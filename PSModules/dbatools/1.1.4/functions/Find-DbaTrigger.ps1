function Find-DbaTrigger {
    <#
    .SYNOPSIS
        Returns all triggers that contain a specific case-insensitive string or regex pattern.

    .DESCRIPTION
        This function search on Instance, Database and Object level.
        If you specify one or more databases, search on Server level will not be preformed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Pattern
        String pattern that you want to search for in the trigger text body

    .PARAMETER TriggerLevel
        Allows specify the trigger level that you want to search. By default is All (Server, Database, Object).

    .PARAMETER IncludeSystemObjects
        By default, system triggers are ignored but you can include them within the search using this parameter.

        Warning - this will likely make it super slow if you run it on all databases.

    .PARAMETER IncludeSystemDatabases
        By default system databases are ignored but you can include them within the search using this parameter

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trigger
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaTrigger

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance DEV01 -Pattern whatever

        Searches all user databases triggers for "whatever" in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

        Searches all databases for all triggers that contain a valid email pattern in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

        Searches in "mydb" database triggers for "some string" in the text body

    .EXAMPLE
        PS C:\> Find-DbaTrigger -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

        Searches in "mydb" database triggers for "runtime" in the text body

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory)]
        [string]$Pattern,
        [ValidateSet('All', 'Server', 'Database', 'Object')]
        [string]$TriggerLevel = 'All',
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        $sqlDatabaseTriggers = "SELECT tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 0"

        $sqlTableTriggers = "SELECT OBJECT_SCHEMA_NAME(tr.parent_id) TableSchema, OBJECT_NAME(tr.parent_id) AS TableName, tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 1"
        if (!$IncludeSystemObjects) { $sqlTableTriggers = "$sqlTableTriggers AND tr.is_ms_shipped = 0" }

        $everyserverstcount = 0
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            } catch {
                Write-Message -Level Warning -Message "Failed to connect to: $Instance"
                continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            #search at instance level. Only if no database was specified
            if ((-Not $Database) -and ($TriggerLevel -in @('All', 'Server'))) {
                foreach ($trigger in $server.Triggers) {
                    $everyserverstcount++; $triggercount++
                    Write-Message -Level Debug -Message "Looking in Trigger: $trigger TextBody for $pattern"
                    if ($trigger.TextBody -match $Pattern) {

                        $triggerText = $trigger.TextBody.split("`n`r")
                        $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            SqlInstance      = $server.ServiceName
                            TriggerLevel     = "Server"
                            Database         = $null
                            Object           = $null
                            Name             = $trigger.Name
                            IsSystemObject   = $trigger.IsSystemObject
                            CreateDate       = $trigger.CreateDate
                            LastModified     = $trigger.DateLastModified
                            TriggerTextFound = $trTextFound -join "`n"
                            Trigger          = $trigger
                            TriggerFullText  = $trigger.TextBody
                        } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                    }
                }
                Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $server"
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            } else {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            $totalcount = 0
            $dbcount = $dbs.count

            if ($TriggerLevel -in @('All', 'Database', 'Object')) {
                foreach ($db in $dbs) {

                    Write-Message -Level Verbose -Message "Searching on database $db"

                    # If system objects aren't needed, find trigger text using SQL
                    # This prevents SMO from having to enumerate

                    if (!$IncludeSystemObjects) {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            Write-Message -Level Debug -Message $sqlDatabaseTriggers
                            $rows = $db.ExecuteWithResults($sqlDatabaseTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($row.TextBody -match $Pattern) {
                                    $tr = $db.Triggers | Where-Object name -eq $row.name

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            Write-Message -Level Debug -Message $sqlTableTriggers
                            $rows = $db.ExecuteWithResults($sqlTableTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name
                                $triggerParentSchema = $row.TableSchema
                                $triggerParent = $row.TableName

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $triggerParentSchema.$triggerParent at database $db"
                                if ($row.TextBody -match $Pattern) {

                                    $tr = ($db.Tables | Where-Object { $_.Name -eq $triggerParent -and $_.Schema -eq $triggerParentSchema }).Triggers | Where-Object name -eq $row.name
                                    if ($null -eq $tr) {
                                        Write-Message -Level Verbose -Message "Could not find table named $($row.Name). Will try to find on Views."
                                        $tr = ($db.Views | Where-Object { $_.Name -eq $triggerParent -and $_.Schema -eq $triggerParentSchema }).Triggers | Where-Object name -eq $row.name
                                    }

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    } else {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            $triggers = $db.Triggers

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            $triggers = $db.Tables | ForEach-Object { $_.Triggers }
                            $triggers += $db.Views | ForEach-Object { $_.Triggers }

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $($tr.Parent) at database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.ComputerName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    }
                    Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $db"
                }
            }
            Write-Message -Level Verbose -Message "Evaluated $totalcount total triggers in $dbcount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Evaluated $everyserverstcount total triggers"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUX/yz2SRGxvjZDbvbqRoX2RBx
# JL+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFALd8uEffLK9efxcJ/jgxeIl54mnMA0GCSqGSIb3DQEBAQUABIIBAHky9EFK
# zdgJ2TtOIlhD4WWdFA2TJ+IsEgNJctRcFFDByrN4xZKh/mLJZ9wJJvX1vnnSDh5r
# b50EDUpxNQhpWbvtjVGNQZvs42XKrdfm+yJBpiLTOO16zufwnuw5/nO/DdXE03FS
# n4l4oZ4A1InOxF3rWTDHoSmQ3ktK0Fe6uV7z+/xLHcirB0oKa9XN4ok3Crdr4/pz
# 9MvE4bCS3BPhUduEOIkEI8A+nhDPlmfP21cEoDqDpt7URne8ZSbeOKQAxBYu7jb0
# GRIWQg2skKJbWvOYSfJT37GY7PLE8Mhia89KBvbZ52LXPnN7pNBXqTMEwzEYBx8d
# TFK+SxXbOoUvtbmhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyM1owLwYJKoZIhvcNAQkEMSIEIJw5Vx7Iq4GI/wZhg1tQr6h8Yekv
# IoqAzbPDM6gZZrW1MA0GCSqGSIb3DQEBAQUABIIBAEWqPveXC/3bvw2kj7PixWc6
# BHmxBBzHFdV+/vokc/n6SzCj/a6dhoNVqazFe1a6fNRNJED7To7BeLeiWsSJxW34
# xP2zLJxPwCqwyqzmEuEvZaW2loAppqdSvEtq+ki2udxoSU83fIVlECGF3xC88Zt9
# 72DmopJKK9NNejGB4wZYbu2e2RXEizv+3o7QTsBr8bIccit5Cw2S9Hk7NlVvSJi5
# RvDCi8ozUZhIZbQ2cPTdfUr71vJ16YAbdKjvFKUZrxSmZV3GhG4UKy+Yxu0pL2B9
# V9uu1LX4ZNEJ83fA/eIeh0RITUj7jLuE5rgQef1YJ1gZAcQKYI8kCUmXfEcwU4A=
# SIG # End signature block
