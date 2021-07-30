function Remove-DbaDbOrphanUser {
    <#
    .SYNOPSIS
        Drop orphan users with no existing login to map

    .DESCRIPTION
        Allows the removal of orphan users from one or more databases

        Orphaned users in SQL Server occur when a database user is based on a login in the master database, but the login no longer exists in master.
        This can occur when the login is deleted, or when the database is moved to another server where the login does not exist.

        If user is the owner of the schema with the same name and if if the schema does not have any underlying objects the schema will be dropped.

        If user owns more than one schema, the owner of the schemas that does not have the same name as the user, will be changed to 'dbo'. If schemas have underlying objects, you must specify the -Force parameter so the user can be dropped.

        If a login of the same name exists (which could be re-mapped with Repair-DbaDbOrphanUser)  the drop will not be performed unless you specify the -Force parameter (only when calling from Repair-DbaDbOrphanUser.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server

    .PARAMETER User
        Specifies the list of users to remove.

    .PARAMETER Force
        If this switch is enabled:
        If exists any schema which owner is the User, this will force the change of the owner to 'dbo'.
        If a login of the same name exists the drop will not be performed unless you specify this parameter.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Orphan, Database, Security, Login
        Author: Claudio Silva (@ClaudioESSilva) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbOrphanUser

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sql2005

        Finds and drops all orphan users without matching Logins in all databases present on server 'sql2005'.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -SqlCredential $cred

        Finds and drops all orphan users without matching Logins in all databases present on server 'sqlserver2014a'. SQL Server authentication will be used in connecting to the server.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -Database db1, db2 -Force

        Finds and drops orphan users even if they have a matching Login on both db1 and db2 databases.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -ExcludeDatabase db1, db2 -Force

        Finds and drops orphan users even if they have a matching Login from all databases except db1 and db2.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -User OrphanUser

        Removes user OrphanUser from all databases only if there is no matching login.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -User OrphanUser -Force

        Removes user OrphanUser from all databases even if they have a matching Login. Any schema that the user owns will change ownership to dbo.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$User,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            } catch {
                Write-Message -Level Warning -Message "Can't connect to $Instance or access denied. Skipping."
                continue
            }

            $DatabaseCollection = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            $CallStack = Get-PSCallStack | Select-Object -Property *
            if ($CallStack.Count -eq 1) {
                $StackSource = $CallStack[0].Command
            } else {
                #-2 because index base is 0 and we want the one before the last (the last is the actual command)
                $StackSource = $CallStack[($CallStack.Count - 2)].Command
            }

            if ($DatabaseCollection) {
                foreach ($db in $DatabaseCollection) {
                    try {
                        #if SQL 2012 or higher only validate databases with ContainmentType = NONE
                        if ($server.versionMajor -gt 10) {
                            if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None) {
                                Write-Message -Level Warning -Message "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation."
                                Continue
                            }
                        }

                        if ($StackSource -eq "Repair-DbaDbOrphanUser") {
                            Write-Message -Level Verbose -Message "Call origin: Repair-DbaDbOrphanUser."
                            #Will use collection from parameter ($User)
                            $users = $User
                        } else {
                            Write-Message -Level Verbose -Message "Validating users on database $db."

                            $users = (Get-DbaDbOrphanUser -SqlInstance $server -Database $db.Name).SmoUser
                            if ($User.Count -gt 0) {
                                $users = $users | Where-Object { $User -contains $_.Name }
                            }
                        }

                        if ($users.Count -gt 0) {
                            Write-Message -Level Verbose -Message "Orphan users found."
                            foreach ($dbuser in $users) {
                                $SkipUser = $false

                                $ExistLogin = $null

                                if ($StackSource -ne "Repair-DbaDbOrphanUser") {
                                    #Need to validate Existing Login because the call does not came from Repair-DbaDbOrphanUser
                                    $ExistLogin = $server.logins | Where-Object {
                                        $_.Isdisabled -eq $False -and
                                        $_.IsSystemObject -eq $False -and
                                        $_.IsLocked -eq $False -and
                                        $_.Name -eq $dbuser.Name
                                    }
                                }

                                #Schemas only appears on SQL Server 2005 (v9.0)
                                if ($server.versionMajor -gt 8) {

                                    #reset variables
                                    $AlterSchemaOwner = ""
                                    $DropSchema = ""

                                    #Validate if user owns any schema
                                    $Schemas = @()
                                    $Schemas = $db.Schemas | Where-Object Owner -eq $dbuser.Name

                                    if (@($Schemas).Count -gt 0) {
                                        Write-Message -Level Verbose -Message "User $dbuser owns one or more schemas."

                                        foreach ($sch in $Schemas) {
                                            <#
                                                On sql server 2008 or lower the EnumObjects method does not accept empty parameter.
                                                0x1FFFFFFF is the way we can say we want everything known by those versions

                                                When it is a higher version we can use empty to get all
                                            #>
                                            if ($server.versionMajor -lt 11) {
                                                $NumberObjects = ($db.EnumObjects(0x1FFFFFFF) | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                            } else {
                                                $NumberObjects = ($db.EnumObjects() | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                            }

                                            if ($NumberObjects -gt 0) {
                                                if ($Force) {
                                                    Write-Message -Level Verbose -Message "Parameter -Force was used! The schema '$($sch.Name)' have $NumberObjects underlying objects. We will change schema owner to 'dbo' and drop the user."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'. -Force used.")) {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "ALTER OWNER"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "dbo"
                                                        }
                                                    }
                                                } else {
                                                    Write-Message -Level Warning -Message "Schema '$($sch.Name)' owned by user $($dbuser.Name) have $NumberObjects underlying objects. If you want to change the schemas' owner to 'dbo' and drop the user anyway, use -Force parameter. Skipping user '$dbuser'."
                                                    $SkipUser = $true
                                                    break
                                                }
                                            } else {
                                                if ($sch.Name -eq $dbuser.Name) {
                                                    Write-Message -Level Verbose -Message "The schema '$($sch.Name)' have the same name as user $dbuser. Schema will be dropped."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Dropping schema '$($sch.Name)'.")) {
                                                        $DropSchema += "DROP SCHEMA [$($sch.Name)]"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "DROP"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "N/A"
                                                        }
                                                    }
                                                } else {
                                                    Write-Message -Level Warning -Message "Schema '$($sch.Name)' does not have any underlying object. Ownership will be changed to 'dbo' so the user can be dropped. Remember to re-check permissions on this schema."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'.")) {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "ALTER OWNER"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "dbo"
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    } else {
                                        Write-Message -Level Verbose -Message "User $dbuser does not own any schema. Will be dropped."
                                    }

                                    # https://github.com/sqlcollaborative/dbatools/issues/7130
                                    $dbUserName = $dbuser.ToString()
                                    if (-not ($dbUserName.StartsWith("[") -and $dbUserName.EndsWith("]"))) {
                                        $dbUserName = "[" + $dbUserName + "]"
                                    }

                                    $query = "$AlterSchemaOwner `r`n$DropSchema `r`nDROP USER " + $dbUserName

                                    Write-Message -Level Debug -Message $query
                                } else {
                                    $query = "EXEC master.dbo.sp_droplogin @loginame = N'$($dbuser.name)'"
                                }

                                if ($ExistLogin) {
                                    if (-not $SkipUser) {
                                        if ($Force) {
                                            if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user $dbuser using -Force")) {
                                                $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                                Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name). -Force parameter was used."
                                            }
                                        } else {
                                            Write-Message -Level Warning -Message "Orphan user $($dbuser.Name) has a matching login. The user will not be dropped. If you want to drop anyway, use -Force parameter."
                                            Continue
                                        }
                                    }
                                } else {
                                    if (-not $SkipUser) {
                                        if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user $dbuser")) {
                                            $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                            Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name)."
                                        }
                                    }
                                }
                            }
                        } else {
                            Write-Message -Level Verbose -Message "No orphan users found on database $db."
                        }
                        #reset collection
                        $users = $null
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUyudNaOPE2EaFbjAPW9lHsgS
# XoSgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFObT0fe3CB5wIYrWFRyFv4uAJXIlMA0GCSqGSIb3DQEBAQUABIIBAEhKVCJo
# 4VLWzTnb/BqAcw3dYBnoxLfvzKjKq0F1lnq8WaFHUgAjxLkwftf9vCVQKlTiePNf
# dHgmtnoZwLjl1sEp+IEItjilCZVPaEKCQzX3orEyIQlIAvXsp+j+oLgNH+EdQjJk
# f2OTPgIi/p65koy5zCMJAYoXa+fu/+7cJ95nUF6513WrwKqk/fs99cr++DSe4DSG
# RzTGJ6FCHL28je4Lgr/hd1OJKN8sq8NjivId2xq0585i3mVsw+wgHSlpREW9cXwl
# udhOwBAIaiVC/P/Ml4ojfD+Zon6O6g3oAWs2VzGYQW9utSmPSdRAWYUN/OFUm1sB
# y4/UzeV6ysvJSM2hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwMlowLwYJKoZIhvcNAQkEMSIEIOiz7MMl4uu4+dY1NisRW0S5y7BN
# lo4mDVQVjwHIB2YdMA0GCSqGSIb3DQEBAQUABIIBAGUgGlHG87byW8Ps6c20cu+a
# 167zQ2c0Y5by6uw9LHP1w3+LJnZAZMdZR5Nfw3DhzIZbfQZ9PU1fc9pSpgOot9Ff
# FPc1JW5XDt+Wunn4JAUy6IHXaY8Cnd5I2UdCyRemQ3enUsTFjyov9xGcG7OshEk0
# qyAtf/cnTe77LMEDmjoLp7YFpwtX41wn+PjPLOaxxjiT2pIJNVbLf6cuLBOUcAKU
# WzWbr0M7RfyCWULWnj+NC2LKKIMNhO9eQCXQR735Ag98IaiGZV3H4ER6f2FyYkI+
# tiwKXlJBWnJ9DQNzcMl4QhvC4WOJ+Xps1DYO+pbXP6Hf2jZfBviOs5kw+M/H91Q=
# SIG # End signature block
