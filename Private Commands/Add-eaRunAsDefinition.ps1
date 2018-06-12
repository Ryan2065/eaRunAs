Function Add-eaRunAsDefinition {
    $RunAsDefinition = Get-Content -Path "$PSScriptRoot\RunAsDefinition.cs" -Raw
    Add-Type -TypeDefinition $RunAsDefinition -Language CSharp -Debug:$false -ErrorAction SilentlyContinue
}