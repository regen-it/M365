function Get-MailboxSize {
    <#
    .SYNOPSIS
        Gets a simple size report of a mailbox in Exchange Online
    .DESCRIPTION
        Gets a simple size report of a mailbox in Exchange Online. The default output provides the mailbox size in Mb. Accepts pipeline input
    .PARAMETER userPrincipalName
        The PrimarySmtpAddress or UserPrincipalName of the mailbox to check
    .PARAMETER Size
        The size that is used in the output. Defaults to Mb if not specified. Accepted values are Gb, Mb, Kb, b
    .NOTES
        Author: Author: jethro@regenit.cloud / https://github.com/regen-it
        Version: 1.2
    .EXAMPLE
        PS> Get-MailboxSizeReport -UserPrincipalName user@mailbox.com -SizeFormat Mb
    .EXAMPLE
        PS> Get-Mailbox user@mailbox.com | Get-MailboxSizeReport -SizeFormat Gb
    .EXAMPLE
        PS> $mailboxes = Get-Mailbox -ResultSize Unlimited
        PS> $mailboxes | Get-MailboxSizeReport
    #>
    [CmdletBinding()]
    Param (
        [Parameter(
            Position = 0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [string[]]$userPrincipalName,
        [ValidateSet(
            'Gb', 'Mb', 'Kb', 'B')]
            [string]$size = "Mb"
    )
    Begin {}
    Process {
        $mailboxes = $userPrincipalName | ForEach-Object -Process {Get-Mailbox -Identity $_}
        ForEach ($mailbox in $mailboxes) {
            $mailboxStats = Get-MailboxStatistics -Identity $mailbox.PrimarySmtpAddress
            $byteValue = [INT64](($mailboxStats.TotalItemSize.Value -split "B ")[1] -replace '[(), bytes]','')
            $output = [PSCustomObject]@{
                DisplayName = $mailbox.DisplayName
                PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
                MailboxType = $mailbox.RecipientTypeDetails
            }
            switch ($size) {
                "GB" {
                    $mailboxSize = (($byteValue/1Gb).ToString()).Substring(0,4)
                    $output | Add-Member -MemberType NoteProperty MailboxSizeGb -Value $mailboxSize
                }
                "MB" {
                    $mailboxSize = ($byteValue/1Mb).ToString('.')
                    $output | Add-Member -MemberType NoteProperty MailboxSizeMb -Value $mailboxSize
                }
                "KB" {
                    $mailboxSize = ($byteValue/1Kb).ToString('.')
                    $output | Add-Member -MemberType NoteProperty MailboxSizeKb -Value $mailboxSize
                }
                "B" {
                    $mailboxSize = $byteValue
                    $output | Add-Member -MemberType NoteProperty MailboxSizeBytes -Value $mailboxSize}
            }
            $output
        }
    }
    End {}
}
<#
#TODO remove duplicate mailbox lookup when accepting mailbox type from pipeline
#>
