function ConvertTo-DbaDataTable {
    <#
    .SYNOPSIS
        Creates a DataTable for an object.

    .DESCRIPTION
        Creates a DataTable based on an object's properties. This allows you to easily write to SQL Server tables.

        Thanks to Chad Miller, this is based on his script. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd

        If the attempt to convert to data table fails, try the -Raw parameter for less accurate datatype detection.

    .PARAMETER InputObject
        The object to transform into a DataTable.

    .PARAMETER TimeSpanType
        Specifies the type to convert TimeSpan objects into. Default is 'TotalMilliseconds'. Valid options are: 'Ticks', 'TotalDays', 'TotalHours', 'TotalMinutes', 'TotalSeconds', 'TotalMilliseconds', and 'String'.

    .PARAMETER SizeType
        Specifies the type to convert DbaSize objects to. Default is 'Int64'. Valid options are 'Int32', 'Int64', and 'String'.

    .PARAMETER IgnoreNull
        If this switch is enabled, objects with null values will be ignored (empty rows will be added by default).

    .PARAMETER Raw
        If this switch is enabled, the DataTable will be created with strings. No attempt will be made to parse/determine data types.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataTable, Table, Data
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io/
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/ConvertTo-DbaDataTable

    .OUTPUTS
        System.Object[]

    .EXAMPLE
        PS C:\> Get-Service | ConvertTo-DbaDataTable

        Creates a DataTable from the output of Get-Service.

    .EXAMPLE
        PS C:\> ConvertTo-DbaDataTable -InputObject $csv.cheesetypes

        Creates a DataTable from the CSV object $csv.cheesetypes.

    .EXAMPLE
        PS C:\> $dblist | ConvertTo-DbaDataTable

        Creates a DataTable from the $dblist object passed in via pipeline.

    .EXAMPLE
        PS C:\> Get-Process | ConvertTo-DbaDataTable -TimeSpanType TotalSeconds

        Creates a DataTable with the running processes and converts any TimeSpan property to TotalSeconds.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Position = 0,
            Mandatory,
            ValueFromPipeline)]
        [AllowNull()]
        [PSObject[]]$InputObject,
        [ValidateSet("Ticks",
            "TotalDays",
            "TotalHours",
            "TotalMinutes",
            "TotalSeconds",
            "TotalMilliseconds",
            "String")]
        [ValidateNotNullOrEmpty()]
        [string]$TimeSpanType = "TotalMilliseconds",
        [ValidateSet("Int64", "Int32", "String")]
        [string]$SizeType = "Int64",
        [switch]$IgnoreNull,
        [switch]$Raw,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        Write-Message -Level Debug -Message "TimeSpanType = $TimeSpanType | SizeType = $SizeType"

        function Convert-Type {
            # This function will check so that the type is an accepted type which could be used when inserting into a table.
            # If a type is accepted (included in the $type array) then it will be passed on, otherwise it will first change type before passing it on.
            # Special types will have both their types converted as well as the value.
            # TimeSpan is a special type and will be converted into the $timespantype. (default: TotalMilliseconds) so that the timespan can be stored in a database further down the line.
            [CmdletBinding()]
            param (
                $type,
                $value,
                $timespantype = 'TotalMilliseconds',
                $sizetype = 'Int64'
            )

            $types = [System.Collections.ArrayList]@(
                'System.Int32',
                'System.UInt32',
                'System.Int16',
                'System.UInt16',
                'System.Int64',
                'System.UInt64',
                'System.Decimal',
                'System.Single',
                'System.Double',
                'System.Byte',
                'System.Byte[]',
                'System.SByte',
                'System.Boolean',
                'System.DateTime',
                'System.Guid',
                'System.Char'
            )

            # The $special variable is used to mark the return value if a conversion was made on the value itself.
            # If this is set to true the original value will later be ignored when updating the DataTable.
            # And the value returned from this function will be used instead. (cannot modify existing properties)
            $special = $false
            $specialType = ""

            # Special types need to be converted in some way.
            # This attempt is to convert timespan into something that works in a table.
            # I couldn't decide on what to convert it to so the user can decide.
            # If the parameter is not used, TotalMilliseconds will be used as default.
            # Ticks are more accurate but I think milliseconds are more useful most of the time.
            if (($type -eq 'System.TimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty')) {
                $special = $true
                if ($timespantype -eq 'String') {
                    $value = $value.ToString()
                    $type = 'System.String'
                } else {
                    # Let's use Int64 for all other types than string.
                    # We could match the type more closely with the timespantype but that can be added in the future if needed.
                    $value = $value.$timespantype
                    $type = 'System.Int64'
                }
                $specialType = 'Timespan'
            } elseif ($type -eq 'Sqlcollaborative.Dbatools.Utility.Size') {
                $special = $true
                switch ($sizetype) {
                    'Int64' {
                        $value = $value.Byte
                        $type = 'System.Int64'
                    }
                    'Int32' {
                        $value = $value.Byte
                        $type = 'System.Int32'
                    }
                    'String' {
                        $value = $value.ToString()
                        $type = 'System.String'
                    }
                }
                $specialType = 'Size'
            } elseif (-not ($type -in $types)) {
                # All types which are not found in the array will be converted into strings.
                # In this way we don't ignore it completely and it will be clear in the end why it looks as it does.
                $type = 'System.String'
            }

            # return a hashtable instead of an object. I like hashtables :)
            return @{ type = $type; Value = $value; Special = $special; SpecialType = $specialType }
        }

        function Convert-SpecialType {
            <#
            .SYNOPSIS
                Converts a value for a known column.

            .DESCRIPTION
                Converts a value for a known column.

            .PARAMETER Value
                The value to convert

            .PARAMETER Type
                The special type for which to convert

            .PARAMETER SizeType
                The size type defined by the user

            .PARAMETER TimeSpanType
                The timespan type defined by the user
        #>
            [CmdletBinding()]
            param (
                $Value,
                [ValidateSet('Timespan', 'Size')]
                [string]$Type,
                [string]$SizeType,
                [string]$TimeSpanType
            )

            switch ($Type) {
                'Size' {
                    if ($SizeType -eq 'String') { return $Value.ToString() }
                    else { return $Value.Byte }
                }
                'Timespan' {
                    if ($TimeSpanType -eq 'String') {
                        $Value.ToString()
                    } else {
                        $Value.$TimeSpanType
                    }
                }
            }
        }

        function Add-Column {
            <#
            .SYNOPSIS
                Adds a column to the datatable in progress.

            .DESCRIPTION
                Adds a column to the datatable in progress.

            .PARAMETER Property
                The property for which to add a column.

            .PARAMETER DataTable
                Autofilled. The table for which to add a column.

            .PARAMETER TimeSpanType
                Autofilled. How should timespans be handled?

            .PARAMETER SizeType
                Autofilled. How should sizes be handled?

            .PARAMETER Raw
                Autofilled. Whether the column should be string, no matter the input.
        #>
            [CmdletBinding()]
            param (
                [System.Management.Automation.PSPropertyInfo]$Property,
                [System.Data.DataTable]$DataTable = $datatable,
                [string]$TimeSpanType = $TimeSpanType,
                [string]$SizeType = $SizeType,
                [bool]$Raw = $Raw
            )

            $type = $property.TypeNameOfValue
            try {
                if ($Property.MemberType -like 'ScriptProperty') {
                    $type = $Property.GetType().FullName
                }
            } catch { $type = 'System.String' }

            $converted = Convert-Type -type $type -value $property.Value -timespantype $TimeSpanType -sizetype $SizeType

            $column = New-Object System.Data.DataColumn
            $column.ColumnName = $property.Name.ToString()
            if (-not $Raw) {
                $column.DataType = [System.Type]::GetType($converted.type)
            }
            $null = $DataTable.Columns.Add($column)
            $converted
        }

        $datatable = New-Object System.Data.DataTable

        # Accelerate subsequent lookups of columns and special type columns
        $columns = @()
        $specialColumns = @()
        $specialColumnsType = @{ }

        $ShouldCreateColumns = $true
    }

    process {
        #region Handle null objects
        if ($null -eq $InputObject) {
            if (-not $IgnoreNull) {
                $datarow = $datatable.NewRow()
                $datatable.Rows.Add($datarow)
            }

            # Only ends the current process block
            return
        }
        #endregion Handle null objects


        foreach ($object in $InputObject) {
            #region Handle null objects
            if ($null -eq $object) {
                if (-not $IgnoreNull) {
                    $datarow = $datatable.NewRow()
                    $datatable.Rows.Add($datarow)
                }
                continue
            }
            #endregion Handle null objects

            #Handle rows already being System.Data.DataRow
            if ($object.GetType().FullName -eq 'System.Data.DataRow') {
                $datatable.Merge($object.Table)
                $datatable = $datatable.DefaultView.ToTable($true)
                continue
            }

            # The new row to insert
            $datarow = $datatable.NewRow()

            #region Process Properties
            $objectProperties = $object.PSObject.Properties
            foreach ($property in $objectProperties) {
                #region Create Columns as needed
                if ($ShouldCreateColumns) {
                    $newColumn = Add-Column -Property $property
                    $columns += $property.Name
                    if ($newColumn.Special) {
                        $specialColumns += $property.Name
                        $specialColumnsType[$property.Name] = $newColumn.SpecialType
                    }
                }
                #endregion Create Columns as needed

                # Handle null properties, as well as properties with access errors
                try {
                    $propValueLength = $property.value.length
                } catch {
                    $propValueLength = 0
                }

                #region Insert value into column of row
                if ($propValueLength -gt 0) {
                    # If the typename was a special typename we want to use the value returned from Convert-Type instead.
                    # We might get error if we try to change the value for $property.value if it is read-only. That's why we use $converted.value instead.
                    if ($property.Name -in $specialColumns) {
                        $datarow.Item($property.Name) = Convert-SpecialType -Value $property.value -Type $specialColumnsType[$property.Name] -SizeType $SizeType -TimeSpanType $TimeSpanType
                    } else {
                        if ($property.value.ToString().length -eq 15) {
                            if ($property.value.ToString() -eq 'System.Object[]') {
                                $value = $property.value -join ", "
                            } elseif ($property.value.ToString() -eq 'System.String[]') {
                                $value = $property.value -join ", "
                            } else {
                                $value = $property.value
                            }
                        } else {
                            $value = $property.value
                        }

                        try {
                            $datarow.Item($property.Name) = $value
                        } catch {
                            if ($property.Name -notin $columns) {
                                try {
                                    $newColumn = Add-Column -Property $property
                                    $columns += $property.Name
                                    if ($newColumn.Special) {
                                        $specialColumns += $property.Name
                                        $specialColumnsType[$property.Name] = $newColumn.SpecialType
                                    }

                                    $datarow.Item($property.Name) = $newColumn.Value
                                } catch {
                                    Stop-Function -Message "Failed to add property $($property.Name) from $object" -ErrorRecord $_ -Target $object
                                }
                            } else {
                                Stop-Function -Message "Failed to add property $($property.Name) from $object" -ErrorRecord $_ -Target $object
                            }
                        }
                    }
                }
                #endregion Insert value into column of row
            }

            $datatable.Rows.Add($datarow)
            # If this is the first non-null object then the columns has just been created.
            # Set variable to false to skip creating columns from now on.
            if ($ShouldCreateColumns) {
                $ShouldCreateColumns = $false
            }
            #endregion Process Properties
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Finished."
        , $datatable
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0B3DHdI8uI3DHZgIzisUvqPE
# SuOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFJbdF/IkkFjMhkLS3u3/g06ukcMEMA0GCSqGSIb3DQEBAQUABIIBACtnk2+H
# Yz/w/KC2m70llDJyBi8+JQ9P62uR/bHGhtjveYw88F7gGlQ/OaBNaLSSWDeyyuC/
# xpwjqaJzl1780mEijyItUpSyfJKlFUg7Bf/BC21/PytAIPj0AGtTa4zWHeIXL0zx
# NxQBbuAelcYUDI134nioL9H1AHP1KeY3QEA7JEf0Lu0IRgAdMORQxxBqcAF3p648
# aSScP/0r0Olh4HnbPu0UWopoAoVyKpvCsJRIC0FksUk2yOPXJegCUuPbEbTTxjsP
# vCJxB9Yzm09cBkmRZ4GIcqTuKqFpR7vOLXQzWBlp7eZYZvj+nyzf6AocstOmQWCV
# BcDqEnMR4Dj3q8ehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjQ1N1owLwYJKoZIhvcNAQkEMSIEIJizd7vRg3aapY73kxf5e//+av3i
# S4O1KHT+k+kIlhm7MA0GCSqGSIb3DQEBAQUABIIBALGusjd0byAsJt/h+DhCOkL9
# W0CkgFq2SoWUrQP8cjkRN7iojhjjVG0Fg6Niszrb1GYzKIFge6yf/jO4m4/XReOG
# lgYjTq4n5H2oRzgtM4O4UyOiMuZkjlYOJska4kBP9CrW0XZAeFY7wONtm3CFoqzQ
# W20Um3QbcPI7KR2PVEnFcKto7wGf6vRSy+wXF0/9dUrr0kLWRBZ2JX2mx5dj+jDZ
# QOx1R9o6qoEbPoCyA+wQfEHFLbpjR9Hj342Qo3DNjwHLpSpQ4AOepYlfTGD38HQz
# z/n7Ol/i8E9RkYwp4CBmA0GoqHwtSz3pUboNbcEXGmjrkvUYm1rFIIsf/jL9Va4=
# SIG # End signature block
