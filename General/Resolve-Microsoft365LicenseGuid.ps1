function Resolve-Microsoft365LicenseGuid {
    <#
    .SYNOPSIS
        Resolves licensing GUIDs to human readable information
    .DESCRIPTION
        Resolves a PowerShell or Graph API license GUID to humnan readable information from the Microsoft 365 "Product names and service plan identifiers for licensing" information
    .PARAMETER param1
    .NOTES
        Author: Jethro Underwood - jethro.underwood@regenit.cloud
        Version: 0.1
    .EXAMPLE
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][String[]]$licenseGuid,
        [string]$csvPath
    )
    $csvUri = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
    If ($csvPath) {
        Write-Verbose -Message "Attempting to import Microsoft 365 license information via CSV from specified path"
        Try {
            $licenseFile = Import-CSV -Path $csvPath
        } Catch {
            Write-Warning -Message "Failed to import CSV file from $csvPath"
        }
    } else {
        Write-Verbose -Message "Attempting to import Microsoft 365 license information via web"
        Try {
            $licenseFile = Invoke-RestMethod -Method GET -Uri $csvUri | ConvertFrom-CSV
        } Catch {
            Write-Warning -Message "Failed to download CSV file from Microsoft"
        }
    }
    ForEach ($guid in $licenseGuid) {
        #No requirement for included service plans for this activity so they'r essentially discarded
        $license = $licenseFile -Match $guid | Select-Object -First 1
        [pscustomobject]@{
            ProductDisplayName = $license.'Product_Display_Name'
            licenseGuid = $license.GUID
            ServicePlanName = $license.'Service_Plan_Name'
            ServicePlanFriendlyName = $license.'Service_Plans_Included_Friendly_Names'
        }
    }
}
