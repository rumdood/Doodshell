function Get-YesNoResponse {
    Param(
        [string] $question
    )

    do {
        try {
            [ValidateSet('Y','N', '')]$answer = $(Write-Host $question -ForegroundColor Yellow -NoNewline; Read-Host)
        } catch {
            Write-Error "Invalid Entry - it's a Yes or No question"
        }
    } until ($answer -in 'Y', 'N', '')

    return $answer -eq 'Y'
}