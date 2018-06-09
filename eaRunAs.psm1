$OldExcPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
$Commands = Get-ChildItem -Path "$PSScriptRoot" -Filter '*.ps1' -Recurse
Foreach($Command in $Commands){
    . $Command.FullName
}
$PrivateCommands = Get-ChildItem -Path "$PSScriptRoot\Private Commands" -Filter '*.ps1'
Foreach($Command in $PrivateCommands){
    #. $Command.FullName
}
Set-ExecutionPolicy -ExecutionPolicy $OldExcPolicy -Scope Process

Export-ModuleMember -Function $Commands.BaseName