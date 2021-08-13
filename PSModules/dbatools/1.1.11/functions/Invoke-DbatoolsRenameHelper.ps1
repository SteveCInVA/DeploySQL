function Invoke-DbatoolsRenameHelper {
    <#
    .SYNOPSIS
        Older dbatools command names have been changed. This script helps keep up.

    .DESCRIPTION
        Older dbatools command names have been changed. This script helps keep up.

    .PARAMETER InputObject
        A piped in object from Get-ChildItem

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsRenameHelper

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper

        Checks to see if any ps1 file in C:\temp\ps matches an old command name.
        If so, then the command name within the text is updated and the resulting changes are written to disk in UTF-8.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper -Encoding Ascii -WhatIf

        Shows what would happen if the command would run. If the command would run and there were matches,
        the resulting changes would be written to disk as Ascii encoded.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $paramrenames = @{
            ExcludeAllSystemDb = 'ExcludeSystem'
            ExcludeAllUserDb   = 'ExcludeUser'
            'Invoke-Sqlcmd2'   = 'Invoke-DbaQuery'
            NetworkShare       = 'SharedPath'
            NoDatabases        = 'ExcludeDatabases'
            NoDisabledJobs     = 'ExcludeDisabledJobs'
            NoJobs             = 'ExcludeJobs'
            NoJobSteps         = 'ExcludeJobSteps'
            NoQueryTextColumn  = 'ExcludeQueryTextColumn'
            NoSystem           = 'ExcludeSystemLogins'
            NoSystemDb         = 'ExcludeSystem'
            NoSystemLogins     = 'ExcludeSystemLogins'
            NoSystemObjects    = 'ExcludeSystemObjects'
            NoSystemSpid       = 'ExcludeSystemSpids'
            UseLastBackups     = 'UseLastBackup'
            PasswordExpiration = 'PasswordExpirationEnabled'
            PasswordPolicy     = 'PasswordPolicyEnforced'
            ServerInstance     = 'SqlInstance'
        }

        $commandrenames = @{
            'Find-DbaDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-DbaDisabledIndex'             = 'Find-DbaDbDisabledIndex'
            'Add-DbaRegisteredServer'           = 'Add-DbaRegServer'
            'Add-DbaRegisteredServerGroup'      = 'Add-DbaRegServerGroup'
            'Backup-DbaDatabaseCertificate'     = 'Backup-DbaDbCertificate'
            'Backup-DbaDatabaseMasterKey'       = 'Backup-DbaDbMasterKey'
            'Clear-DbaSqlConnectionPool'        = 'Clear-DbaConnectionPool'
            'Connect-DbaServer'                 = 'Connect-DbaInstance'
            'Copy-DbaAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-DbaAgentProxyAccount'         = 'Copy-DbaAgentProxy'
            'Copy-DbaAgentSharedSchedule'       = 'Copy-DbaAgentSchedule'
            'Copy-DbaCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-DbaDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-DbaDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-DbaExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-DbaQueryStoreConfig'          = 'Copy-DbaDbQueryStoreOption'
            'Copy-DbaSqlDataCollector'          = 'Copy-DbaDataCollector'
            'Copy-DbaSqlPolicyManagement'       = 'Copy-DbaPolicyManagement'
            'Copy-DbaSqlServerAgent'            = 'Copy-DbaAgentServer'
            'Copy-DbaTableData'                 = 'Copy-DbaDbTableData'
            'Copy-SqlAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-SqlAlert'                     = 'Copy-DbaAgentAlert'
            'Copy-SqlAudit'                     = 'Copy-DbaInstanceAudit'
            'Copy-SqlAuditSpecification'        = 'Copy-DbaInstanceAuditSpecification'
            'Copy-SqlBackupDevice'              = 'Copy-DbaBackupDevice'
            'Copy-SqlCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-SqlCredential'                = 'Copy-DbaCredential'
            'Copy-SqlCustomError'               = 'Copy-DbaCustomError'
            'Copy-SqlDatabase'                  = 'Copy-DbaDatabase'
            'Copy-SqlDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-SqlDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-SqlDataCollector'             = 'Copy-DbaDataCollector'
            'Copy-SqlEndpoint'                  = 'Copy-DbaEndpoint'
            'Copy-SqlExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-SqlJob'                       = 'Copy-DbaAgentJob'
            'Copy-SqlJobServer'                 = 'Copy-SqlInstanceAgent'
            'Copy-SqlLinkedServer'              = 'Copy-DbaLinkedServer'
            'Copy-SqlLogin'                     = 'Copy-DbaLogin'
            'Copy-SqlOperator'                  = 'Copy-DbaAgentOperator'
            'Copy-SqlPolicyManagement'          = 'Copy-DbaPolicyManagement'
            'Copy-SqlProxyAccount'              = 'Copy-DbaAgentProxy'
            'Copy-SqlResourceGovernor'          = 'Copy-DbaResourceGovernor'
            'Copy-SqlInstanceAgent'             = 'Copy-DbaAgentServer'
            'Copy-SqlInstanceTrigger'           = 'Copy-DbaInstanceTrigger'
            'Copy-SqlSharedSchedule'            = 'Copy-DbaAgentSchedule'
            'Copy-SqlSpConfigure'               = 'Copy-DbaSpConfigure'
            'Copy-SqlSsisCatalog'               = 'Copy-DbaSsisCatalog'
            'Copy-SqlSysDbUserObjects'          = 'Copy-DbaSysDbUserObject'
            'Copy-SqlUserDefinedMessage'        = 'Copy-SqlCustomError'
            'Expand-DbaTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Expand-SqlTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Export-DbaDacpac'                  = 'Export-DbaDacPackage'
            'Export-DbaRegisteredServer'        = 'Export-DbaRegServer'
            'Export-SqlLogin'                   = 'Export-DbaLogin'
            'Export-SqlSpConfigure'             = 'Export-DbaSpConfigure'
            'Export-SqlUser'                    = 'Export-DbaUser'
            'Find-DbaDatabaseGrowthEvent'       = 'Find-DbaDbGrowthEvent'
            'Find-SqlDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-SqlUnusedIndex'               = 'Find-DbaDbUnusedIndex'
            'Get-DbaRegServerName'              = 'Get-DbaRegServer'
            'Get-DbaConfig'                     = 'Get-DbatoolsConfig'
            'Get-DbaConfigValue'                = 'Get-DbatoolsConfigValue'
            'Get-DbaDatabaseAssembly'           = 'Get-DbaDbAssembly'
            'Get-DbaDatabaseCertificate'        = 'Get-DbaDbCertificate'
            'Get-DbaDatabaseEncryption'         = 'Get-DbaDbEncryption'
            'Get-DbaDatabaseFile'               = 'Get-DbaDbFile'
            'Get-DbaDatabaseFreeSpace'          = 'Get-DbaDbSpace'
            'Get-DbaDatabaseMasterKey'          = 'Get-DbaDbMasterKey'
            'Get-DbaDatabasePartitionFunction'  = 'Get-DbaDbPartitionFunction'
            'Get-DbaDatabasePartitionScheme'    = 'Get-DbaDbPartitionScheme'
            'Get-DbaDatabaseSnapshot'           = 'Get-DbaDbSnapshot'
            'Get-DbaDatabaseSpace'              = 'Get-DbaDbSpace'
            'Get-DbaDatabaseState'              = 'Get-DbaDbState'
            'Get-DbaDatabaseUdf'                = 'Get-DbaDbUdf'
            'Get-DbaDatabaseUser'               = 'Get-DbaDbUser'
            'Get-DbaDatabaseView'               = 'Get-DbaDbView'
            'Get-DbaDbQueryStoreOptions'        = 'Get-DbaDbQueryStoreOption'
            'Get-DbaDistributor'                = 'Get-DbaRepDistributor'
            'Get-DbaInstance'                   = 'Connect-DbaInstance'
            'Get-DbaJobCategory'                = 'Get-DbaAgentJobCategory'
            'Get-DbaLog'                        = 'Get-DbaErrorLog'
            'Get-DbaLogShippingError'           = 'Get-DbaDbLogShipError'
            'Get-DbaOrphanUser'                 = 'Get-DbaDbOrphanUser'
            'Get-DbaPolicy'                     = 'Get-DbaPbmPolicy'
            'Get-DbaQueryStoreConfig'           = 'Get-DbaDbQueryStoreOption'
            'Get-DbaRegisteredServerGroup'      = 'Get-DbaRegServerGroup'
            'Get-DbaRegisteredServerStore'      = 'Get-DbaRegServerStore'
            'Get-DbaRestoreHistory'             = 'Get-DbaDbRestoreHistory'
            'Get-DbaRoleMember'                 = 'Get-DbaDbRoleMember'
            'Get-DbaSqlBuildReference'          = 'Get-DbaBuild'
            'Get-DbaSqlFeature'                 = 'Get-DbaFeature'
            'Get-DbaSqlInstanceProperty'        = 'Get-DbaInstanceProperty'
            'Get-DbaSqlInstanceUserOption'      = 'Get-DbaInstanceUserOption'
            'Get-DbaSqlManagementObject'        = 'Get-DbaManagementObject'
            'Get-DbaSqlModule'                  = 'Get-DbaModule'
            'Get-DbaSqlProductKey'              = 'Get-DbaProductKey'
            'Get-DbaSqlRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaSqlService'                 = 'Get-DbaService'
            'Get-DbaTable'                      = 'Get-DbaDbTable'
            'Get-DbaTraceFile'                  = 'Get-DbaTrace'
            'Get-DbaUserLevelPermission'        = 'Get-DbaUserPermission'
            'Get-DbaXEventSession'              = 'Get-DbaXESession'
            'Get-DbaXEventSessionTarget'        = 'Get-DbaXESessionTarget'
            'Get-DiskSpace'                     = 'Get-DbaDiskSpace'
            'Get-SqlMaxMemory'                  = 'Get-DbaMaxMemory'
            'Get-SqlRegisteredServerName'       = 'Get-DbaRegServer'
            'Get-SqlInstanceKey'                = 'Get-DbaProductKey'
            'Import-DbaCsvToSql'                = 'Import-DbaCsv'
            'Import-DbaRegisteredServer'        = 'Import-DbaRegServer'
            'Import-SqlSpConfigure'             = 'Import-DbaSpConfigure'
            'Install-SqlWhoIsActive'            = 'Install-DbaWhoIsActive'
            'Invoke-DbaCmd'                     = 'Invoke-DbaQuery'
            'Invoke-DbaDatabaseClone'           = 'Invoke-DbaDbClone'
            'Invoke-DbaDatabaseShrink'          = 'Invoke-DbaDbShrink'
            'Invoke-DbaDatabaseUpgrade'         = 'Invoke-DbaDbUpgrade'
            'Invoke-DbaLogShipping'             = 'Invoke-DbaDbLogShipping'
            'Invoke-DbaLogShippingRecovery'     = 'Invoke-DbaDbLogShipRecovery'
            'Invoke-DbaSqlQuery'                = 'Invoke-DbaQuery'
            'Move-DbaRegisteredServer'          = 'Move-DbaRegServer'
            'Move-DbaRegisteredServerGroup'     = 'Move-DbaRegServerGroup'
            'New-DbaDatabaseCertificate'        = 'New-DbaDbCertificate'
            'New-DbaDatabaseMasterKey'          = 'New-DbaDbMasterKey'
            'New-DbaDatabaseSnapshot'           = 'New-DbaDbSnapshot'
            'New-DbaPublishProfile'             = 'New-DbaDacProfile'
            'New-DbaSqlConnectionString'        = 'New-DbaConnectionString'
            'New-DbaSqlConnectionStringBuilder' = 'New-DbaConnectionStringBuilder'
            'New-DbaSqlDirectory'               = 'New-DbaDirectory'
            'Out-DbaDataTable'                  = 'ConvertTo-DbaDataTable'
            'Publish-DbaDacpac'                 = 'Publish-DbaDacPackage'
            'Read-DbaXEventFile'                = 'Read-DbaXEFile'
            'Register-DbaConfig'                = 'Register-DbatoolsConfig'
            'Remove-DbaDatabaseCertificate'     = 'Remove-DbaDbCertificate'
            'Remove-DbaDatabaseMasterKey'       = 'Remove-DbaDbMasterKey'
            'Remove-DbaDatabaseSnapshot'        = 'Remove-DbaDbSnapshot'
            'Remove-DbaOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Remove-DbaRegisteredServer'        = 'Remove-DbaRegServer'
            'Remove-DbaRegisteredServerGroup'   = 'Remove-DbaRegServerGroup'
            'Remove-SqlDatabaseSafely'          = 'Remove-DbaDatabaseSafely'
            'Remove-SqlOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Repair-DbaOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Repair-SqlOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Reset-SqlAdmin'                    = 'Reset-DbaAdmin'
            'Reset-SqlSaPassword'               = 'Reset-SqlAdmin'
            'Restart-DbaSqlService'             = 'Restart-DbaService'
            'Restore-DbaDatabaseCertificate'    = 'Restore-DbaDbCertificate'
            'Restore-DbaDatabaseSnapshot'       = 'Restore-DbaDbSnapshot'
            'Restore-HallengrenBackup'          = 'Restore-SqlBackupFromDirectory'
            'Set-DbaConfig'                     = 'Set-DbatoolsConfig'
            'Get-DbaBackupHistory'              = 'Get-DbaDbBackupHistory'
            'Set-DbaDatabaseOwner'              = 'Set-DbaDbOwner'
            'Set-DbaDatabaseState'              = 'Set-DbaDbState'
            'Set-DbaDbQueryStoreOptions'        = 'Set-DbaDbQueryStoreOption'
            'Set-DbaJobOwner'                   = 'Set-DbaAgentJobOwner'
            'Set-DbaQueryStoreConfig'           = 'Set-DbaDbQueryStoreOption'
            'Set-DbaTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Set-SqlMaxMemory'                  = 'Set-DbaMaxMemory'
            'Set-SqlTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Show-DbaDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlMigrationConstraint'       = 'Test-SqlMigrationConstraint'
            'Show-SqlInstanceFileSystem'        = 'Show-DbaInstanceFileSystem'
            'Show-SqlWhoIsActive'               = 'Invoke-DbaWhoIsActive'
            'Start-DbaSqlService'               = 'Start-DbaService'
            'Start-SqlMigration'                = 'Start-DbaMigration'
            'Stop-DbaSqlService'                = 'Stop-DbaService'
            'Sync-DbaSqlLoginPermission'        = 'Sync-DbaLoginPermission'
            'Sync-SqlLoginPermissions'          = 'Sync-DbaLoginPermission'
            'Test-DbaDatabaseCollation'         = 'Test-DbaDbCollation'
            'Test-DbaDatabaseCompatibility'     = 'Test-DbaDbCompatibility'
            'Test-DbaDatabaseOwner'             = 'Test-DbaDbOwner'
            'Test-DbaDbVirtualLogFile'          = 'Measure-DbaDbVirtualLogFile'
            'Test-DbaFullRecoveryModel'         = 'Test-DbaDbRecoveryModel'
            'Test-DbaJobOwner'                  = 'Test-DbaAgentJobOwner'
            'Test-DbaLogShippingStatus'         = 'Test-DbaDbLogShipStatus'
            'Test-DbaRecoveryModel'             = 'Test-DbaDbRecoveryModel'
            'Test-DbaSqlBuild'                  = 'Test-DbaBuild'
            'Test-DbaSqlManagementObject'       = 'Test-DbaManagementObject'
            'Test-DbaSqlPath'                   = 'Test-DbaPath'
            'Test-DbaTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Test-DbaValidLogin'                = 'Test-DbaWindowsLogin'
            'Test-DbaVirtualLogFile'            = 'Measure-DbaDbVirtualLogFile'
            'Test-SqlConnection'                = 'Test-DbaConnection'
            'Test-SqlDiskAllocation'            = 'Test-DbaDiskAllocation'
            'Test-SqlMigrationConstraint'       = 'Test-DbaMigrationConstraint'
            'Test-SqlNetworkLatency'            = 'Test-DbaNetworkLatency'
            'Test-SqlPath'                      = 'Test-DbaPath'
            'Test-SqlTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Update-DbaSqlServiceAccount'       = 'Update-DbaServiceAccount'
            'Watch-DbaXEventSession'            = 'Watch-DbaXESession'
            'Watch-SqlDbLogin'                  = 'Watch-DbaDbLogin'
            'Add-DbaCmsRegServer'               = 'Add-DbaRegServer'
            'Add-DbaCmsRegServerGroup'          = 'Add-DbaRegServerGroup'
            'Copy-DbaCmsRegServer'              = 'Copy-DbaRegServer'
            'Export-DbaCmsRegServer'            = 'Export-DbaRegServer'
            'Get-DbaCmsRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaCmsRegServer'               = 'Get-DbaRegServer'
            'Get-DbaCmsRegServerGroup'          = 'Get-DbaRegServerGroup'
            'Get-DbaCmsRegServerStore'          = 'Get-DbaRegServerStore'
            'Import-DbaCmsRegServer'            = 'Import-DbaRegServer'
            'Move-DbaCmsRegServer'              = 'Move-DbaRegServer'
            'Move-DbaCmsRegServerGroup'         = 'Move-DbaRegServerGroup'
            'Remove-DbaCmsRegServer'            = 'Remove-DbaRegServer'
            'Remove-DbaCmsRegServerGroup'       = 'Remove-DbaRegServerGroup'
            'Copy-DbaServerAuditSpecification'  = 'Copy-DbaInstanceAuditSpecification'
            'Copy-DbaServerAudit'               = 'Copy-DbaInstanceAudit'
            'Copy-DbaServerTrigger'             = 'Copy-DbaInstanceTrigger'
            'Test-DbaServerName'                = 'Test-DbaInstanceName'
            'Test-DbaInstanceName'              = 'Repair-DbaInstanceName'
            'Get-DbaServerTrigger'              = 'Get-DbaInstanceTrigger'
            'Get-DbaServerAudit'                = 'Get-DbaInstanceAudit'
            'Get-DbaServerAuditSpecification'   = 'Get-DbaInstanceAuditSpecification'
            'Get-DbaServerInstallDate'          = 'Get-DbaInstanceInstallDate'
            'Show-DbaServerFileSystem'          = 'Show-DbaInstanceFileSystem'
            'Install-DbaWatchUpdate'            = 'Install-DbatoolsWatchUpdate'
            'Uninstall-DbaWatchUpdate'          = 'Uninstall-DbatoolsWatchUpdate'
        }
    }
    process {
        foreach ($fileobject in $InputObject) {
            $file = $fileobject.FullName

            foreach ($name in $paramrenames.GetEnumerator()) {
                if ((Select-String -Pattern $name.Key -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = (Get-Content -Path $file -Raw).Replace($name.Key, $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }

            foreach ($name in $commandrenames.GetEnumerator()) {
                if ((Select-String -Pattern "\b$($name.Key)\b" -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = ((Get-Content -Path $file -Raw) -Replace "\b$($name.Key)\b", $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEprDiKO1uoODmlUKcsb5dsm4
# w/2gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBRowggQC
# oAMCAQICEAMFu4YhsKFjX7/erhIE520wDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA1MTIwMDAwMDBaFw0yMzA2MDgxMjAwMDBaMFcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQIEwhWaXJnaW5pYTEPMA0GA1UEBxMGVmllbm5hMREw
# DwYDVQQKEwhkYmF0b29sczERMA8GA1UEAxMIZGJhdG9vbHMwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQC8v2N7q+O/vggBtpjmteofFo140k73JXQ5sOD6
# QLzjgija+scoYPxTmFSImnqtjfZFWmucAWsDiMVVro/6yGjsXmJJUA7oD5BlMdAK
# fuiq4558YBOjjc0Bp3NbY5ZGujdCmsw9lqHRAVil6P1ZpAv3D/TyVVq6AjDsJY+x
# rRL9iMc8YpD5tiAj+SsRSuT5qwPuW83ByRHqkaJ5YDJ/R82ZKh69AFNXoJ3xCJR+
# P7+pa8tbdSgRf25w4ZfYPy9InEvsnIRVZMeDjjuGvqr0/Mar73UI79z0NYW80yN/
# 7VzlrvV8RnniHWY2ib9ehZligp5aEqdV2/XFVPV4SKaJs8R9AgMBAAGjggHFMIIB
# wTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU8MCg
# +7YDgENO+wnX3d96scvjniIwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdp
# Y2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCG
# SAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NB
# LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQCPzflwlQwf1jak
# EqymPOc0nBxiY7F4FwcmL7IrTLhub6Pjg4ZYfiC79Akz5aNlqO+TJ0kqglkfnOsc
# jfKQzzDwcZthLVZl83igzCLnWMo8Zk/D2d4ZLY9esFwqPNvuuVDrHvgh7H6DJ/zP
# Vm5EOK0sljT0UQ6HQEwtouH5S8nrqCGZ8jKM/+DeJlm+rCAGGf7TV85uqsAn5JqD
# En/bXE1AlyG1Q5YiXFGS5Sf0qS4Nisw7vRrZ6Qc4NwBty4cAYjzDPDixorWI8+FV
# OUWKMdL7tV8i393/XykwsccCstBCp7VnSZN+4vgzjEJQql5uQfysjcW9rrb/qixp
# csPTKYRHMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFMTCC
# BBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0BAQsFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvdAy7kvNj3/dqbqC
# mcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQmL8TvFfTw+F+CNZq
# FAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODeIj8O/36V+/OjuiI+
# GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt30A6XLdR4aF5FMZN
# JCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ/ZQqLKfkdT66mA+E
# f58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4UdxB08r8/arBD13ays
# 6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu0uRhpbKiJbLIFzVu
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHkGCCsG
# AQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqg
# OKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3QITvS4S/ys8DAv3F
# p8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP+LLR2HwZYuhegiUe
# xLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFNYkYkh2OMkVIsrymJ
# 5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18yAGxuSh1t5ljhSKM
# Ycp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8QlK0cCCHxJrhO24XxC
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBFwwggRYAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFK64qYvBgPXSW3QyStOTZ/aGFVVKMA0GCSqGSIb3DQEBAQUABIIBACeapAuV
# 0wAAJEMEpF2zQ5yIzSCUnCAH/GnwZLPzgrheUm0UlN1rn8Fm4OssJcVIIQgjIrS4
# B9kcNSuzwtziHFnarGbFlUbVOevPq7ouulRGkqX1ZELCm2W0bv83hK4z8IWKbmaY
# kELHwIy90VxlAObcXfPMdsG8tLzKyYJkz11gStRenR2B7JRqnvRSigSmKHTq+xgJ
# wtG9hta0PsxaEdj8brmrcNQKVASlpbqbe3fsai6OY/fdUdCTmPMEiRxJRF2AQ4Qk
# avZlLhkJ8uP4n35CR4kulEFDur42oltaGE672HrqshzGuDS4caU290Wx6izojir+
# 2dofc3BxzOPc+VWhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzN1owLwYJKoZIhvcNAQkEMSIEINv0MiWibYw/9pCZsAvAcK2ZyFNI
# awpX3A6YDol2sym7MA0GCSqGSIb3DQEBAQUABIIBAFhnedjPvlGK+egHAAmtOBFW
# Isc/23dzubNRCZNUuX9H7mZGd3NGZ/GWLH8t57/ADUaMtc9tdIZqQhxoZaIqxfxP
# Osh7gDbdL0dVE8ZFcx/OhJxQVVq4BaleRKHMNVhwIOrV5ISNNr5XIThlhFaifgni
# O4ll5MzYEAtH2ZE+6HDX2xzgBtEmdLu6K3iM3czFR0sX7KKLXp86o/+ultPxVbAm
# gxNrLqO5FJhkRnJaw5FPdaXcfW57a8x3DNDR95//pukT2labRfEqIK9FpxQ+mzQW
# RFZXrPQwGmhrez5dAUc5jRR9qSS22Q6T8QZc7pMcdGDRejDJ0try28A42ldH9Ow=
# SIG # End signature block
