Function Invoke-eaRunAsScriptBlock {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Runspace', 'Process')]
        [string]$RunAsMethod,
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        [Parameter(Mandatory=$true)]
        [pscredential]$Credential,
        [Parameter(Mandatory=$false)]
        [hashtable]$Parameters,
        [Parameter(Mandatory=$false)]
        [string[]]$ImportModules,
        [Parameter(Mandatory=$false)]
        [hashtable]$ImportVariables = @{},
        [Parameter(Mandatory=$false)]
        [int]$LogonType = 9
    )
    
    $Runspace = $null
    try{
        if($RunAsMethod -eq 'Process') {
            $CreateProcessID = Invoke-eaCreateProcessAsUserW -Credential $Credential -FullExePath (Get-Process -Id $PID).Path -Arguments '-NoExit'
            $Runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(
                (New-Object -TypeName System.Management.Automation.Runspaces.NamedPipeConnectionInfo -ArgumentList @($CreateProcessID)), 
                $Host, 
                ([System.Management.Automation.Runspaces.TypeTable]::LoadDefaultTypeFiles())
            )
        }
        else {
            $Runspace = [runspacefactory]::CreateRunspace()
        }
        $null = $Runspace.Open()
    }
    catch {
        Write-Warning 'Was not able to create and open the runspace!'
        throw
    }
    $PowerShell = [powershell]::Create()
    $PowerShell.Runspace = $Runspace

    $ModulePaths = @()
    Foreach($ImportModule in $ImportModules){
        if($ModuleToImport = Get-Module -Name $ImportModule -ErrorAction SilentlyContinue){
            $ModulePaths += $ModuleToImport.ModuleBase
        }
    }

    $ImportVariables['eaScriptBlock'] = $ScriptBlock
    $ImportVariables['eaParameters'] = $Parameters
    $ImportVariables['ErrorActionPreference'] = $ErrorActionPreference
    $ImportVariables['VerbosePreference'] = $VerbosePreference
    $ImportVariables['DebugPreference'] = $DebugPreference
    $ImportVariables['ProgressPreference'] = $ProgressPreference
    $ImportVariables['WarningPreference'] = $WarningPreference
    if($PSBoundParameters['Verbose']) {
        $ImportVariables['VerbosePreference'] = [System.Management.Automation.ActionPreference]::Continue
    }
    if($PSBoundParameters['Debug']) {
        $ImportVariables['DebugPreference'] = [System.Management.Automation.ActionPreference]::Continue
    }

    Switch($RunAsMethod){
        'Runspace' {
            $ImportVariables['eaCredential'] = $Credential
            $ImportVariables['eaLogonType'] = $LogonType
            $ImportVariables['SetRunspaceToken'] = $true
        }
        'Process' {
            $ImportVariables['SetRunspaceToken'] = $false
        }
    }


    # In the "Process" method, I cannot set the InitialSessionState, so instead both methods use this scriptblock to set initial
    # Modules and variables
    $InitialSessionScriptBlock = {
        Param(
            [string[]]$ModulePaths,
            [hashtable]$ImportVariables
        )
        if($null -ne $ModulePaths){
            foreach($ModulePath in $ModulePaths){
                Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
            }
        }
        if($null -ne $ImportVariables){
            Foreach($key in $ImportVariables.Keys){
                Set-Variable -Name $Key -Value $ImportVariables[$key] -ErrorAction SilentlyContinue
            }
        }
    }
    
    $null = $PowerShell.AddScript($InitialSessionScriptBlock.ToString())
    $null = $PowerShell.AddArgument($ModulePaths)
    $null = $PowerShell.AddArgument($ImportVariables)
    $null = $PowerShell.Invoke()
    
    #endregion


    if($RunAsMethod -eq 'Runspace'){
        if($eaRunAsModule = Get-Module -Name 'eaRunAs' -ErrorAction SilentlyContinue){
            $RunspaceTokenScript = Get-Content "$($eaRunAsModule.ModuleBase)\Private Commands\Set-eaRunAsRunspaceToken.ps1" -Raw
            $PowerShell.AddScript($RunspaceTokenScript)
            $null = $PowerShell.Invoke()
        }
        $PowerShell.AddScript('$null = Set-eaRunAsRunspaceToken -Credential $eaCredential -LogonType $eaLogonType')
        $null = $PowerShell.Invoke()
    }
    $ScriptBlockString = $ScriptBlock.ToString()
    $null = $PowerShell.AddScript($ScriptBlockString)
    if($null -ne $Parameters){
        foreach($key in $Parameters.Keys){
            $null = $PowerShell.AddParameter($key, $Parameters[$key])
        }
    }
    
    $StreamsToCollect = 'Verbose','Progress','Warning','Debug','Error'
    if($RunAsMethod -eq 'Process') {
        $PowerShell.Invoke()
    }
    else {
        $PSObject = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        $BeginInvoke = $PowerShell.BeginInvoke($PSObject, $PSObject)
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
            if($BeginInvoke -ne $null){
                $null = $PowerShell.EndInvoke($BeginInvoke)
            }
            else {
                throw "Script had an unretrievable error"
            }
        }
    }
    $null = $PowerShell.Dispose()
    $null = $Runspace.Dispose()
    if($RunAsMethod -eq 'Process'){
        if(Get-Process -Id $CreateProcessID -ErrorAction SilentlyContinue) {
            $null = Stop-Process -Id $CreateProcessID -Force
        }
    }
}