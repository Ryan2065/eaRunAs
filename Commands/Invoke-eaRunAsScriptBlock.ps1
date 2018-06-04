Function Invoke-eaRunAsScriptBlock {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        [Parameter(Mandatory=$true)]
        [pscredential]$Credential,
        [Parameter(Mandatory=$false)]
        [hashtable]$Parameters,
        [Parameter(Mandatory=$false)]
        [string[]]$ImportModules,
        [Parameter(Mandatory=$false)]
        [hashtable]$ImportVariables,
        [Parameter(Mandatory=$false)]
        [int]$LogonType = 9
    )

    $InternalFunctionsToAdd = 'Set-eaRunAsRunspaceToken'

    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if($PSBoundParameters.ContainsKey('ImportModules')){
        $null = $InitialSessionState.ImportPSModule($ImportModules)
    }
    if($PSBoundParameters.ContainsKey('ImportVariables')){
        foreach($Variable in $ImportVariables.Keys){
            $tempVariable = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $Variable, $ImportVariables[$Variable], ''
            $null = $InitialSessionState.Variables.Add($tempVariable)
        }
    }

    foreach($InternalFunction in $InternalFunctionsToAdd){
        $InternalFunctionObject = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $InternalFunction, (Get-Content Function:\$InternalFunction)
        $null = $InitialSessionState.Commands.Add($InternalFunctionObject)
    }

    $eaCredential = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'eaCredential', $Credential, ''
    $null = $InitialSessionState.Variables.Add($eaCredential)
    $eaScriptBlock = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'eaScriptBlock', $ScriptBlock, ''
    $null = $InitialSessionState.Variables.Add($eaScriptBlock)
    $eaParameters = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'eaParameters', $Parameters, ''
    $null = $InitialSessionState.Variables.Add($eaParameters)
    $eaLogonType = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'eaLogonType', $LogonType, ''
    $null = $InitialSessionState.Variables.Add($eaLogonType)
    $StreamPreferences = @{
        'Verbose' = $VerbosePreference
        'Debug' = $DebugPreference
        'Error' = $ErrorActionPreference
        'Progress' = $ProgressPreference
        'Warning' = $WarningPreference
    }
    if($PSBoundParameters['Verbose']) {
        $StreamPreferences.Verbose = [System.Management.Automation.ActionPreference]::Continue
    }
    if($PSBoundParameters['Debug']) {
        $StreamPreferences.Debug = [System.Management.Automation.ActionPreference]::Continue
    }
    $eaStreamPreference = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'eaStreamPreference', $StreamPreferences, ''
    $null = $InitialSessionState.Variables.Add($eaStreamPreference)
    $Runspace = [runspacefactory]::CreateRunspace($InitialSessionState)
    $null = $Runspace.Open()
    $PowerShell = [PowerShell]::Create()
    $PowerShell.Runspace = $Runspace
    $RunScriptBlock = {
        $VerbosePreference = $eaStreamPreference.Verbose
        $null = Set-eaRunAsRunspaceToken -Credential $eaCredential -LogonType $eaLogonType
        $DebugPreference = $eaStreamPreference.Debug
        $ErrorActionPreference = $eaStreamPreference.Error
        $ProgressPreference = $eaStreamPreference.Progress
        $WarningPreference = $eaStreamPreference.Warning
        if($null -ne $eaParameters){
            . $eaScriptBlock @eaParameters
        }
        else {
            . $eaScriptBlock
        }
        $null = [System.Security.Principal.WindowsIdentity]::Impersonate(0)
    }
    $null = $PowerShell.AddScript($RunScriptBlock.ToString())
    $PSObject = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
    $BeginInvoke = $PowerShell.BeginInvoke($PSObject, $PSObject)
    $StreamsToCollect = 'Verbose','Progress','Warning','Debug','Error'
    while($false -eq $BeginInvoke.IsCompleted){
        Start-sleep -Milliseconds 100
        if($PSObject.Count -gt 0){
            $PSObject.ReadAll()
        }
        foreach($St in $StreamsToCollect) {
            if($PowerShell.Streams.$St.Count -gt 0){
                foreach($rec in $PowerShell.Streams.$St.ReadAll()){
                    Write-eaRunAsStream -StreamRecord $rec
                }
            }
        }
    }
    if($PSObject.Count -gt 0){
        $PSObject.ReadAll()
    }
    foreach($St in $StreamsToCollect) {
        if($PowerShell.Streams.$St.Count -gt 0){
            foreach($rec in $PowerShell.Streams.$St.ReadAll()){
                Write-eaRunAsStream -StreamRecord $rec
            }
        }
    }
    if($PowerShell.HadErrors) {
        $threw = $false
        if($PowerShell.InvocationStateInfo.State -eq 'Failed'){
            if($null -ne $PowerShell.InvocationStateInfo.Reason) {
                $threw = $true
                throw $PowerShell.InvocationStateInfo.Reason
            }
        }
        if($false -eq $threw) {
            $null = $PowerShell.EndInvoke($BeginInvoke)
        }
    }
    $PowerShell.Dispose()
    $Runspace.Dispose()
}