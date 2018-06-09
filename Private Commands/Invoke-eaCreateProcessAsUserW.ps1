Function Invoke-eaCreateProcessAsUserW {
    Param(
        [pscredential]$Credential,
        [string]$FullExePath,
        [string]$Arguments,
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