# eaRunAs

eaRunAs is a module to help run code with alternate credentials cross domain or in environments that do not allow other methods like CredSSP. Install the module with the commmand:

```PowerShell
Install-Module -Name 'eaRunAs'
```

Currently, eaRunAs has only one command: Invoke-eaRunAsScriptBlock

You can use this command in the following manner:

```PowerShell
Invoke-eaRunAsScriptBlock -Credential $mycreds -ScriptBlock {
    Get-WMIObject -ComputerName 'REMOTECOMPUTER' -Class Win32_OperatingSystem
}
```

The above command will start a new process of PowerShell with CreateProcessWithLogonW (similar to what PSExec and runas.exe do) and the credentials will only be enabled for commands that go over the network. This means if you try to access local resources it will use your local credentials, but anything over the network will be accessed with the supplied credentials.

The benefits of this approach are:

* The computer you run the command on doesn't need to be on the domain you are connecting to
* You can run the code without having to worry about the double hop issue! This just works out of the box without any fancy domain settings or computer settings to reach out to remote computers with alternate credentials and not having to worry about it using the NETWORK_SERVICE account.
* Even though network resources are using the remote credentials, local stuff will use your local account so you can still write logs to $env:temp or anywhere else on your computer and it will use your local profile
* Since the account doesn't actually log into the system, you don't need to set up any special permissions for the account for this method to work. No log on locally permissions needed!

As always, this isn't a perfect approach, the cons are:

* It really will use your local account to access local resources and will not tell you it's doing it. If you forget, troubleshooting can be hard!
* There are no good errors if you supply an incorrect password, which can lead to account lockouts. I'll look at adding a second function later to verify the password before starting if on the same domain.
* This will not work if launched from the LOCAL SYSTEM account. The base Windows method I'm using to launch the process needs the SID of the local account to create the new process, and LOCAL SYSTEM has no SID. 


Please let me know if you want anything added! Features I'm looking to add in the future:

1) Run as Local System
2) Verify password before launching

