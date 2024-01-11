function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings, $QueueItem)
    
    If ($Settings.remediate) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox'
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Started setting default calendar permissions for $($Mailboxes.Count) mailboxes." -sev Info

        # Retrieve the last run status
        $LastRunTable = Get-CIPPTable -Table StandardsLastRun
        $Filter = "RowKey eq 'calDefaults' and PartitionKey eq '{0}'" -f $tenant
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter

        $startIndex = 0
        if ($LastRun -and $LastRun.totalMailboxes -ne $LastRun.processedMailboxes) {
            $startIndex = $LastRun.processedMailboxes
        }
        $SuccessCounter = if ($lastrun.currentSuccessCount) { [int64]$lastrun.currentSuccessCount } else { 0 }
        $UserSuccesses = [HashTable]::Synchronized(@{Counter = $SuccessCounter })
        $processedMailboxes = $startIndex
        $mailboxes = $mailboxes[$startIndex..($mailboxes.Count)]
        Write-Host "CalDefaults Starting at index $startIndex"
        $Mailboxes | ForEach-Object {
            $Mailbox = $_
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{identity = $Mailbox.UserPrincipalName; FolderScope = 'Calendar' } -Anchor $Mailbox.UserPrincipalName | Where-Object { $_.FolderType -eq 'Calendar' } |
                ForEach-Object {
                    try {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdparams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $Settings.permissionlevel } -Anchor $Mailbox.UserPrincipalName 
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $($Settings.permissionlevel)" -sev Debug 
                        $UserSuccesses.Counter++
                    } catch {
                        Write-Host "Setting cal failed: $($_.exception.message)"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($_.exception.message)" -sev Error
                    }
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($_.exception.message)" -sev Error
            }
            $processedMailboxes++
            if ($processedMailboxes % 25 -eq 0) {
                $LastRun = @{
                    RowKey              = 'calDefaults'
                    PartitionKey        = $Tenant
                    totalMailboxes      = $Mailboxes.count
                    processedMailboxes  = $processedMailboxes
                    currentSuccessCount = $UserSuccesses.Counter
                }
                Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
                Write-Host "Processed $processedMailboxes mailboxes"
            }
        }

        $LastRun = @{
            RowKey              = 'calDefaults'
            PartitionKey        = $Tenant
            totalMailboxes      = $Mailboxes.count
            processedMailboxes  = $processedMailboxes
            currentSuccessCount = $UserSuccesses.Counter
        }
        Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force

        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set default calendar permissions for $($UserSuccesses.Counter) out of $($Mailboxes.Count) mailboxes." -sev Info
    }
}