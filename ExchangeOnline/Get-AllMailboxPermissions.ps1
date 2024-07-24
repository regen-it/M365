<#
.SYNOPSIS
    Developed to provide a single cmdlet to collect all delegate permissions on a mailbox and provide a more report-friendly output
.DESCRIPTION
    Developed to provide a single cmdlet to collect all delegate permissions on a mailbox and provide a more report-friendly output
.PARAMETER Identity
    UserPrincipalName or Mailbox ID
.PARAMETER CombinePermissions
    Specify this switch parameter to roll up the mailbox permissions into a combined output
.EXAMPLE
    Get-AllMailboxPermissions -Identity user@mailbox.com
.NOTES
    Author: jethro@regenit.cloud / https://github.com/regen-it
    Version: 1.0
    Mandatory Dependencies: Exchange Online module: https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps#install-and-maintain-the-exchange-online-powershell-module
#>

function Get-AllMailboxPermissions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][String]$Identity,
        [switch]$CombinePermissions
    )
    Write-Verbose "Checking for connectivity to Exchange Online"
    Function Test-ExchangeOnlineConnection {
        [CmdletBinding()]
        $exoConnection = Get-ConnectionInformation
        If ($exoConnection.Name -like "ExchangeOnline*" -and $exoConnection.TokenStatus -eq "Active") {
            Write-Verbose "Connection to Exchange Online detected"
        } else {
            Write-Warning "Connection to Exchange Online required"
            Break
        }
    }
    Test-ExchangeOnlineConnection
    $permissionRollUp = @()
    $combinedPermissions = @()
    Try {
        Write-Verbose 'Getting mailbox and delegate permissions'
        $mailbox = Get-ExoMailbox -Identity $Identity -PropertySets All -ErrorAction Stop
        $sendAsPermissions = Get-RecipientPermission -Identity $Identity -ErrorAction Stop | Where-Object -FilterScript { $_.Trustee -ne 'NT Authority\Self' -and $_.Trustee -ne $mailbox.PrimarySmtpAddress}
        $fullAccessPermissions = Get-MailboxPermission -Identity $Identity -ErrorAction Stop | Where-Object -FilterScript { $_.User -ne 'NT Authority\Self' -and $_.User -ne $mailbox.PrimarySmtpAddress}
        Write-Verbose "Successfully found mailbox and permissions for $($mailbox.userprincipalname)"
        If ($mailbox.grantSendOnBehalfTo) {
            Write-Verbose "Mailbox has send on behalf permissions, processing"
            $mailbox.grantSendOnBehalfTo -split ', ' | ForEach-Object -Process {
                $delegate = Get-ExoMailbox -Identity $_
                $sendOnBehalfPermissionsObject = [PSCustomObject]@{
                    Mailbox     = $mailbox.PrimarySmtpAddress
                    Delegate    = $delegate.PrimarySmtpAddress
                    Permissions = 'SendOnBehalf'
                }
                If ($CombinePermissions) {
                    $permissionRollUp += $sendOnBehalfPermissionsObject
                } else {
                    $sendOnBehalfPermissionsObject
                }
            }
        } else {
            Write-Verbose 'Mailbox does not have send on behalf permissions assigned, skipping'
        }
        If ($sendAsPermissions) {
            Write-Verbose 'Mailbox has send as permissions, processing'
            ForEach ($permission in $sendAsPermissions) {
                $sendAsPermissionsObject = [PSCustomObject]@{
                    Mailbox     = $mailbox.PrimarySmtpAddress
                    Delegate    = $permission.Trustee
                    Permissions = 'SendAs'
                }
                If ($CombinePermissions) {
                    $permissionRollUp += $sendAsPermissionsObject
                } else {
                    $sendAsPermissionsObject
                }
                
            }
        } else {
            Write-Verbose 'Mailbox does not have send as permissions assigned, skipping'
        }
        If ($fullAccessPermissions) {
            Write-Verbose 'Mailbox has full access permissions, processing'
            ForEach ($permission in $fullAccessPermissions) {
                $fullAccessPermissionsObject = [PSCustomObject]@{
                    Mailbox     = $mailbox.PrimarySmtpAddress
                    Delegate    = $permission.user
                    Permissions = 'FullAccess'
                }
                If ($CombinePermissions) {
                    $permissionRollUp += $fullAccessPermissionsObject
                } else {
                    $fullAccessPermissionsObject
                }
            }
        } else {
            Write-Verbose 'Mailbox does not have full access permissions assigned, skipping'
        }
        If ($CombinePermissions) {
            Write-Verbose 'Collected permissions to be combined, starting'
            $mailboxPermissionsGroups = $permissionRollUp | Group-Object -Property Mailbox
            ForEach ($permissionGroup in $mailboxPermissionsGroups) {
                $mailboxName = $permissionGroup.Name
                $delegatePermissions = $permissionGroup.Group | Group-Object -Property Delegate
                ForEach ($delegate in $delegatePermissions) {
                    $delegateName = $delegate.name
                    $sendonBehalf = $null
                    $sendAs = $null
                    $fullAccess = $null
                    switch -Wildcard ($delegate.Group) {
                        "*SendOnBehalf*" {$sendonBehalf = '✓'}
                        "*SendAs*" {$sendAs = '✓'}
                        "*FullAccess*" {$fullAccess = '✓'}
                    }
                    $rolledUpPermissions = [PSCustomObject]@{
                        Mailbox      = $mailboxName
                        Delegate     = $delegateName
                        SendOnBehalf = $sendOnBehalf
                        SendAs       = $sendAs
                        FullAccess   = $fullAccess
                    }
                    $combinedPermissions += $rolledUpPermissions
                }
                $combinedPermissions
            }
        }
    } Catch [Microsoft.Exchange.Management.RestApiClient.RestClientException] {
        If ($error[0].exception.message -match "couldn't be found") {
        Write-Warning -Message "Mailbox for $($Identity) could not be found"
        } else {
            Write-Error -Message "Failed to collect delegate permissions for $($Identity)"
        }
    } Catch {
        Write-Error -Message "Failed to collect delegate permissions for $($Identity)"
    }
}