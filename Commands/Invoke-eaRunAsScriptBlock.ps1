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
        [hashtable]$ImportVariables = @{}
    )
    
    $Runspace = $null
    try{
        $CreateProcessID = Invoke-eaCreateProcessAsUserW -Credential $Credential -FullExePath (Get-Process -Id $PID).Path -Arguments '-NoExit'
        $Runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(
            (New-Object -TypeName System.Management.Automation.Runspaces.NamedPipeConnectionInfo -ArgumentList @($CreateProcessID)), 
            $Host, 
            ([System.Management.Automation.Runspaces.TypeTable]::LoadDefaultTypeFiles())
        )
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

    $ScriptBlockString = $ScriptBlock.ToString()
    $null = $PowerShell.AddScript($ScriptBlockString)
    if($null -ne $Parameters){
        foreach($key in $Parameters.Keys){
            $null = $PowerShell.AddParameter($key, $Parameters[$key])
        }
    }
    try{
        $PSObject = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        $BeginInvoke = $PowerShell.BeginInvoke($PSObject, $PSObject)
        while($false -eq $BeginInvoke.IsCompleted){
            Start-sleep -Milliseconds 50
            if($PSObject.Count -gt 0){
                $PSObject.ReadAll()
            }
        }
        if($PSObject.Count -gt 0){
            $PSObject.ReadAll()
        }
        if($PowerShell.InvocationStateInfo.State -eq 'Failed'){
            if($null -ne $PowerShell.InvocationStateInfo.Reason) {
                throw $PowerShell.InvocationStateInfo.Reason
            }
        }
    }
    catch [System.Management.Automation.RemoteException] {
        if($PowerShell.InvocationStateInfo.State -eq 'Failed'){
            if($null -ne $PowerShell.InvocationStateInfo.Reason) {
                if($null -ne $PowerShell.InvocationStateInfo.Reason.SerializedRemoteInvocationInfo) {
                    $WarningMessage = ''
                    $MemberProperties = $PowerShell.InvocationStateInfo.Reason.SerializedRemoteInvocationInfo | Get-Member -MemberType Property
                    foreach($Property in $MemberProperties.Name){
                        $WarningMessage += "`"$($Property)`": $($PowerShell.InvocationStateInfo.Reason.SerializedRemoteInvocationInfo.$Property)`n"
                    }
                    Write-Warning -Message "Detailed Error Message:`n$($WarningMessage)"
                }
                throw $PowerShell.InvocationStateInfo.Reason
            }
        }
        else {
            throw
        }
    }
    finally {
        $null = $Runspace.Dispose()
        $null = $PowerShell.Dispose()
        if(Get-Process -Id $CreateProcessID -ErrorAction SilentlyContinue) {
            $null = Stop-Process -Id $CreateProcessID -Force -ErrorAction SilentlyContinue
        }
    }
}