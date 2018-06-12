Function Invoke-eaCreateProcessAsUserW {
    <#
    .SYNOPSIS
    Creates a new process running under alternate network credentials
    
    .DESCRIPTION
    uses CreateProcessAsUserW to create a new process that will access local resources as you and 
    network resources as the remote user
    
    .PARAMETER Credential
    Credential with the domain information to connect to the remote machine
    
    .PARAMETER FullExePath
    Full path to the exe you wish to run
    
    .PARAMETER Arguments
    Command line arguments to send to the exe. Needs to be a string, not array
    
    .PARAMETER ShowUI
    Do we want the UI shown, or hidden?
    
    .EXAMPLE
    $CreateProcessID = Invoke-eaCreateProcessAsUserW -Credential $Credential -FullExePath (Get-Process -Id $PID).Path -Arguments '-NoExit' -ShowUI
    This will launch a new process of PowerShell
    
    .NOTES
    .Author: Ryan Ephgrave
    #>
    Param(
        [Parameter(Mandatory=$true)]
        [pscredential]$Credential,
        [Parameter(Mandatory=$true)]
        [string]$FullExePath,
        [Parameter(Mandatory=$false)]
        [string]$Arguments,
        [Parameter(Mandatory=$false)]
        [switch]$ShowUI
    )
    Add-eaRunAsDefinition
   
    #region STARTUPINFO
    $StartupInfo = New-Object -TypeName 'STARTUPINFO'
    $StartupInfo.dwFlags = 0x00000001
    $StartupInfo.wShowWindow = 0x0000
    if($ShowUI) {
        $StartupInfo.wShowWindow = 0x0001
    }
    $StartupInfo.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($StartupInfo)
    #endregion

    $ProcessInfo = New-Object -TypeName 'PROCESS_INFORMATION'
    $LogonType = 2
    $CurrentPath = $PSScriptRoot
    $Result = [eaCreateProcessW]::CreateProcessWithLogonW(
        $Credential.GetNetworkCredential().UserName,
        $Credential.GetNetworkCredential().Domain,
        $Credential.GetNetworkCredential().Password,
        $LogonType,
        $FullExePath,
        $Arguments,
        0x04000000,
        $null,
        $CurrentPath,
        [ref]$StartupInfo,
        [ref]$ProcessInfo
    )
    if(-not $Result) {
        throw 'Could not start the process!'
    }
    else {
        return $ProcessInfo.dwProcessId
    }
}