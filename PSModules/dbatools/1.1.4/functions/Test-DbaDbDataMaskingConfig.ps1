function Test-DbaDbDataMaskingConfig {
    <#
    .SYNOPSIS
        Checks the masking configuration if it's valid

    .DESCRIPTION
        When you're dealing with large masking configurations, things can get complicated and messy.
        This function will test for a range of rules and returns all the tables and columns that contain errors.

    .PARAMETER FilePath
        Path to the file to test

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing objects on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Masking, DataMasking
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaDbDataMaskingConfig

    .EXAMPLE
        Test-DbaDbDataMaskingConfig -FilePath C:\temp\_datamasking\db1.json

        Test the configuration file
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$FilePath,
        [switch]$EnableException
    )
    begin {
        if (-not (Test-Path -Path $FilePath)) {
            Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath
            return
        }

        # Get all the items that should be processed
        try {
            $json = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
        }

        if (-not $json.Type) {
            Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataMaskingConfiguration`", '" -Target $json.Type
            return
        }

        if ($json.Type -ne "DataMaskingConfiguration") {
            Stop-Function -Message "Configuration file is not a valid masking configuration. Type found '$($json.Type)'" -Target $json.Type
            return
        }

        $supportedDataTypes = @('bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'float', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar')

        $randomizerTypes = Get-DbaRandomizedType

        $requiredColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'SubType')
        $allowedColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'Separator', 'SubType', 'StaticValue')

        $allowedActionCategories = @('datetime', 'number', 'column')
        $allowedActionSubCategories = @('year', 'quarter', 'month', 'dayofyear', 'day', 'week', 'weekday', 'hour', 'minute', 'second', 'millisecond', 'microsecond', 'nanosecond')
        $allowedActionTypes = @('Add', 'Divide', 'Multiply', 'Nullify', 'Set', 'Subtract')

        $allowedDateTimeTypes = @('date', 'datetime', 'datetime2', 'smalldatetime', 'time')
        $allowedNumberTypes = @('bigint', 'bit', 'int', 'money', 'smallint')

        $requiredDateTimeActionProperties = @('Category', 'Subcategory', 'Type', 'Value')
        $requiredNumberActionProperties = @('Category', 'Type', 'Value')
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($table in $json.Tables) {

            foreach ($column in $table.Columns) {

                # Test the column properties
                $columnProperties = $column | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name
                $compareResultRequired = Compare-Object -ReferenceObject $requiredColumnProperties -DifferenceObject $columnProperties
                $compareResultAllowed = Compare-Object -ReferenceObject $allowedColumnProperties -DifferenceObject $columnProperties

                if ($null -ne $compareResultRequired) {
                    if ($compareResultRequired.SideIndicator -contains "<=") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultRequired | Where-Object SideIndicator -eq "<=").InputObject -join ","
                            Error  = "The column does not contain all the required properties. Please check the column "
                        }
                    }
                }

                if ($null -ne $compareResultAllowed) {
                    if ($compareResultAllowed.SideIndicator -contains "=>") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultAllowed | Where-Object SideIndicator -eq "=>").InputObject -join ","
                            Error  = "The column contains a property that is not in the allowed properties. Please check the column"
                        }
                    }
                }

                # Test column type
                if ($column.ColumnType -notin $supportedDataTypes) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.ColumnType
                        Error  = "ColumnType is not a supported data type "
                    }
                }

                # Test masking type
                if ($column.MaskingType -notin $randomizerTypes.Type) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.MaskingType
                        Error  = "MaskingType is not valid"
                    }
                }

                # Test masking sub type
                if ($null -ne $column.SubType -and $column.SubType -notin $randomizerTypes.SubType) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.SubType
                        Error  = "SubType is not valid"
                    }
                }

                # Test date types
                if ($column.ColumnType.ToLower() -eq 'date') {

                    if ($column.MaskingType -ne 'Date' -and ($column.SubType -ne 'DateOfBirth' -and $null -ne $column.Subtype)) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.MaskingType
                            Error  = "MaskingType should be date when ColumnType is 'date'"
                        }
                    }

                    if ($null -ne $Column.SubType -and $Column.SubType.ToLower() -eq 'between') {

                        if (-not ($null -eq $column.MinValue) -and -not ([datetime]::TryParse($column.MinValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MinValue
                                Error  = "The value for MinValue is not a valid date"
                            }
                        }

                        if (-not ($null -eq $column.MaxValue) -and -not ([datetime]::TryParse($column.MaxValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MaxValue
                                Error  = "The value for MaxValue is not a valid date"
                            }
                        }

                        if ($null -eq $column.MinValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MinValue cannot be 'null' when using sub type 'Between'"
                            }
                        }

                        if ($null -eq $column.MaxValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MaxValue cannot be 'null' when using sub type 'Between'"
                            }
                        }
                    }
                }

                # Test actions
                if ($column.Action) {
                    # General checks

                    if ($null -ne $column.Action.Category -and $column.Action.Category -notin $allowedActionCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action category '$($column.Action.Category)' is not allowed"
                        }
                    }

                    if ($null -ne $column.Action.Category -and $column.Action.Type -notin $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action type '$($column.Action.Type)' is not allowed"
                        }
                    }

                    if ($column.Action.Category -ne 'Column' -and $column.Action.Type -ne 'Nullify' -and $null -eq $column.Action.Value -and $column.Action.Type -in $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action value cannot be empty"
                        }
                    }

                    if (-not $null -eq $column.Action.SubCategory -and $column.Action.SubCategory -notin $allowedActionSubCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action subcategory cannot be empty"
                        }
                    }

                    $actionProperties = $column.Action | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name

                    # Date checks
                    if ($column.Action.Category -eq 'datetime' ) {

                        $compareResult = Compare-Object -ReferenceObject $requiredDateTimeActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }

                            if ($compareResult.SideIndicator -contains "=>") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "=>").InputObject -join ","
                                    Error  = "The action contains a property that is not in the required properties. Please check the column"
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedDateTimeTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }

                    # Number checks
                    if ($column.Action.Category -eq 'number' ) {
                        $compareResult = Compare-Object -ReferenceObject $requiredNumberActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedNumberTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }
                } # End column action
            } # End for each column
        } # End for each table
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+2PD6AaPWcVvR5YeUudLec/V
# OSygghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFLpMLwmyPMjJCQp1hwIc6D/a0Xy9MA0GCSqGSIb3DQEBAQUABIIBAGjiUEKL
# s9x/28pLCwV9smN5nl+HMDvahXrQYXZRXNTcfL9HWp8Uirn4v0swJc0xq2S6QhGe
# CLfx7Io7iM7yZXPqEeghwTpeJLJ6u02P12zTvgNy3LQz6i9WBcbQ1apikA8q7/F7
# OxrJl/ZqG5l29cx0XorTqwAF3gLGibZ4fqq6+FqB5xFL8ZIuFtP/7hP7WoxdtGy0
# IWYk/B1wtmYdJAS0KHLz7D5KQPjFoCMq9OPEnVMmguoOdvgZ7td/TsDvBwPdZsKf
# KV4iWwxjHTH1UBuwSsEZIb8TLOw30YVq6bSr6vWomFW8jypnzbo/n0jw7POklf7j
# 3BJVEJTiFl9LD4qhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxNFowLwYJKoZIhvcNAQkEMSIEILt0pqFSrJgiGZywLn8Wl3BTvhc6
# 54Vk4cNQYBOC96eVMA0GCSqGSIb3DQEBAQUABIIBAGUNSFkkt0qnw2idVSo8VIrx
# mGMAk5XbXZZIrkAXpTvZW0t9r0WFkdlmEoXYoLnXO4dXf0PR3bN9dvZ5LZS3tymq
# 9N0448WX/yPAF4Wotrrkj8T0ueGlp/qNR4+cqjegEQE0wERCsCDjuEGzz10yzhvs
# PXBuAlnAuXJprst3UWKPDgrh/+46my+aCe/vdsYOuL92JaJA8YY5QZ6MFOKUWhvH
# c717wF3DnNjtNHwWHIP0jz86EKSaxOq94Pk5aGkeHwtPKweP7lp9alIr4APe/Uxa
# ES8o6t/cDH+kBQCz+Cl8XgicbUraZQyYQJI2tJb2uyd7GuMuLn7d5DxBraKingo=
# SIG # End signature block
