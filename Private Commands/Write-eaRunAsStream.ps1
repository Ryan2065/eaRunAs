Function Write-eaRunAsStream {
    Param(
        [object]$StreamRecord
    )
    if($null -ne $StreamRecord){
        Switch($StreamRecord.GetType().Name) {
            'VerboseRecord' {
                if(-not [string]::IsNullOrEmpty($StreamRecord.Message)){
                    Write-Verbose -Message $StreamRecord.Message
                }
            }
        }
    }
}