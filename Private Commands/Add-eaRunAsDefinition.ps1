Function Add-eaRunAsDefinition {
    <#
    .SYNOPSIS
    Adds the Runas definition in RunAsDefinition.cs to the current runspace
    
    .DESCRIPTION
    Will get the content of the file RunAsDefinition.cs and then add it with Add-Type
    
    .EXAMPLE
    Add-eaRunAsDefinition
    
    .NOTES
    .Author: Ryan Ephgrave
    #>
    $RunAsDefinition = Get-Content -Path "$PSScriptRoot\RunAsDefinition.cs" -Raw
    Add-Type -TypeDefinition $RunAsDefinition -Language CSharp -Debug:$false -ErrorAction SilentlyContinue
}