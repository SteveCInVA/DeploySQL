function Get-DbaPermission {
    <#
    .SYNOPSIS
        Get a list of Server and Database level permissions

    .DESCRIPTION
        Retrieves a list of permissions

        Permissions link principals to securables.
        Principals exist on Windows, Instance and Database level.
        Securables exist on Instance and Database level.
        A permission state can be GRANT, DENY or REVOKE.
        The permission type can be SELECT, CONNECT, EXECUTE and more.
        The CONTROL permission is also returned for dbo users, db_owners, and schema owners.
        To see server-level implicit permissions via fixed roles run the following command: Get-DbaServerRole -SqlInstance serverName | Select-Object *

        See https://msdn.microsoft.com/en-us/library/ms191291.aspx for more information

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER IncludeServerLevel
        If this switch is enabled, information about Server Level Permissions will be output.

    .PARAMETER ExcludeSystemObjects
        If this switch is enabled, permissions on system securables will be excluded.

    .PARAMETER EnableException
        If this switch is enabled exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

    .NOTES
        Tags: Permissions, Databases
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPermission

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, permission state, permission type, grantee, granteetype, securable and securabletype.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 -ExcludeSystemObjects -IncludeServerLevel

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable
        in all databases and on the server level, but not on system securables.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance sql2016 -Database master

        Returns a custom object with permissions for the master database.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeServerLevel,
        [switch]$ExcludeSystemObjects,
        [switch]$EnableException
    )
    begin {
        if ($ExcludeSystemObjects) {
            $ExcludeSystemObjectssql = "WHERE major_id > 0 "
        }

        $ServPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                       SERVERPROPERTY('ServerName') AS SqlInstance
                        , [Database] = ''
                        , [PermState] = state_desc
                        , [PermissionName] = permission_name
                        , [SecurableType] = COALESCE(o.type_desc,sp.class_desc)
                        , [Securable] = CASE    WHEN class = 100 THEN @@SERVERNAME
                                                WHEN class = 105 THEN OBJECT_NAME(major_id)
                                                ELSE OBJECT_NAME(major_id)
                                                END
                        , [Grantee] = SUSER_NAME(grantee_principal_id)
                        , [GranteeType] = pr.type_desc
                        , [revokeStatement] = 'REVOKE ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' FROM [' + SUSER_NAME(grantee_principal_id) + ']'
                        , [grantStatement] = 'GRANT ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' TO [' + SUSER_NAME(grantee_principal_id) + ']'
                            + CASE WHEN sp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.server_permissions sp
                        JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
                        LEFT OUTER JOIN sys.all_objects o ON o.object_id = sp.major_id

                    $ExcludeSystemObjectssql

                    UNION ALL
                    SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                            , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                            , SERVERPROPERTY('ServerName') AS SqlInstance
                            , [database] = ''
                            , [PermState] = 'GRANT'
                            , [PermissionName] = pb.[permission_name]
                            , [SecurableType] = pb.class_desc
                            , [Securable] = @@SERVERNAME
                            , [Grantee] = spr.name
                            , [GranteeType] = spr.type_desc
                            , [revokestatement] = ''
                            , [grantstatement] = ''
                    FROM sys.server_principals AS spr
                    INNER JOIN sys.fn_builtin_permissions('SERVER') AS pb ON
                        spr.[name]='bulkadmin' AND pb.[permission_name]='ADMINISTER BULK OPERATIONS'
                        OR
                        spr.[name]='dbcreator' AND pb.[permission_name]='CREATE ANY DATABASE'
                        OR
                        spr.[name]='diskadmin' AND pb.[permission_name]='ALTER RESOURCES'
                        OR
                        spr.[name]='processadmin' AND pb.[permission_name] IN ('ALTER ANY CONNECTION', 'ALTER SERVER STATE')
                        OR
                        spr.[name]='sysadmin' AND pb.[permission_name]='CONTROL SERVER'
                        OR
                        spr.[name]='securityadmin' AND pb.[permission_name]='ALTER ANY LOGIN'
                        OR
                        spr.[name]='serveradmin'  AND pb.[permission_name] IN ('ALTER ANY ENDPOINT', 'ALTER RESOURCES','ALTER SERVER STATE', 'ALTER SETTINGS','SHUTDOWN', 'VIEW SERVER STATE')
                        OR
                        spr.[name]='setupadmin' AND pb.[permission_name]='ALTER ANY LINKED SERVER'
                    WHERE spr.[type]='R'
                    ;"

        $DBPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance
                    , [Database] = DB_NAME()
                    , [PermState] = state_desc
                    , [PermissionName] = permission_name
                    , [SecurableType] = COALESCE(o.type_desc,dp.class_desc)
                    , [Securable] = CASE    WHEN class = 0 THEN DB_NAME()
                                            WHEN class = 1 THEN ISNULL(s.name + '.','')+OBJECT_NAME(major_id)
                                            WHEN class = 3 THEN SCHEMA_NAME(major_id)
                                            WHEN class = 6 THEN SCHEMA_NAME(t.schema_id)+'.' + t.name
                                            END
                    , [Grantee] = USER_NAME(grantee_principal_id)
                    , [GranteeType] = pr.type_desc
                    , [RevokeStatement] = CASE WHEN class = 3 THEN 'REVOKE ' + permission_name + ' ON Schema::' + isnull(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + ' FROM [' + USER_NAME(grantee_principal_id) +']'
                                            ELSE 'REVOKE ' + permission_name + ' ON ' + isnull(schema_name(o.schema_id) COLLATE DATABASE_DEFAULT+'.','')+OBJECT_NAME(major_id)+ ' FROM [' + USER_NAME(grantee_principal_id) +']'
                                            END
                    , [GrantStatement] = CASE WHEN class = 3 THEN 'GRANT ' + permission_name + ' ON Schema::' + isnull(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + ' TO [' + USER_NAME(grantee_principal_id) + ']'
                                            ELSE 'GRANT ' + permission_name + ' ON ' + isnull(schema_name(o.schema_id) COLLATE DATABASE_DEFAULT+'.','')+OBJECT_NAME(major_id)+ ' TO [' + USER_NAME(grantee_principal_id) + ']'
                                            END
                        + CASE WHEN dp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.database_permissions dp
                    JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                    LEFT OUTER JOIN sys.all_objects o ON (o.object_id = dp.major_id AND dp.class NOT IN (0, 3))
                    LEFT OUTER JOIN sys.schemas s ON s.schema_id = o.schema_id
                    LEFT OUTER JOIN sys.types t on t.user_type_id = dp.major_id

                $ExcludeSystemObjectssql

                UNION ALL
                SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                        , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                        , SERVERPROPERTY('ServerName') AS SqlInstance
                        , [database] = DB_NAME()
                        , [PermState] = ''
                        , [PermissionName] = p.[permission_name]
                        , [SecurableType] = p.class_desc
                        , [Securable] = DB_NAME()
                        , [Grantee] = dp.name
                        , [GranteeType] = dp.type_desc
                        , [revokestatement] = ''
                        , [grantstatement] = ''
                FROM sys.database_principals AS dp
                INNER JOIN sys.fn_builtin_permissions('DATABASE') AS p ON
                    dp.[name]='db_accessadmin' AND p.[permission_name] IN ('ALTER ANY USER', 'CREATE SCHEMA')
                    OR
                    dp.[name]='db_backupoperator' AND p.[permission_name] IN ('BACKUP DATABASE', 'BACKUP LOG', 'CHECKPOINT')
                    OR
                    dp.[name] IN ('db_datareader', 'db_denydatareader') AND p.[permission_name]='SELECT'
                    OR
                    dp.[name] IN ('db_datawriter', 'db_denydatawriter') AND p.[permission_name] IN ('INSERT', 'DELETE', 'UPDATE')
                    OR
                    dp.[name]='db_ddladmin' AND
                    p.[permission_name] IN ('ALTER ANY ASSEMBLY', 'ALTER ANY ASYMMETRIC KEY',
                                            'ALTER ANY CERTIFICATE', 'ALTER ANY CONTRACT',
                                            'ALTER ANY DATABASE DDL TRIGGER', 'ALTER ANY DATABASE EVENT',
                                            'NOTIFICATION', 'ALTER ANY DATASPACE', 'ALTER ANY FULLTEXT CATALOG',
                                            'ALTER ANY MESSAGE TYPE', 'ALTER ANY REMOTE SERVICE BINDING',
                                            'ALTER ANY ROUTE', 'ALTER ANY SCHEMA', 'ALTER ANY SERVICE',
                                            'ALTER ANY SYMMETRIC KEY', 'CHECKPOINT', 'CREATE AGGREGATE',
                                            'CREATE DEFAULT', 'CREATE FUNCTION', 'CREATE PROCEDURE',
                                            'CREATE QUEUE', 'CREATE RULE', 'CREATE SYNONYM', 'CREATE TABLE',
                                            'CREATE TYPE', 'CREATE VIEW', 'CREATE XML SCHEMA COLLECTION',
                                            'REFERENCES')
                    OR
                    dp.[name]='db_owner' AND p.[permission_name]='CONTROL'
                    OR
                    dp.[name]='db_securityadmin' AND p.[permission_name] IN ('ALTER ANY APPLICATION ROLE', 'ALTER ANY ROLE', 'CREATE SCHEMA', 'VIEW DEFINITION')

                WHERE dp.[type]='R'
                    AND dp.is_fixed_role=1
                UNION ALL -- include the dbo user
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'DATABASE'
                ,	[Securable]			= DB_NAME()
                ,	[Grantee]			= SUSER_SNAME(owner_sid)
                ,	[GranteeType]		= 'DATABASE OWNER (dbo user)'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                    sys.databases
                WHERE
                    name = DB_NAME()
                UNION ALL -- include the users with the db_owner role
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'DATABASE'
                ,	[Securable]			= DB_NAME()
                ,	[Grantee]			= databaseUser.name
                ,	[GranteeType]		= 'DATABASE OWNER (db_owner role)'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                (
                    SELECT
                        member_principal_id
                    FROM
                        sys.database_role_members AS roleMembers
                    INNER JOIN
                        sys.database_principals AS roleFilter
                            ON roleMembers.role_principal_id = roleFilter.principal_id
                            AND roleFilter.name = 'db_owner'
                ) dbOwner
                INNER JOIN
                    sys.database_principals AS databaseUser
                        ON dbOwner.member_principal_id = databaseUser.principal_id
                WHERE
                    databaseUser.name <> 'dbo'
                UNION ALL -- include the schema owners
                SELECT
                    [ComputerName]		= SERVERPROPERTY('MachineName')
                ,	[InstanceName]		= ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,	[SqlInstance]		= SERVERPROPERTY('ServerName')
                ,	[database]			= DB_NAME()
                ,	[PermState]			= ''
                ,	[PermissionName]	= 'CONTROL'
                ,	[SecurableType]		= 'SCHEMA'
                ,	[Securable]			= name
                ,	[Grantee]			= USER_NAME(principal_id)
                ,	[GranteeType]		= 'SCHEMA OWNER'
                ,	[revokestatement]	= ''
                ,	[grantstatement]	= ''
                FROM
                    sys.schemas
                WHERE
                    name NOT IN (SELECT name FROM sys.database_principals WHERE type = 'R')
                AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
                ;"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($IncludeServerLevel) {
                Write-Message -Level Debug -Message "T-SQL: $ServPermsql"
                $server.Query($ServPermsql)
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance."

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db is not accessible. Skipping database."
                    Continue
                }

                Write-Message -Level Debug -Message "T-SQL: $DBPermsql"
                try {
                    $db.ExecuteWithResults($DBPermsql).Tables.Rows
                } catch {
                    Stop-Function -Message "Failure executing against $($db.Name) on $instance" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUhzTje+FMdo1htBzGXUkTK1T+
# BFGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFBHkYdmySVBFS2gO9i37z+1czqelMA0GCSqGSIb3DQEBAQUABIIBAB4mH7YQ
# MkBZfKQBycPF5bI6QqlhmX+NzY0uSOPWQXbsgCcv34+NHsKzh7thDxsMKWdFiLcm
# oLXc72mgSUokROydf8mS8FXHirbR7Je3QbUJCEUJK8cNfYEnuyAQK4wj08HRzY8d
# /bu4xa3DzpC/UZDiTZQ4213huo2mk49HHXTDes9EHkr6CNDpaxB3Jq7kQevgxnwv
# gmXtS6WeVIFhE56LlTmWcjuoPl7PY7UbOTjc7Jny5wMti/6yYLfd3nd0ImCpUNG5
# jNVClciMVf03Pcm0ZjOdUYxSl8htVywWFV/F/xIKNqSTPDY5MmF7wJJPnLjWtZaH
# /tWJ3SXafdcq/z6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUyNFowLwYJKoZIhvcNAQkEMSIEIDIJix48QQHRKM2Ctvi4aYOTTEQa
# IttEEorCKVDAeUBfMA0GCSqGSIb3DQEBAQUABIIBAEDCCtBxcDXcb6H2fVUssPp5
# Q2Emc5kJ1DArpNe86QgH07WjjkxPymJvPXKN2FYHlZK7prAkVHTl9BOeWOdpKyLv
# GlRqd9SmT+LqFESXL4Y+XhjY8TNg8GRYWtUimg/gdgJAFsdFFGWwi+4yh/L3agBQ
# VnYYp7hlBNj0W51o42Zq6wkpxxN61jT0T35FinTgDUqE+mGWhw4IFyvGPyrn60BH
# 0ZPGibq7uPVwK2fm8l4hMguTclNPXEwOUg7KEFa8mZuYbFGiATOqxPe0HNiWlvET
# GxoYLFIHKCrzz3XQ1pqCDxlaip87FqghOnpe7woc0O5v+QQAXKr1owulcsXa6mQ=
# SIG # End signature block
