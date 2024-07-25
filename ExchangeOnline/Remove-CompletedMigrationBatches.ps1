<#
.SYNOPSIS
    Developed to make it easier to remove stale migration jobs
.DESCRIPTION
    Developed to make it easier to remove stale migration jobs
    Used in automation to keep migration batch numbers under control and avoid the hitting the batch limit where a business function was automatically migrating users
.PARAMETER OlderThan
    Specify in days how many far back you would like to remove migration batches
.PARAMETER RemoveNonPerfectBatches
    Specify this switch parameter to remove any completed batches that do not have a data consistency score of Perfect
.EXAMPLE
    Remove-CompletedMigrationBatches -OlderThan 10
.NOTES
    Author: jethro@regenit.cloud / https://github.com/regen-it
    Version: 1.0
    Mandatory Dependencies: Exchange Online module: https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps#install-and-maintain-the-exchange-online-powershell-module
#>

function Remove-CompletedMigrationBatches {
    [cmdletbinding()]
    param (
        [Int32]$OlderThan = 7, #TODO add parameter validation
        [switch]$RemoveNonPerfectBatches
    )
    Write-Verbose -Message "Checking for connectivity to Exchange Online"
    Function Test-ExchangeOnlineConnection {
        [CmdletBinding()]
        $exoConnection = Get-ConnectionInformation
        If ($exoConnection.Name -like "ExchangeOnline*" -and $exoConnection.TokenStatus -eq "Active") {
            Write-Verbose -Message "Connection to Exchange Online detected"
        } else {
            Write-Warning -Message "Connection to Exchange Online required"
            Break
        }
    }
    Test-ExchangeOnlineConnection
    $output = @()
    $dateTime = (Get-Date).AddDays(-$OlderThan)
    Try{
        Write-Verbose -Message "Getting completed migration batches"
        $migrationBatches = Get-MigrationBatch -Status Completed -ResultSize Unlimited -ErrorAction Stop | Where-Object {$_.CreationDateTime -lt $dateTime}
        If ($RemoveNonPerfectBatches) {
            Write-Verbose -Message "All completed migration batches created within the last $($OlderThan) days will be removed"
        } else {
            Write-Verbose -Message "All completed migration batches with a perfect data consistency score created with the last $($OlderThan) days be removed"
            $migrationBatches = $migrationBatches | Where-Object {$_.DataConsistencyScore.value -eq 'Perfect'}
        }
        Write-Verbose "Got migration batches for removal"
    } Catch {
        Write-Error -Message "Failed to collect migration batches"
    }
    Write-Verbose "Removing $($migrationBatches.count) migration batches"
    ForEach ($batch in $migrationBatches) {
        Try {
            Write-Verbose -Message "Successfully removed $($batch.Identity)"
            Remove-MigrationBatch -Identity $batch.Identity -Confirm:$false
            $batchRemoved = $true
            $errorMessage = $null
        } catch {
            Write-Warning -Message "Failed to remove $($batch.Identity)"
            $batchRemoved = $false
            $errorMessage = $error[0].exception.message
        }
        $outputObject = [PSCustomObject]@{
            Identity = $batch.Identity
            Status = $batch.status
            Type = $batch.MigrationType
            TotalCount = $batch.TotalCount
            BatchRemoved = $batchRemoved
            Error = $errorMessage
        }
        $output += $outputObject
    }
    Write-Verbose "Successfully removed migration batches"
    $output
}
