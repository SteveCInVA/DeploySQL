function Test-DbaDiskAlignment {
    <#
    .SYNOPSIS
        Verifies that your non-dynamic disks are aligned according to physical constraints.

    .DESCRIPTION
        Verifies that your non-dynamic disks are aligned according to physical constraints.

        Returns one row per computer, partition and stripe size with.

        Please refer to your storage vendor best practices before following any advice below.

        By default issues with disk alignment should be resolved by a new installation of Windows Server 2008, Windows Vista, or later operating systems, but verifying disk alignment continues to be recommended as a best practice.
        While some versions of Windows use different starting alignments, if you are starting anew 1MB is generally the best practice offset for current operating systems (because it ensures that the partition offset % common stripe unit sizes == 0 )

        Caveats:
        * Dynamic drives (or those provisioned via third party software) may or may not have accurate results when polled by any of the built in tools, see your vendor for details.
        * Windows does not have a reliable way to determine stripe unit Sizes. These values are obtained from vendor disk management software or from your SAN administrator.
        * System drives in versions previous to Windows Server 2008 cannot be aligned, but it is generally not recommended to place SQL Server databases on system drives.

    .PARAMETER ComputerName
        The target computer or computers.

    .PARAMETER Credential
        Specifies an alternate Windows account to use when enumerating drives on the server. May require Administrator privileges. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER SQLCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoSqlCheck
        If this switch is enabled, the disk(s) will not be checked for SQL Server data or log files.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage
        Author: Constantine Kokkinos (@mobileck), https://constantinekokkinos.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        The preferred way to determine if your disks are aligned (or not) is to calculate:
        1. Partition offset - stripe unit size
        2. Stripe unit size - File allocation unit size

        References:
        - Disk Partition Alignment Best Practices for SQL Server - https://technet.microsoft.com/en-us/library/dd758814(v=sql.100).aspx
        - Getting Partition Offset information with Powershell - http://sqlblog.com/blogs/jonathan_kehayias/archive/2010/03/01/getting-partition-Offset-information-with-powershell.aspx
        Thanks to Jonathan Kehayias!
        - Decree: Set your partition Offset and block Size and make SQL Server faster - http://www.midnightdba.com/Jen/2014/04/decree-set-your-partition-Offset-and-block-Size-make-sql-server-faster/
        Thanks to Jen McCown!
        - Disk Performance Hands On - http://www.kendalvandyke.com/2009/02/disk-performance-hands-on-series-recap.html
        Thanks to Kendal Van Dyke!
        - Get WMI Disk Information - http://powershell.com/cs/media/p/7937.aspx
        Thanks to jbruns2010!

    .LINK
        https://dbatools.io/Test-DbaDiskAlignment

    .EXAMPLE
        PS C:\> Test-DbaDiskAlignment -ComputerName sqlserver2014a

        Tests the disk alignment of a single server named sqlserver2014a

    .EXAMPLE
        PS C:\> Test-DbaDiskAlignment -ComputerName sqlserver2014a, sqlserver2014b, sqlserver2014c

        Tests the disk alignment of multiple servers

    #>
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$NoSqlCheck,
        [switch]$EnableException
    )
    begin {
        $sessionoption = New-CimSessionOption -Protocol DCom

        function Get-DiskAlignment {
            [CmdletBinding()]
            param (
                $CimSession,
                [string]$FunctionName = (Get-PSCallStack)[0].Command,
                [bool]$NoSqlCheck,
                [string]$ComputerName,
                [System.Management.Automation.PSCredential]$SqlCredential,
                [bool]$EnableException = $EnableException
            )

            $SqlInstances = @()
            $offsets = @()

            #region Retrieving partition/disk Information
            try {
                Write-Message -Level Verbose -Message "Gathering information about first partition on each disk for $ComputerName." -FunctionName $FunctionName

                try {
                    $partitions = Get-CimInstance -CimSession $CimSession -ClassName Win32_DiskPartition -Namespace "root\cimv2" -ErrorAction Stop
                } catch {
                    if ($_.Exception -match "namespace") {
                        Stop-Function -Message "Can't get disk alignment info for $ComputerName. Unsupported operating system." -InnerErrorRecord $_ -Target $ComputerName -FunctionName $FunctionName
                        return
                    } else {
                        Stop-Function -Message "Can't get disk alignment info for $ComputerName. Check logs for more details." -InnerErrorRecord $_ -Target $ComputerName -FunctionName $FunctionName
                        return
                    }
                }


                $disks = @()
                foreach ($partition in $partitions) {
                    $associators = Get-CimInstance -CimSession $CimSession -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=""$($partition.DeviceID.Replace("\", "\\"))""} WHERE AssocClass = Win32_LogicalDiskToPartition"
                    foreach ($assoc in $associators) {
                        $disks += [PSCustomObject]@{
                            BlockSize      = $partition.BlockSize
                            BootPartition  = $partition.BootPartition
                            Description    = $partition.Description
                            DiskIndex      = $partition.DiskIndex
                            Index          = $partition.Index
                            NumberOfBlocks = $partition.NumberOfBlocks
                            StartingOffset = $partition.StartingOffset
                            Type           = $partition.Type
                            Name           = $assoc.Name
                            Size           = $partition.Size
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Gathered CIM information." -FunctionName $FunctionName
            } catch {
                Stop-Function -Message "Can't connect to CIM on $ComputerName." -FunctionName $FunctionName -InnerErrorRecord $_
                return
            }
            #endregion Retrieving partition Information

            #region Retrieving Instances
            if (-not $NoSqlCheck) {
                Write-Message -Level Verbose -Message "Checking for SQL Services." -FunctionName $FunctionName
                $sqlservices = Get-CimInstance -ClassName Win32_Service -CimSession $CimSession | Where-Object DisplayName -like 'SQL Server (*'
                foreach ($service in $sqlservices) {
                    $instance = $service.DisplayName.Replace('SQL Server (', '')
                    $instance = $instance.TrimEnd(')')

                    $instanceName = $instance.Replace("MSSQLSERVER", "Default")
                    Write-Message -Level Verbose -Message "Found instance $instanceName" -FunctionName $FunctionName
                    if ($instance -eq 'MSSQLSERVER') {
                        $SqlInstances += $ComputerName
                    } else {
                        $SqlInstances += "$ComputerName\$instance"
                    }
                }
                $sqlcount = $SqlInstances.Count
                Write-Message -Level Verbose -Message "$sqlcount instance(s) found." -FunctionName $FunctionName
            }
            #endregion Retrieving Instances

            #region Offsets
            foreach ($disk in $disks) {
                if (!$disk.name.StartsWith("\\")) {
                    $diskname = $disk.Name
                    if ($NoSqlCheck -eq $false) {
                        $sqldisk = $false

                        foreach ($SqlInstance in $SqlInstances) {
                            try {
                                if ($null -ne $SqlCredential) {
                                    $smoserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
                                } else {
                                    $smoserver = Connect-SqlInstance -SqlInstance $SqlInstance # win auth
                                }
                                $sql = "Select count(*) as Count from sys.master_files where physical_name like '$diskname%'"
                                Write-Message -Level Verbose -Message "Query is: $sql" -FunctionName $FunctionName
                                Write-Message -Level Verbose -Message "SQL Server is: $SqlInstance." -FunctionName $FunctionName
                                $sqlcount = $smoserver.Databases['master'].ExecuteWithResults($sql).Tables[0].Count
                                if ($sqlcount -gt 0) {
                                    $sqldisk = $true
                                    break
                                }
                            } catch {
                                Stop-Function -Message "Can't connect to $ComputerName ($SqlInstance)." -FunctionName $FunctionName -InnerErrorRecord $_
                                return
                            }
                        }
                    }

                    if ($NoSqlCheck -eq $false) {
                        if ($sqldisk -eq $true) {
                            $offsets += $disk
                        }
                    } else {
                        $offsets += $disk
                    }
                }
            }
            #endregion Offsets

            #region Processing results
            Write-Message -Level Verbose -Message "Checking $($offsets.count) partitions." -FunctionName $FunctionName
            foreach ($partition in $offsets) {
                # Unfortunately "Windows does not have a reliable way to determine stripe unit Sizes. These values are obtained from vendor disk management software or from your SAN administrator."
                # And this is the #1 most impactful issue with disk alignment :D
                # What we can do is test common stripe unit Sizes against the Offset we have and give advice if the Offset they chose would work in those scenarios
                $offset = $partition.StartingOffset / 1kb
                $type = $partition.Type
                $stripe_units = @(64, 128, 256, 512, 1024) # still wish I had a better way to verify this or someone to pat my back and say its alright.

                # testing dynamic disks, everyone states that info from dynamic disks is not to be trusted, so throw a warning.
                Write-Message -Level Verbose -Message "Testing for dynamic disks." -FunctionName $FunctionName
                if ($type -eq "Logical Disk Manager") {
                    $IsDynamicDisk = $true
                    Write-Message -Level Warning -Message "Disk is dynamic, all Offset calculations should be suspect, please refer to your vendor to determine actual Offset calculations." -FunctionName $FunctionName
                } else {
                    $IsDynamicDisk = $false
                }

                Write-Message -Level Verbose -Message "Checking for best practices offsets." -FunctionName $FunctionName

                if ($offset -ne 64 -and $offset -ne 128 -and $offset -ne 256 -and $offset -ne 512 -and $offset -ne 1024) {
                    $IsOffsetBestPractice = $false
                } else {
                    $IsOffsetBestPractice = $true
                }

                # as we can't tell the actual size of the file strip unit, just check all the sizes I know about
                foreach ($size in $stripe_units) {
                    if ($offset % $size -eq 0) {
                        # for proper alignment we really only need to know that your offset divided by your stripe unit size has a remainder of 0
                        $OffsetModuloKB = "$($offset % $size)"
                        $isBestPractice = $true
                    } else {
                        $OffsetModuloKB = "$($offset % $size)"
                        $isBestPractice = $false
                    }

                    [PSCustomObject]@{
                        ComputerName            = $ogcomputer
                        Name                    = "$($partition.Name)"
                        PartitionSize           = [dbasize]($($partition.Size / 1MB) * 1024 * 1024)
                        PartitionType           = $partition.Type
                        TestingStripeSize       = [dbasize]($size * 1024)
                        OffsetModuluCalculation = [dbasize]($OffsetModuloKB * 1024)
                        StartingOffset          = [dbasize]($offset * 1024)
                        IsOffsetBestPractice    = $IsOffsetBestPractice
                        IsBestPractice          = $isBestPractice
                        NumberOfBlocks          = $partition.NumberOfBlocks
                        BootPartition           = $partition.BootPartition
                        PartitionBlockSize      = $partition.BlockSize
                        IsDynamicDisk           = $IsDynamicDisk
                    }
                }
            }
        }
    }

    process {
        # uses cim commands


        foreach ($computer in $ComputerName) {
            $computer = $ogcomputer = $computer.ComputerName
            Write-Message -Level VeryVerbose -Message "Processing: $computer."

            $computer = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
            $Computer = $computer.FullComputerName

            if (-not $Computer) {
                Stop-Function -Message "Couldn't resolve hostname. Skipping." -Continue
            }

            #region Connecting to server via Cim
            Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan"

            if (-not $Credential) {
                $cimsession = New-CimSession -ComputerName $Computer -ErrorAction Ignore
            } else {
                $cimsession = New-CimSession -ComputerName $Computer -ErrorAction Ignore -Credential $Credential
            }

            if ($null -eq $cimsession.id) {
                Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan failed. Creating CimSession on $computer over DCOM."

                if (!$Credential) {
                    $cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction Ignore
                } else {
                    $cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction Ignore -Credential $Credential
                }
            }

            if ($null -eq $cimsession.id) {
                Stop-Function -Message "Can't create CimSession on $computer." -Target $Computer -Continue
            }
            #endregion Connecting to server via Cim

            Write-Message -Level Verbose -Message "Getting Disk Alignment information from $Computer."


            try {
                Get-DiskAlignment -CimSession $cimsession -NoSqlCheck $NoSqlCheck -ComputerName $Computer -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failed to process $($Computer): $($_.Exception.Message)" -Continue -InnerErrorRecord $_ -Target $Computer
            }
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUXjTQf2anf//6pjG38cWSlKin
# 2mKgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFADsGlxDWyITlxbYn696mTN6QxonMA0GCSqGSIb3DQEBAQUABIIBAG/V8U8a
# PS1OvGGxVJhn81zmXZmkhiaLOYtnsP1f0LK8oHWkPXzLc7n6msvSn1gXZb9U1ch7
# ftzLANsIeGszTidqWw9CiRcu+9qMDvWD9HbvwyJ3yup8E6aKUUUR51lnl3eT6rRi
# ZZRbf//b83ER2hmy+KdEIZGH00fBfkrkgtYDQCuv7/1pQO7kHBLKFjMLo8vJMcYy
# 7NWMWzrPB5cQ4eAOibORuF/BK6gMQTr7L2zGHLPcCThWF5+5VbSRrpo1s2zr0KaJ
# zPZ8y2nbGKlxulKkZT1SknUD7lPWbb38y+dmR1OLH+1lRCX6lf4tqyBZ5rFKBUu4
# lO7jR7DCCG58cB2hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYwMVowLwYJKoZIhvcNAQkEMSIEIPbWH7IQYrrl1xzbwtWzeC8gYRF9
# 87WwYYoMb6cAy2iFMA0GCSqGSIb3DQEBAQUABIIBACu3JSdAgMYRzt706U3cmMdl
# sK30TIp6SqrcoVbAzUEfR9xu0AhVS7ipRWbJmK3HIcogdJ0W/YtQjbD61CCqpdY9
# rKAW7i6I92QH7lm3rArdJIQVkdzw6T3MquWZ0URCxXobtyGlBAJITL4XWrnszi6Z
# P/wl22Xd2mjAw24iLnXJAByWCUPpg6JvPLOih7MnOav3oNYJ/h7x8mUJeMEtw2Sw
# XLQgUcyX/8DKOw3U0G+pJnlvNKkSos3IEC9XnnZvgNKYN5X+xtQ1RAhmdyaEYWm7
# 0n+WFIC2vjxE8Jp2ymSPlBSqWLQmmoOH8C8mJ90A/t1rs/WYFEGK1aEAlg3LNR8=
# SIG # End signature block
