function Get-DbaRandomizedValue {
    <#
    .SYNOPSIS
        This function will generate a random value for a specific data type or bogus type and subtype

    .DESCRIPTION
        Generates a random value based on the assigned sql data type or bogus type with sub type.
        It supports a wide range of sql data types and an entire dictionary of various random values.

    .PARAMETER DataType
        The target SQL Server instance or instances.

        Supported data types are bigint, bit, bool, char, date, datetime, datetime2, decimal, int, float, guid, money, numeric, nchar, ntext, nvarchar, real, smalldatetime, smallint, text, time, tinyint, uniqueidentifier, userdefineddatatype, varchar

    .PARAMETER RandomizerType
        Bogus type to use.

        Supported types are Address, Commerce, Company, Database, Date, Finance, Hacker, Hashids, Image, Internet, Lorem, Name, Person, Phone, Random, Rant, System

    .PARAMETER RandomizerSubType
        Subtype to use.

    .PARAMETER Min
        Minimum value used to generate certain lengths of values. Default is 0

    .PARAMETER Max
        Maximum value used to generate certain lengths of values. Default is 255

    .PARAMETER Precision
        Precision used for numeric sql data types like decimal, numeric, real and float

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER Format
        Use specilized formatting with certain randomizer types like phone number.

    .PARAMETER Symbol
        Use a symbol in front of the value i.e. $100,12

    .PARAMETER Separator
        Some masking types support separators

    .PARAMETER Value
        This is the value that needs to be used for several possible transformations.
        One example is the subtype "Shuffling" where the value will be shuffled.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue -DataType bit

        Will return either a 1 or 0

    .EXAMPLE
        Get-DbaRandomizedValue -DataType int

        Will generate a number between -2147483648 and 2147483647

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode

        Generates a random zipcode

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode -Format "#### ##"

        Generates a random zipcode like "1234 56"

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType PhoneNumber -Format "(###) #######"

        Generates a random phonenumber like "(123) 4567890"

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [object]$Min,
        [object]$Max,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Format,
        [string]$Symbol,
        [string]$Separator,
        [string]$Value,
        [string]$Locale = 'en',
        [switch]$EnableException
    )


    begin {
        # Create faker object
        if (-not $script:faker) {
            $script:faker = New-Object Bogus.Faker($Locale)
        }

        # Get all the random possibilities
        if (-not $script:randomizerTypes) {
            $script:randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv") | Group-Object { $_.Type }
        }

        if (-not $script:uniquesubtypes) {
            $script:uniquesubtypes = $script:randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type -First 1
        }

        if (-not $script:uniquerandomizertypes) {
            $script:uniquerandomizertypes = ($script:randomizerTypes.Group.Type | Select-Object -Unique)
        }

        if (-not $script:uniquerandomizersubtype) {
            $script:uniquerandomizersubtype = ($script:randomizerTypes.Group.SubType | Select-Object -Unique)
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $script:uniquesubtypes
        }

        if ($DataType -and $DataType.ToLowerInvariant() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin $script:uniquerandomizertypes) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin $script:uniquerandomizersubtype) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType
            }

            if ($RandomizerSubType.ToLowerInvariant() -eq 'shuffle' -and $null -eq $Value) {
                Stop-Function -Message "Value cannot be empty when using sub type 'Shuffle'" -Continue -Target $RandomizerSubType
            }
        }

        if ($null -eq $Min) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Min = 1
            }
        }

        if ($null -eq $Max) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Max = 255
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType) {

            switch ($DataType.ToLowerInvariant()) {
                'bigint' {
                    if (-not $Min -or $Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Long($Min, $Max)
                }

                { $psitem -in 'bit', 'bool' } {
                    if ($script:faker.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                'date' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime2' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                { $psitem -in 'decimal', 'float', 'money', 'numeric', 'real' } {
                    $script:faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if (-not $Min -or $Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 2147483647 -or $Max -lt $Min) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)

                }
                'smalldatetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'smallint' {
                    if (-not $Min -or $Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 32767 -or $Max -lt $Min) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                'time' {
                    ($script:faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if (-not $Min -or $Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 255 -or $Max -lt $Min) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                { $psitem -in 'uniqueidentifier', 'guid' } {
                    $script:faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($script:faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $psitem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $script:faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {

            $randSubType = $RandomizerSubType.ToLowerInvariant()

            switch ($RandomizerType.ToLowerInvariant()) {
                'address' {

                    if ($randSubType -in 'latitude', 'longitude') {
                        $script:faker.Address.Latitude($Min, $Max)
                    } elseif ($randSubType -eq 'zipcode') {
                        if ($Format) {
                            $script:faker.Address.ZipCode("$($Format)")
                        } else {
                            $script:faker.Address.ZipCode()
                        }
                    } else {
                        $script:faker.Address.$RandomizerSubType()
                    }

                }
                'commerce' {
                    if ($randSubType -eq 'categories') {
                        $script:faker.Commerce.Categories($Max)
                    } elseif ($randSubType -eq 'departments') {
                        $script:faker.Commerce.Department($Max)
                    } elseif ($randSubType -eq 'price') {
                        $script:faker.Commerce.Price($min, $Max, $Precision, $Symbol)
                    } else {
                        $script:faker.Commerce.$RandomizerSubType()
                    }

                }
                'company' {
                    $script:faker.Company.$RandomizerSubType()
                }
                'database' {
                    $script:faker.Database.$RandomizerSubType()
                }
                'date' {
                    if ($randSubType -eq 'between') {

                        if (-not $Min) {
                            Stop-Function -Message "Please set the minimum value for the date" -Continue -Target $Min
                        }

                        if (-not $Max) {
                            Stop-Function -Message "Please set the maximum value for the date" -Continue -Target $Max
                        }

                        if ($Min -gt $Max) {
                            Stop-Function -Message "The minimum value for the date cannot be later than maximum value" -Continue -Target $Min
                        } else {
                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'past') {
                        if ($Max) {
                            if ($Min) {
                                $yearsToGoBack = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoBack = 1
                            }

                            $script:faker.Date.Past($yearsToGoBack, $Max).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'future') {
                        if ($Min) {
                            if ($Max) {
                                $yearsToGoForward = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoForward = 1
                            }

                            $script:faker.Date.Future($yearsToGoForward, $Min).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Future().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }

                    } elseif ($randSubType -eq 'recent') {
                        $script:faker.Date.Recent().ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } elseif ($randSubType -eq 'random') {
                        if ($Min -or $Max) {
                            if (-not $Min) {
                                $Min = Get-Date
                            }

                            if (-not $Max) {
                                $Max = (Get-Date).AddYears(1)
                            }

                            ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } else {
                        $script:faker.Date.$RandomizerSubType()
                    }
                }
                'finance' {
                    if ($randSubType -eq 'account') {
                        $script:faker.Finance.Account($Max)
                    } elseif ($randSubType -eq 'amount') {
                        $script:faker.Finance.Amount($Min, $Max, $Precision)
                    } else {
                        $script:faker.Finance.$RandomizerSubType()
                    }
                }
                'hacker' {
                    $script:faker.Hacker.$RandomizerSubType()
                }
                'image' {
                    $script:faker.Image.$RandomizerSubType()
                }
                'internet' {
                    if ($randSubType -eq 'password') {
                        $script:faker.Internet.Password($Max)
                    } elseif ($randSubType -eq 'mac') {
                        if ($Separator) {
                            $script:faker.Internet.Mac($Separator)
                        } else {
                            if (-not $Format -or $Format -eq "##:##:##:##:##:##") {
                                $script:faker.Internet.Mac()
                            } elseif ($Format -eq "############") {
                                $script:faker.Internet.Mac("")
                            } else {
                                $newMacArray = $Format.ToCharArray()

                                $macAddress = $script:faker.Internet.Mac("")
                                $macArray = $macAddress.ToCharArray()

                                $macIndex = 0
                                for ($i = 0; $i -lt $formatArray.Count; $i++) {
                                    if ($newMacArray[$i] -eq "#") {
                                        $newMacArray[$i] = $macArray[$macIndex]
                                        $macIndex++
                                    }
                                }

                                $newMacArray -join ""
                            }
                        }
                    } else {
                        $script:faker.Internet.$RandomizerSubType()
                    }
                }
                'lorem' {
                    if ($randSubType -eq 'paragraph') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $script:faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $script:faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentences($Min, $Max)

                    } elseif ($randSubType -eq 'slug') {
                        $script:faker.Lorem.Slug($Max)
                    } elseif ($randSubType -eq 'words') {
                        $script:faker.Lorem.Words($Max)
                    } else {
                        $script:faker.Lorem.$RandomizerSubType()
                    }
                }
                'name' {
                    $script:faker.Name.$RandomizerSubType()
                }
                'person' {
                    if ($randSubType -eq "phone") {
                        if ($Format) {
                            $script:faker.Phone.PhoneNumber($Format)
                        } else {
                            $script:faker.Phone.PhoneNumber()
                        }
                    } else {
                        $script:faker.Person.$RandomizerSubType
                    }
                }
                'phone' {
                    if ($Format) {
                        $script:faker.Phone.PhoneNumber($Format)
                    } else {
                        $script:faker.Phone.PhoneNumber()
                    }
                }
                'random' {
                    if ($randSubType -in 'byte', 'char', 'decimal', 'double', 'even', 'float', 'int', 'long', 'number', 'odd', 'sbyte', 'short', 'uint', 'ulong', 'ushort') {
                        $script:faker.Random.$RandomizerSubType($Min, $Max)
                    } elseif ($randSubType -eq 'bytes') {
                        $script:faker.Random.Bytes($Max)
                    } elseif ($randSubType -in 'string', 'string2') {
                        $script:faker.Random.String2([int]$Min, [int]$Max, $CharacterString)
                    } elseif ($randSubType -eq 'shuffle') {
                        $commaIndex = $value.IndexOf(",")
                        $dotIndex = $value.IndexOf(".")

                        $Value = (($Value -replace ',', '') -replace '\.', '')

                        $newValue = ($script:faker.Random.Shuffle($Value) -join '')

                        if ($commaIndex -ne -1) {
                            $newValue = $newValue.Insert($commaIndex, ',')
                        }

                        if ($dotIndex -ne -1) {
                            $newValue = $newValue.Insert($dotIndex, '.')
                        }

                        $newValue
                    } else {
                        $script:faker.Random.$RandomizerSubType()
                    }
                }
                'rant' {
                    if ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Review($script:faker.Commerce.Product())
                    } elseif ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Reviews($script:faker.Commerce.Product(), $Max)
                    }
                }
                'system' {
                    $script:faker.System.$RandomizerSubType()
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBaWLVymE5vggGic8VP9JQlxK
# 4d6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFP9oOX+606EgFCmBz2x4b2szU4K7MA0GCSqGSIb3DQEBAQUABIIBAKhuDx6F
# 9jJlvXMsECw76RdkfxYf1bnRVSeyZxALm46w34UATlOiU9z0Zis9pQVvs+3MTTGi
# AALRu0f5VZLXstLUrsfMd0DCaqs4ujRIGN/DAgvJ5z+Pnz8viUmCGEYnTSeDdJOx
# EzLdBhC9hEb9/khXfL1jmF/mVJTvDQPn8kVuCtmq/qBg3RiibKeuG3zXPj080DAr
# sn+49plqs3ugPg97SMFNofvuEaaLBGUxXCggr7ttyYvM6HoZuFQ/CuoBIzGIeB5x
# nWmnaEJhqPchRav3136Iv96TEDD9oiA6VqNT74qTxTp2aO17GiquVkuSiuO0vUli
# YKNYGsoepiJKrjuhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk0MVowLwYJKoZIhvcNAQkEMSIEINMRyMJ2X01Y5s69VymMLHSKn186
# miuR5K91zXjcKmJbMA0GCSqGSIb3DQEBAQUABIIBAKgWFrxIEQz4OVdwrL/sifKn
# +LxCLOihDs+g1mxYcQwO+x2ZvI/I20tAmQisGer9ng73QrvyPqyT7mGev5UR2Uib
# LIPE9ax3Pmhg++0JbylHiyHUxL/h0fQZC97/vmR08v2i4gTkdwXxII8ix1gD3ZJE
# HALdkInaMDgKRmjj1D0NnHQBHzEzpdjWB/2gsqCA/6/IAGSV7TuuMyvizSxn733I
# ewWpBkscVtQRZ9ZPSyKAgqPRPJp2LScs6UjkXtHwe7XM3ZhHC6xFnfY/VfYNoKYG
# PPJfbwqyzdXmkJPoOEj9ewzWY7HWJ/vZlXTGDpD3AjMf2qZD5qtPYoHHEEtq1+s=
# SIG # End signature block
