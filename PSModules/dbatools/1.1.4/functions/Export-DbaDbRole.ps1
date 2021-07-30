function Export-DbaDbRole {
    <#
    .SYNOPSIS
        Exports database roles to a T-SQL file. Export includes Role creation, object permissions and Schema ownership.

    .DESCRIPTION
        Exports database roles to a T-SQL file. Export includes Role creation, object permissions and Schema ownership.

        This command is based off of John Eisbrener's post "Fully Script out a MSSQL Database Role"
        Reference:  https://dbaeyes.wordpress.com/2013/04/19/fully-script-out-a-mssql-database-role/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2005 and above supported.
        Any databases in CompatibilityLevel 80 or lower will be skipped

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase and Get-DbaLogin.

     .PARAMETER ScriptingOptionsObject
        An SMO Scripting Object that can be used to customize the output - see New-DbaScriptingOption

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Role
        The Role(s) to process. If unspecified, all Roles will be processed.

    .PARAMETER ExcludeRole
        The Role(s) to exclude.

    .PARAMETER ExcludeFixedRole
        Excludes all members of fixed roles.

    .PARAMETER IncludeRoleMember
        Include scripting of role members in script

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER FilePath
        Specifies the full file path of the output file. If left blank then filename based on Instance name, Database name and date is created.
        If more than one database or instance is input then this parameter should normally be blank.

    .PARAMETER Passthru
        Output script to console only

    .PARAMETER BatchSeparator
        Batch separator for scripting output. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoClobber
        If this switch is enabled, a file already existing at the path specified by Path will not be overwritten. This takes precedence over Append switch

    .PARAMETER Append
        If this switch is enabled, content will be appended to a file already existing at the path specified by FilePath. If the file does not exist, it will be created.

    .PARAMETER NoPrefix
        Do not include a Prefix

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

    .NOTES
        Tags: Export, Role
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDbRole

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sql2005 -Path C:\temp

        Exports all the Database Roles for SQL Server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -ExcludeRole realcajun -SqlCredential $scred -Path C:\temp\roles.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all roles except for realcajun to C:\temp\roles.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -Role realcajun,netnerds -Path C:\temp\roles.sql

        Exports ONLY roles netnerds and realcajun FROM sqlserver2014a to the file C:\temp\roles.sql

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -Role realcajun,netnerds -Database HR, Accounting

        Exports ONLY roles netnerds and realcajun FROM sqlserver2014a with the permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR, Accounting | Export-DbaDbRole

        Exports ONLY roles FROM sqlserver2014a with permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Set-DbatoolsConfig -FullName formatting.batchseparator -Value $null
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2008 -Role realcajun,netnerds -Path C:\temp\roles.sql

        Sets the BatchSeparator configuration to null, removing the default "GO" value.
        Exports ONLY roles netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\roles.sql file, without the "GO" batch separator.

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2008 -Role realcajun,netnerds -Path C:\temp\roles.sql -BatchSeparator $null

        Exports ONLY roles netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\roles.sql file, without the "GO" batch separator.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2008 | Export-DbaDbRole -Role realcajun

        Exports role realcajun for all databases on sqlserver2008

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance sqlserver2008 -ExcludeFixedRole | Export-DbaDbRole

        Exports all roles from all databases on sqlserver2008, excludes all roles marked as as FixedRole

    #>
    [CmdletBinding()]
    param (
        [parameter()]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [object[]]$Database,
        [object[]]$Role,
        [object[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [switch]$IncludeRoleMember,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$Passthru,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$NoPrefix,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $outputFileArray = @()
        $roleCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name

        $roleSQL = "SELECT
                        N'/*RoleName*/' as RoleName,
                        CASE dp.state
                            WHEN 'D' THEN 'DENY'
                            WHEN 'G' THEN 'GRANT'
                            WHEN 'R' THEN 'REVOKE'
                            WHEN 'W' THEN 'GRANT'
                        END as GrantState,
                        dp.permission_name as Permission,
                        CASE dp.class
                            WHEN 0 THEN ''
                            WHEN 1 THEN --table or column subset on the table
                                CASE WHEN dp.major_id < 0 THEN COALESCE('[sys].[' + OBJECT_NAME(dp.major_id) + ']', '')
                                    ELSE '[' + (SELECT SCHEMA_NAME(schema_id) + '].[' + name FROM sys.objects WHERE object_id = dp.major_id) + ']'
                                END + -- optionally concatenate column names
                                    CASE WHEN MAX(dp.minor_id) > 0 THEN ' (['
                                        + REPLACE((SELECT name + '], [' FROM sys.columns
                                                WHERE object_id = dp.major_id
                                                AND column_id IN (SELECT minor_id FROM sys.database_permissions WHERE major_id = dp.major_id AND USER_NAME(grantee_principal_id) = N'/*RoleName*/')
                                        FOR XML PATH('')) + '])', ', []', '')
                                        ELSE ''
                                    END
                            WHEN 3 THEN 'SCHEMA::[' + SCHEMA_NAME(dp.major_id) + ']'
                            WHEN 4 THEN '' + (SELECT RIGHT(type_desc, 4) + '::[' + name FROM sys.database_principals WHERE principal_id = dp.major_id) + ']'
                            WHEN 5 THEN 'ASSEMBLY::[' + (SELECT name FROM sys.assemblies WHERE assembly_id = dp.major_id) + ']'
                            WHEN 6 THEN 'TYPE::[' + (SELECT name FROM sys.types WHERE user_type_id = dp.major_id) + ']'
                            WHEN 10 THEN 'XML SCHEMA COLLECTION::[' + (SELECT SCHEMA_NAME(schema_id) + '.' + name FROM sys.xml_schema_collections WHERE xml_collection_id = dp.major_id) + ']'
                            WHEN 15 THEN 'MESSAGE TYPE::[' + (SELECT name FROM sys.service_message_types WHERE message_type_id = dp.major_id) + ']'
                            WHEN 16 THEN 'CONTRACT::[' + (SELECT name FROM sys.service_contracts WHERE service_contract_id = dp.major_id) + ']'
                            WHEN 17 THEN 'SERVICE::[' + (SELECT name FROM sys.services WHERE service_id = dp.major_id) + ']'
                            WHEN 18 THEN 'REMOTE SERVICE BINDING::[' + (SELECT name FROM sys.remote_service_bindings WHERE remote_service_binding_id = dp.major_id) + ']'
                            WHEN 19 THEN 'ROUTE::[' + (SELECT name FROM sys.routes WHERE route_id = dp.major_id) + ']'
                            WHEN 23 THEN 'FULLTEXT CATALOG::[' + (SELECT name FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id) + ']'
                            WHEN 24 THEN 'SYMMETRIC KEY::[' + (SELECT name FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id) + ']'
                            WHEN 25 THEN 'CERTIFICATE::[' + (SELECT name FROM sys.certificates WHERE certificate_id = dp.major_id) + ']'
                            WHEN 26 THEN 'ASYMMETRIC KEY::[' + (SELECT name FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id) + ']'
                        END COLLATE DATABASE_DEFAULT  as Type,
                        CASE dp.state WHEN 'W' THEN ' WITH GRANT OPTION' ELSE '' END as GrantType
                    FROM sys.database_permissions dp
                    WHERE USER_NAME(dp.grantee_principal_id) = N'/*RoleName*/'
                    GROUP BY dp.state, dp.major_id, dp.permission_name, dp.class
                    UNION ALL
                    SELECT
                        N'/*RoleName*/' as RoleName,
                        'ALTER' as GrantState,
                        'AUTHORIZATION' as permission_name,
                        'SCHEMA::['+s.[name]+']' as Type,
                        '' as GrantType
                    from sys.schemas s
                    join sys.sysusers u on s.principal_id = u.[uid]
                    where u.[name] = N'/*RoleName*/'"

        $userSQL = "SELECT roles.name as RoleName, users.name as Member
                    FROM sys.database_principals users
                    INNER JOIN sys.database_role_members link
                        ON link.member_principal_id = users.principal_id
                    INNER JOIN sys.database_principals roles
                        ON roles.principal_id = link.role_principal_id
                    WHERE roles.name = N'/*RoleName*/'"

        if (Test-Bound -Not -ParameterName ScriptingOptionsObject) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.AllowSystemObjects = $false
            $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
            $ScriptingOptionsObject.ContinueScriptingOnError = $false
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
            $ScriptingOptionsObject.IncludeIfNotExists = $false
        }

        if ($ScriptingOptionsObject.NoCommandTerminator) {
            $commandTerminator = ''
        } else {
            $commandTerminator = ';'
        }
        $outsql = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $databaseRoles = $input | Get-DbaDbRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject"
                    $databaseRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or login."
                    return
                }
            }
            foreach ($dbRole in $databaseRoles) {
                try {
                    $server = $dbRole.Parent.Parent
                    $db = $dbRole.Parent
                    if ($server.VersionMajor -lt 9) {
                        Stop-Function -Message "SQL Server version 9 or higher required - $server not supported." -Continue
                    }
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))
                    if ($dbCompatibilityLevel -lt 90) {
                        Stop-Function -Message "$db has a compatibility level lower than Version90 and will be skipped." -Target $db -Continue
                    }

                    $outsql += $dbRole.Script($ScriptingOptionsObject)

                    $query = $roleSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                    $rolePermissions = $($dbRole.Parent).Query($query)

                    foreach ($rolePermission in $rolePermissions) {
                        $script = $rolePermission.GrantState + " " + $rolePermission.Permission
                        if ($rolePermission.Type) {
                            $script += " ON " + $rolePermission.Type
                        }
                        if ($rolePermission.RoleName) {
                            $script += " TO [" + $rolePermission.RoleName + "]"
                        }
                        if ($rolePermission.GrantType) {
                            $script += " WITH GRANT OPTION" + $commandTerminator
                        } else {
                            $script += $commandTerminator
                        }
                        $outsql += "$script"
                    }

                    if ($IncludeRoleMember) {
                        $query = $userSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                        $roleUsers = $($dbRole.Parent).Query($query)

                        foreach ($roleUser in $roleUsers) {
                            if ($server.VersionMajor -lt 11) {
                                $script = "EXEC sys.sp_addrolemember @rolename=N'$($roleUser.RoleName)', @membername=N'$($roleUser.Member)'"
                            } else {
                                $script = 'ALTER ROLE [' + $roleUser.RoleName + "] ADD MEMBER [" + $roleUser.Member + "]" + $commandTerminator
                            }
                            $outsql += "$script"
                        }
                    }
                    $roleObject = [PSCustomObject]@{
                        Name     = $dbRole.Name
                        Instance = $dbRole.SqlInstance
                        Database = $dbRole.Database
                        Sql      = $outsql
                    }
                    $roleCollection.Add($roleObject) | Out-Null
                    $outsql = @()
                } catch {
                    $outsql = @()
                    Stop-Function -Message "Error occurred processing role $dbRole" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        $timeNow = $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))
        foreach ($dbRole in $roleCollection) {
            $instanceName = $dbRole.Instance
            $databaseName = $dbRole.Database

            $outputFileName = $instanceName.Replace('\', '$') + '-' + $databaseName.Replace('\', '$')

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*`n`tCreated by $executingUser using dbatools $commandName for objects on $instanceName.$databaseName at $timeNow`n`tSee https://dbatools.io/$commandName for more information`n*/"
            }

            if ($BatchSeparator) {
                $sql = $dbRole.SQL -join "`r`n$BatchSeparator`r`n"
                #add the final GO
                $sql += "`r`n$BatchSeparator"
            } else {
                $sql = $dbRole.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix`r`n$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($outputFileArray -notcontains $outputFileName) {
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $outputFileName
                    Write-Message -Level Verbose -Message "New File $scriptPath"
                    if ($null -ne $prefix) {
                        $sql = "$prefix`r`n$sql"
                    }
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $outputFileArray += $outputFileName
                    Get-ChildItem $scriptPath
                } else {
                    Write-Message -Level Verbose -Message "Adding to $scriptPath"
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUesXs6oKe6ZaiDm86LOVTsOsv
# iPSgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFOs4buPM2t/SOArLGz0VA2IrvfHqMA0GCSqGSIb3DQEBAQUABIIBAKjl/z8A
# XmNIbSWXOQxfWne0M5/1gH1UcIiAvfZOYszhVwHUVlX9NXXRnKp8NEiMaXFbf/ys
# WRJtz9I1sKdTbTZ6fFUPbGw2ape/HxsjoQwuWw3L3psnA56IXqBSLIFnamDUHwcl
# pLaw8gpWgqOq67xiS1dce4abGWI592IXpU0qeg1rNHXTn02ZUXGlS/Mqgtoo3LK4
# tS3lWqzTWqMh8h6d1u/cFxLC0WPGwqZ/qPxhMU+Gcb/DWctundO8X3zMNXBRGXRV
# mH2TsrbM8RbzXIGze4jih4Sk4MOhQ6wWb7RvQIy0eyOpdsJ0L/8f5SPDUn0iEbX2
# SliQOCZg/8vGphuhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyMFowLwYJKoZIhvcNAQkEMSIEIHRoIiyQ/qchuL6bRICFglXoTkI1
# dtkGEgS90yaWa/RHMA0GCSqGSIb3DQEBAQUABIIBALox4riW+rs1Cm9HubI+50ce
# lBm+JddzEdebCyE3AIiUNFnWuZV15Qz+yv3gYwYIMVb5kU8U18tI7GNStuePyOGQ
# HmgLAuDLBonTCyJk/CB5o6jWlBDDvHrssmjm6iQNElWR7HYn6vYlrris9jEnhUPs
# JxD7YH6bhVdE9Vz/1DVUseEhKDEKdMUVg0TMFFkr3xp1VbY8lJi7uoRi8ZII5841
# H0SXy5YLaiyYrTGUV/c0XaulVMuZQGirPpqVBKUgRK0vDq/HlEkmv4lVDGyg16rj
# uG04XTiT4Rs48uhPT4nYr8C2cBKl+6thO1BTUmYBIM2NwmiBWjzt6AjIwLt5AKQ=
# SIG # End signature block
