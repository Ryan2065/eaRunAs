Function Set-eaRunAsRunspaceToken {
    <#
    .SYNOPSIS
    Will make the current runspace run under a different token
    
    .DESCRIPTION
    Makes the current runspace thread run under a different token. Doesn't always filter through to all PowerShell commands though
    
    .PARAMETER Credential
    Credential you want the runspace to run under
    
    .PARAMETER LogonType
    Logon Type
    
    .PARAMETER LogonProvider
    Logon Provider
    
    .EXAMPLE
    Set-eaRunAsRunspaceToken -Credential $MyCred
    
    .NOTES
    .Author: Ryan Ephgrave
    
    #>
    Param(
        [pscredential]$Credential,
        [int]$LogonType = 9,
        [int]$LogonProvider = 0
    )
    $null = Add-Type -Namespace eaRunAs -Name RunAs -MemberDefinition @' 
    [DllImport("advapi32.dll", SetLastError = true)] 
    public static extern bool LogonUser(string user, string domain, string password, int logonType, int logonProvider, out IntPtr token); 
 
    [DllImport("kernel32.dll", SetLastError = true)] 
    public static extern bool CloseHandle(IntPtr handle); 
'@  -ErrorAction SilentlyContinue -Debug:$false
    $VerboseMessage =  "UserName: $($Credential.GetNetworkCredential().UserName)`n"
    $VerboseMessage += "Domain: $($Credential.GetNetworkCredential().Domain)`n"
    $VerboseMessage += "LogonType: $($LogonType)`n"
    Write-Verbose -Message $VerboseMessage
    [System.IntPtr]$phToken = 0
    $WasSuccessful = [eaRunAs.RunAs]::LogonUser(
        $Credential.GetNetworkCredential().UserName,
        $Credential.GetNetworkCredential().Domain,
        $Credential.GetNetworkCredential().Password,
        $LogonType,
        $LogonProvider,
        [ref]$phToken
    )
    if($WasSuccessful){
        [System.Security.Principal.WindowsIdentity]::Impersonate($phToken)
        [void][eaRunAs.RunAs]::CloseHandle($phToken) 
    }
    else {
        throw "Could not get token!"
    }
}