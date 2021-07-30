function Invoke-DbaDbPiiScan {
    <#
    .SYNOPSIS
        Command to return any columns that could potentially contain PII (Personal Identifiable Information)

    .DESCRIPTION
        This command will go through the tables in your database and assess each column.
        It will first check the columns names if it was named in such a way that it would indicate PII.
        The next thing that it will do is pattern recognition by looking into the data from the table.
        Custom scan definitions can be specified using the formats seen in <dbatools module root>\bin\datamasking\pii-knownnames.json and <dbatools module root>\bin\datamasking\pii-patterns.json.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Table(s) to process. By default all the tables will be processed

    .PARAMETER Column
        Column(s) to process. By default all the columns will be processed

    .PARAMETER Country
        Filter out the patterns and known types for one or more countries

    .PARAMETER CountryCode
        Filter out the patterns and known types for one or more country code

    .PARAMETER SampleCount
        Amount of rows to sample to make an assessment. The default is 100

    .PARAMETER KnownNameFilePath
        Points to a file containing the custom known names. Custom scan definitions can be specified using the format seen in <dbatools module root>\bin\datamasking\pii-knownnames.json.

    .PARAMETER PatternFilePath
        Points to a file containing the custom patterns. Custom scan definitions can be specified using the format seen in <dbatools module root>\bin\datamasking\pii-patterns.json.

    .PARAMETER ExcludeDefaultKnownName
        Excludes the default known names

    .PARAMETER ExcludeDefaultPattern
        Excludes the default patterns

    .PARAMETER ExcludeTable
        Exclude certain tables

    .PARAMETER ExcludeColumn
        Exclude certain columns

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Data Masking, Database, Personal Information, GDPR, Policy Compliance
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbPiiScan

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1

        Scan the database db1 on instance sql1

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1, sql2 -Database db1, db2

        Scan multiple databases on multiple instances

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db2 -ExcludeColumn firstname

        Scan database db2 but exclude the column firstname

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db2 -CountryCode US

        Scan database db2 but only apply data patterns used for the United States

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1 -PatternFilePath  c:\pii\patterns.json

        Scans db1 on instance sql1 with additional custom patterns

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1 -PatternFilePath  c:\pii\patterns.json -ExcludeDefaultPattern

        Scans db1 on instance sql1 with additional custom patterns, excluding the default patterns
    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Column,
        [string[]]$Country,
        [string[]]$CountryCode,
        [string[]]$ExcludeTable,
        [string[]]$ExcludeColumn,
        [int]$SampleCount = 100,
        [string]$KnownNameFilePath,
        [string]$PatternFilePath ,
        [switch]$ExcludeDefaultKnownName,
        [switch]$ExcludeDefaultPattern,
        [switch]$EnableException
    )

    begin {
        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $defaultKnownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames = Get-Content -Path $defaultKnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $defaultPatternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $defaultPatternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath
            }
        }

        # Check parameters
        if (-not $SqlInstance) {
            Stop-Function -Message "Please enter a SQL Server instance" -Category InvalidArgument
        }

        if (-not $Database) {
            Stop-Function -Message "Please enter a database" -Category InvalidArgument
        }

        # Filter the patterns
        if ($Country.Count -ge 1) {
            $patterns = $patterns | Where-Object Country -in $Country
        }

        if ($CountryCode.Count -ge 1) {
            $patterns = $patterns | Where-Object CountryCode -in $CountryCode
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $piiScanResults = @()

        # Loop through the instances
        foreach ($instance in $SqlInstance) {

            # Try to connect to the server
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $progressActivity = "Scanning databases for PII"
            $progressId = 1

            # Loop through the databases
            foreach ($dbName in $Database) {

                $progressTask = "Scanning Database $dbName"
                Write-Progress -Id $progressId -Activity $progressActivity -Status $progressTask

                # Get the database object
                $db = $server.Databases[$($dbName)]

                # Filter the tables if needed
                if ($Table) {
                    $tables = $db.Tables | Where-Object Name -in $Table
                } else {
                    $tables = $db.Tables
                }

                if ($ExcludeTable) {
                    $tables = $tables | Where-Object Name -notin $ExcludeTable
                }

                # Filter the tables based on the column
                if ($Column) {
                    $tables = $tables | Where-Object { $ColumnNames = $_.Columns.Name; $Column | Where-Object { $_ -in $ColumnNames } }
                }

                $tableNumber = 1
                $progressStatusText = '"Table $($tableNumber.ToString().PadLeft($($tables.Count).Count.ToString().Length)) of $($tables.Count) | Scanning tables for database $dbName"'
                $progressStatusBlock = [ScriptBlock]::Create($progressStatusText)


                # Loop through the tables
                foreach ($tableobject in $tables) {
                    Write-Message -Level Verbose -Message "Scanning table [$($tableobject.Schema)].[$($tableobject.Name)]"

                    $progressTask = "Scanning columns and data"
                    Write-Progress -Id $progressId -Activity $progressActivity -Status (& $progressStatusBlock) -CurrentOperation $progressTask -PercentComplete ($tableNumber / $($tables.Count) * 100)

                    # Get the columns
                    if ($Column) {
                        $columns = $tableobject.Columns | Where-Object Name -in $Column
                    } else {
                        $columns = $tableobject.Columns
                    }

                    if ($ExcludeColumn) {
                        $columns = $columns | Where-Object Name -notin $ExcludeColumn
                    }

                    # Loop through the columns
                    foreach ($columnobject in $columns) {

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $piiScanResults += [pscustomobject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $dbName
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {

                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($columnobject.Name -match $pattern) {
                                            # Add the column name match if not aleady found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $knownName.Category -and
                                                        $_."PII-Name" -eq $knownName.Name -and
                                                        $_.FoundWith -eq "KnownName" -and
                                                        $_.MaskingType -eq $knownName.MaskingType -and
                                                        $_.MaskingSubType -eq $knownName.MaskingSubType })) {

                                                $piiScanResults += [pscustomobject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $knownName.Category
                                                    "PII-Name"     = $knownName.Name
                                                    FoundWith      = "KnownName"
                                                    MaskingType    = $knownName.MaskingType
                                                    MaskingSubType = $knownName.MaskingSubType
                                                    Pattern        = $knownName.Pattern
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on"
                            }

                            if ($patterns.Count -ge 1) {

                                Write-Message -Level Verbose -Message "Scanning the top $SampleCount values for [$($columnobject.Name)] from [$($tableobject.Schema)].[$($tableobject.Name)]"

                                # Setup the query
                                $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                                # Get the data
                                try {
                                    $dataset = Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $dbName -Query $query -EnableException
                                } catch {
                                    $errormessage = $_.Exception.Message.ToString()
                                    Stop-Function -Message "Error executing query $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $updatequery -Continue -ErrorRecord $_
                                }

                                # Check if there is any data
                                if ($dataset.Count -ge 1) {

                                    # Loop through the patterns
                                    foreach ($patternobject in $patterns) {

                                        # If there is a result from the match
                                        if ($dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                            # Add the data match if not already found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $patternobject.category -and
                                                        $_."PII-Name" -eq $patternobject.Name -and
                                                        $_.FoundWith -eq "Pattern" -and
                                                        $_.MaskingType -eq $patternobject.MaskingType -and
                                                        $_.MaskingSubType -eq $patternobject.MaskingSubType -and
                                                        $_.Country -eq $patternobject.Country -and
                                                        $_.CountryCode -eq $patternobject.CountryCode })) {

                                                $piiScanResults += [pscustomobject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                    Country        = $patternobject.Country
                                                    CountryCode    = $patternobject.CountryCode
                                                    Pattern        = $patternobject.Pattern
                                                    Description    = $patternobject.Description
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on"
                            }
                        }
                    }

                    $tableNumber++

                } # End for each table
            } # End for each database
        } # End for each instance

        $piiScanResults
    } # End process
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUh6eKQhUqz9xfWtJPWEGOx2mL
# zPOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFLHAhTjSmb/DyTeD0odgxjY6zF0hMA0GCSqGSIb3DQEBAQUABIIBAA0FNo4x
# HcRf2mVWCuuSQT6ureDF9uK4NPecNZElfRHyEMfwRSdxMt4hb3hCZ9sDX6rBPEc5
# hcxyVj0kzedDCX4TxxJWdupF3xZI2X+et++0UEMZryv59l6v9AwOZ/Xc5Sg/gBfm
# Z02xsgscP/G5f587MeKZWF91VVyayG507B5uR4yZe8R6v59yrZXx9JioxWFMxmdX
# oAumR6DlY937vqB85TvvxK6VA5ZGCBekbut95O/Kvw3LQEF3LnPpfDQKcokb82Q9
# f5/6Y85ZsgnXjr5dKaDhe9Bn3wqhnzz8Epae/HWqCQgzJDuhWMPSQOUSkbLVcxfi
# ODzS2nKlJtWeoCihggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MVowLwYJKoZIhvcNAQkEMSIEIPjaBL2D5JX+JlRVZ4nQF1JAEb28
# 4nKHHcfpY3nU1qQwMA0GCSqGSIb3DQEBAQUABIIBALkFZ21nEyx7oUE+NIUYIS8r
# YkVZieYic7Rj478qb81/3p2+iUVNV9m5g6GUelkg118SAKTGCyZjwANchfaGMoKN
# z/RMaw+vR/O1sJjqyMvowrfiQmREfeAI7So2jkiV6Lb8PedSJV5eUq7bYovtieDt
# +Xx3mXrCpFOqBwjD0xByGUyXPlAHqSaiAagJpdzYRnBD3rSzHP1UF2iLcKPN+cSW
# cPTG7CX12J7my8aVZDcrQWGneFRctUTBSwcT+f8OKmd5bSTonJ3qS5gcE/TgTAVd
# SzbqYO9zGuZYRvYGnwZR7MnCcl+cbuhQEJHDP+xUBI2O4JWReO9kkV7weDHSRhU=
# SIG # End signature block
