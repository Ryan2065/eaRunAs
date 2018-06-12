Function Invoke-eaRunAsScriptBlock {
    <#
    .SYNOPSIS
    Run scriptblock as another user using CreateProcessWithLogonW so it will run with net only credentials
    
    .DESCRIPTION
    This will create another process of PowerShell using the method CreateProcessWithLogonW
    and then run the supplied scriptblock in this separate process. This will allow you to run 
    network commands with the supplied credentials but without using up the first hop. Note, local
    resources will NOT use the supplied credentials, only remote calls to other computers will.
    
    .PARAMETER ScriptBlock
    Scriptblock to run
    
    .PARAMETER Credential
    Credentials to run the scriptblock as
    
    .PARAMETER Parameters
    Parameters to pass the scriptblock
    
    .PARAMETER ImportModules
    Modules to import into the scriptblock. Just supply the module name and make sure the current
    session can see the modules
    
    .PARAMETER ImportVariables
    Variables to import. Stored as a Hashtable so the key will be the name of the variable and the value will be 
    what you want the variable to be set as
    
    .EXAMPLE
    Invoke-eaRunAsScriptBlock -Credential $MyCredential -ScriptBlock { Get-WMIObject -ComputerName "MyRemoteComputer" -Class Win32_OperatingSystem }
    This will run the Get-WMIObject command on the remote computer.
    
    .NOTES
    .Author: Ryan Ephgrave
    
    #>
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