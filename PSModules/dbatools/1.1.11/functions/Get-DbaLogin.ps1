function Get-DbaLogin {
    <#
    .SYNOPSIS
        Function to get an SMO login object of the logins for a given SQL Server instance. Takes a server object from the pipeline.
        SQL Azure DB is not supported.

    .DESCRIPTION
        The Get-DbaLogin function returns an SMO Login object for the logins passed, if there are no users passed it will return all logins.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The login(s) to process - this list is auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER IncludeFilter
        A list of logins to include - accepts wildcard patterns

    .PARAMETER ExcludeFilter
        A list of logins to exclude - accepts wildcard patterns

    .PARAMETER ExcludeSystemLogin
        A Switch to remove System Logins from the output.

    .PARAMETER Type
        Filters logins by their type. Valid options are Windows and SQL.

    .PARAMETER Locked
        A Switch to return locked Logins.

    .PARAMETER Disabled
        A Switch to return disabled Logins.

    .PARAMETER MustChangePassword
        A Switch to return Logins that need to change password.

    .PARAMETER SqlLogins
        Deprecated. Please use -Type SQL

    .PARAMETER WindowsLogins
        Deprecated. Please use -Type Windows.

    .PARAMETER HasAccess
        A Switch to return Logins that have access to the instance of SQL Server.

    .PARAMETER Detailed
        A Switch to return additional information available from the LoginProperty function

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security
        Author: Mitchell Hamann (@SirCaptainMitch) | Rob Sewell (@SQLDBaWithBeard)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLogin

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016

        Gets all the logins from server sql2016 using NT authentication and returns the SMO login objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred

        Gets all the logins for a given SQL Server using a passed credential object and returns the SMO login objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred -Login dbatoolsuser,TheCaptain

        Get specific logins from server sql2016 returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -IncludeFilter '##*','NT *'

        Get all user objects from server sql2016 beginning with '##' or 'NT ', returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeLogin dbatoolsuser

        Get all user objects from server sql2016 except the login dbatoolsuser, returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type Windows

        Get all user objects from server sql2016 that are Windows Logins

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type Windows -IncludeFilter *Rob*

        Get all user objects from server sql2016 that are Windows Logins and have Rob in the name

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL

        Get all user objects from server sql2016 that are SQL Logins

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL -IncludeFilter *Rob*

        Get all user objects from server sql2016 that are SQL Logins and have Rob in the name

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeSystemLogin

        Get all user objects from server sql2016 that are not system objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeFilter '##*','NT *'

        Get all user objects from server sql2016 except any beginning with '##' or 'NT ', returned as SMO login objects.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred

        Using Get-DbaLogin on the pipeline, you can also specify which names you would like with -Login.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -Locked

        Using Get-DbaLogin on the pipeline to get all locked logins on servers sql2016 and sql2014.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -HasAccess -Disabled

        Using Get-DbaLogin on the pipeline to get all Disabled logins that have access on servers sql2016 or sql2014.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL -Detailed

        Get all user objects from server sql2016 that are SQL Logins. Get additional info for login available from LoginProperty function

.EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -MustChangePassword

        Using Get-DbaLogin on the pipeline to get all logins that must change password on servers sql2016 and sql2014.
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$IncludeFilter,
        [string[]]$ExcludeLogin,
        [string[]]$ExcludeFilter,
        [Alias('ExcludeSystemLogins')]
        [switch]$ExcludeSystemLogin,
        [ValidateSet('Windows', 'SQL')]
        [string]$Type,
        [switch]$HasAccess,
        [switch]$Locked,
        [switch]$Disabled,
        [switch]$MustChangePassword,
        [switch]$Detailed,
        [switch]$EnableException
    )
    begin {
        if ($SQLLogins) {
            $Type = "SQL"
        }
        if ($WindowsLogins) {
            $Type = "Windows"
        }

        $loginTimeSql = "SELECT login_name, MAX(login_time) AS login_time FROM sys.dm_exec_sessions GROUP BY login_name"
        $loginProperty = "SELECT
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordCount') as BadPasswordCount ,
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordTime') as BadPasswordTime,
                            LOGINPROPERTY ('/*LoginName*/' , 'DaysUntilExpiration') as DaysUntilExpiration,
                            LOGINPROPERTY ('/*LoginName*/' , 'HistoryLength') as HistoryLength,
                            LOGINPROPERTY ('/*LoginName*/' , 'IsMustChange') as IsMustChange,
                            LOGINPROPERTY ('/*LoginName*/' , 'LockoutTime') as LockoutTime,
                            CONVERT (varchar(514),  (LOGINPROPERTY('/*LoginName*/', 'PasswordHash')),1) as PasswordHash,
                            LOGINPROPERTY ('/*LoginName*/' , 'PasswordLastSetTime') as PasswordLastSetTime"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverLogins = $server.Logins

            if ($Login) {
                $serverLogins = $serverLogins | Where-Object Name -in $Login
            }

            if ($ExcludeSystemLogin) {
                $serverLogins = $serverLogins | Where-Object IsSystemObject -eq $false
            }

            if ($Type -eq 'Windows') {
                $serverLogins = $serverLogins | Where-Object LoginType -in @('WindowsUser', 'WindowsGroup')
            }

            if ($Type -eq 'SQL') {
                $serverLogins = $serverLogins | Where-Object LoginType -eq 'SqlLogin'
            }

            if ($IncludeFilter) {
                $serverLogins = $serverLogins | Where-Object {
                    foreach ($filter in $IncludeFilter) {
                        if ($_.Name -like $filter) {
                            return $true;
                        }
                    }
                }
            }

            if ($ExcludeLogin) {
                $serverLogins = $serverLogins | Where-Object Name -NotIn $ExcludeLogin
            }

            if ($ExcludeFilter) {
                foreach ($filter in $ExcludeFilter) {
                    $serverLogins = $serverLogins | Where-Object Name -NotLike $filter
                }
            }

            if ($HasAccess) {
                $serverLogins = $serverLogins | Where-Object HasAccess
            }

            if ($Locked) {
                $serverLogins = $serverLogins | Where-Object IsLocked
            }

            if ($Disabled) {
                $serverLogins = $serverLogins | Where-Object IsDisabled
            }

            if ($MustChangePassword) {
                $serverLogins = $serverLogins | Where-Object MustChangePassword
            }

            # There's no reliable method to get last login time with SQL Server 2000, so only show on 2005+
            if ($server.VersionMajor -gt 9) {
                Write-Message -Level Verbose -Message "Getting last login times"
                $loginTimes = $server.ConnectionContext.ExecuteWithResults($loginTimeSql).Tables[0]
            } else {
                $loginTimes = $null
            }

            foreach ($serverLogin in $serverLogins) {
                Write-Message -Level Verbose -Message "Processing $serverLogin on $instance"
                $loginTime = $loginTimes | Where-Object { $_.login_name -eq $serverLogin.name } | Select-Object -ExpandProperty login_time

                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $loginTime

                if ($Detailed) {
                    $loginName = $serverLogin.name
                    $query = $loginProperty.Replace('/*LoginName*/', "$loginName")
                    $loginProperties = $server.ConnectionContext.ExecuteWithResults($query).Tables[0]
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordCount -Value $loginProperties.BadPasswordCount
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordTime -Value $loginProperties.BadPasswordTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name DaysUntilExpiration -Value $loginProperties.DaysUntilExpiration
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name HistoryLength -Value $loginProperties.HistoryLength
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name IsMustChange -Value $loginProperties.IsMustChange
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LockoutTime -Value $loginProperties.LockoutTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordHash -Value $loginProperties.PasswordHash
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordLastSetTime -Value $loginProperties.PasswordLastSetTime
                }
                Select-DefaultView -InputObject $serverLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled, MustChangePassword
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUdgM204uIslf4BafBpJ1gyOld
# r/OgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFMkfxgCp58lbSA08Xmt/5eHXHZv4MA0GCSqGSIb3DQEBAQUABIIBAJUb3TX1
# t7Xfmc/qPcLHakvjb3/JQ69oUNVooWnnAxpMg8HDsu9crrsizfMRydBJUWAn3dyO
# bZuJX8YW+O7V78fMrjr5ATADK2hzp3yRMx2jjdqmTQ1EifdH7EMu3erLSgBnH3vg
# zjidtDO3A0yZZesM3Hucaq0uik1KXI52KYnC+wX9AiTpUTYfiUmVbc8LGBkf7Ewd
# zTeFJqcBnY1cDvk1g1TE3rBx3aat3P73ixskkpUPTfUNLyLj3ZPkrjdk4VVNn3QR
# KzVbZx8GSvZrklAn3GtgRCYVUur3NtA2gJXjDAUZqQ48t/CFg6zubALQu/iKP3Ut
# 1+bl8+IScgiG5wOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUyMlowLwYJKoZIhvcNAQkEMSIEIO8QlOrMvm5VqUKSLqXiKzwfRE/M
# 1RZVHpjJHv76MzgNMA0GCSqGSIb3DQEBAQUABIIBAE/sJVjmjCPDsEZEvJBtyVbV
# RwftGJk4+6I6oaNKYpyC7Vp+KaOqC8U3xbpPRvc6YFxDSyXI6VWDmX6lRSuDmOhO
# x5op63EqkWua/FShGSBFE1IKI7AO9WoZfm1Ha66nmpe2KABKDF12c83NBH6XHFDx
# bMH19K3pbTkUlFJKuRNKWlzayrLvB3Hc9c577xui8A64cDw8zxLeJvuYCrYHnBJX
# dE+KQcDG8afBrfKXTnegjPE6AMEhmTsYgQKCeBlapZckpBMgrmno/7/l/yL+No82
# VErWSjcwUob6Q7e2WKKWfWEU+8V8bpSSc9pPOH7n11sZ19jGa6U8usuTxyKlbNk=
# SIG # End signature block
