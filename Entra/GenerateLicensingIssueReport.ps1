function Get-LicensingIssueReport {
    <#
    .SYNOPSIS
        Generates a report of users with licensing errors in the last X days 
    .DESCRIPTION
        Developed to help out since Microsoft removed the ability to manage licenses in Entra. Used to help the remediation of user licensing errors in Microsoft 365. This function will search the audit logs for licensing errors in the last X days and generate a report of the users with errors and the details of the errors.
    .PARAMETER DaysToSearch
        The number of days to search back in the audit logs for licensing errors. Default is 5 days.
    .NOTES
        Author: Jethro Underwood - jethro@regenit.cloud
        Version: 1.0
        Info: $licenseSku switch is not built out and only contains core licensing I was looking for at the time. Will eventually have this done more intelligently so it doesn't have to be manually maintained
    .EXAMPLE
    #>
    [CmdletBinding()]
    param (
        [Parameter()][Int]
        $DaysToSearch = 5
    )
    Write-Verbose -Message "Searching the last $($DaysToSearch) days of the audit log for users with licensing errors"
    $dateTime = ((Get-Date).AddDays(-$DaysToSearch)).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $auditLogsUri = 'https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?$filter=activityDisplayName eq ''Change user license'' and result eq ''failure''' + " and activityDateTime gt $($dateTime)"
    $licensingFailures = Invoke-MgGraphRequest -Method GET -Uri $auditLogsUri
    $failedUsers = $licensingFailures.value.targetResources.Id | Select-Object -Unique
    Write-Verbose -Message "Collecting licensing details for each user found"
    ForEach ($failedUser in $failedUsers) {
        Try {
            $userUri = 'https://graph.microsoft.com/v1.0/users/' + "$($failedUser)" + '?$select+=UserPrincipalName,DisplayName,LicenseAssignmentStates'
            $userObject = Invoke-MgGraphRequest -Method GET -Uri $userUri
            If ($userObject.LicenseAssignmentStates.State -contains "Error" -or $userObject.LicenseAssignmentStates.state -contains "ActiveWithError") {
                Write-Verbose -Message "Licensing errors found for $($userObject.userPrincipalName), collecting details"
                ForEach ($licenseAssignment in $userObject.LicenseAssignmentStates | Where-Object -FilterScript { $_.State -match "Error" }) {
                    $licenseAssignmentGroupUri = 'https://graph.microsoft.com/v1.0/groups/' + "$($licenseAssignment.assignedByGroup)" + '?$select=DisplayName,id'
                    $licenseAssignmentGroupObject = Invoke-MgGraphRequest -Uri $licenseAssignmentGroupUri
                    $licenseSku = $licenseAssignment.SkuId
                    switch ($licenseSku) {
                        '05e9a617-0261-4cee-bb44-138d3ef5d965' { $licenseFriendlyName = "M365 E3" }
                        '66b55226-6b4f-492c-910c-a3b7a3c9d993' { $licenseFriendlyName = "M365 F3" }
                        'a403ebcc-fae0-4ca2-8c8c-7a907fd6c235' { $licenseFriendlyName = "Microsoft Fabric (Free)" }
                        '639dec6b-bb19-468b-871c-c5c441c4b0cb' { $licenseFriendlyName = "Copilot for Microsoft 365" }
                        'c5928f49-12ba-48f7-ada3-0d743a3601d5' { $licenseFriendlyName = "Visio Plan 2" }
                        Default { $licenseFriendlyName = $licenseSku }
                    }
                    [PSCustomObject]@{
                        UserPrincipalName      = $userObject.userPrincipalName
                        UserObjectId           = $failedUser
                        License                = $licenseFriendlyName
                        LicenseAssignedByGroup = $licenseAssignmentGroupObject.displayName
                        GroupId                = $licenseAssignmentGroupObject.id
                    }
                }
            }
            else {
                Write-Verbose -Message "Licensing errors already resolved for $($userObject.userPrincipalName), ignoring"
            }
        } Catch {
            Write-Warning -Message "Failed to collect licensing details for $($failedUser)"
        }
    }
}

#I would recommend using a certificate to authenticate the application you use to connect this and not lazily and insecurely put Client secrets into the script itself. I've just put this here for demonstration purposes
#The below relies on the Import-Excel module - https://www.powershellgallery.com/packages/ImportExcel/7.8.5
#And a registered app that can send mail as a user 
#And I haven't built proper reporting/logging/error handling into the above function or the below so take that into consideration 

$ApplicationClientId = "value"
$ApplicationClientSecret = "value"
$tenantId = "value"
$SecureClientSecret = ConvertTo-SecureString -String $ApplicationClientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationClientId, $SecureClientSecret

Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential

$outputPath = "C:\Powershell\LicenseIssues\LicenseIssues-$(Get-Date -Format dd-MM).xlsx"
$spreadsheetParametrs = @{
    Path          = $outputPath
    WorksheetName = "License Issues"
    AutoSize      = $true
    TableStyle    = 'Medium16'
    BoldTopRow    = $true
}

$licensingIssueReport = Get-LicensingIssueReport

If ($licensingIssueReport) {
    $licensingIssueReport | Export-Excel @spreadsheetParametrs
    $Attachment = $outputPath
    $FileName = (Get-Item -Path $Attachment).name
    $base64string = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Attachment))
    $graphRequestBody = @"
    {
    "message": {
            "subject": "Licensing Error Report for $(Get-Date -Format "dddd MMMM dd")",
            "body": {
            "contentType": "text",
            "content": "$(($licensingIssueReport.UserPrincipalName | Select-Object -Unique).count) user(s) found with licensing issues within the last five days. Please find attached report"
        },
        "toRecipients": [
            {
                "emailAddress": {
                    "address": "user1@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user2@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user3@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user4@email.com"
                }
            }
        ],
    "attachments": [
        {
            "@odata.type": "#microsoft.graph.fileAttachment",
            "name": "$FileName",
            "contentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "contentBytes": "$base64string"
        }
    ]
    },
    "saveToSentItems": "false"
}
"@
    } else {
        $graphRequestBody = @"
    {
    "message": {
            "subject": "Licensing Error Report for $(Get-Date -Format "dddd MMMM dd")",
            "body": {
            "contentType": "text",
            "content": "No users with licensing errors found in the last five days"
        },
        "toRecipients": [
            {
                "emailAddress": {
                    "address": "user1@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user2@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user3@email.com"
                }
            },
            {
                "emailAddress": {
                    "address": "user4@email.com"
                }
            }
        ],
    },
    "saveToSentItems": "false"
}
"@
}

Invoke-MgGraphRequest -Method POST -Uri https://graph.microsoft.com/v1.0/users/reportingemail@domain.com/sendMail -ContentType application/json -Body $graphRequestBody
