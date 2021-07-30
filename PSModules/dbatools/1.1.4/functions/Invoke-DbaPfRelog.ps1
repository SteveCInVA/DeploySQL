function Invoke-DbaPfRelog {
    <#
    .SYNOPSIS
        Pipeline-compatible wrapper for the relog command which is available on modern Windows platforms.

    .DESCRIPTION
        Pipeline-compatible wrapper for the relog command. Relog is useful for converting Windows Perfmon.

        Extracts performance counters from performance counter logs into other formats,
        such as text-TSV (for tab-delimited text), text-CSV (for comma-delimited text), binary-BIN, or SQL.

        `relog "C:\PerfLogs\Admin\System Correlation\WORKSTATIONX_20180112-000001\DataCollector01.blg" -o C:\temp\foo.csv -f tsv`

        If you find any input hangs, please send us the output so we can accommodate for it then use -Raw for an immediate solution.

    .PARAMETER Path
        Specifies the pathname of an existing performance counter log or performance counter path. You can specify multiple input files.

    .PARAMETER Destination
        Specifies the pathname of the output file or SQL database where the counters will be written. Defaults to the same directory as the source.

    .PARAMETER Type
        The output format. Defaults to tsv. Options include tsv, csv, bin, and sql.

        For a SQL database, the output file specifies the DSN!counter_log. You can specify the database location by using the ODBC manager to configure the DSN (Database System Name).

        For more information, read here: https://technet.microsoft.com/en-us/library/bb490958.aspx

    .PARAMETER Append
        If this switch is enabled, output will be appended to the specified file instead of overwriting. This option does not apply to SQL format where the default is always to append.

    .PARAMETER AllowClobber
        If this switch is enabled, the destination file will be overwritten if it exists.

    .PARAMETER PerformanceCounter
        Specifies the performance counter path to log.

    .PARAMETER PerformanceCounterPath
        Specifies the pathname of the text file that lists the performance counters to be included in a relog file. Use this option to list counter paths in an input file, one per line. Default setting is all counters in the original log file are relogged.

    .PARAMETER Interval
        Specifies sample intervals in "n" records. Includes every nth data point in the relog file. Default is every data point.

    .PARAMETER BeginTime
        This is is Get-Date object and we format it for you.

    .PARAMETER EndTime
        Specifies end time for copying last record from the input file. This is is Get-Date object and we format it for you.

    .PARAMETER ConfigPath
        Specifies the pathname of the settings file that contains command-line parameters.

    .PARAMETER Summary
        If this switch is enabled, the performance counters and time ranges of log files specified in the input file will be displayed.

    .PARAMETER Multithread
        If this switch is enabled, processing will be done in parallel. This may speed up large batches or large files.

    .PARAMETER AllTime
        If this switch is enabled and a datacollector or datacollectorset is passed in via the pipeline, collects all logs, not just the latest.

    .PARAMETER Raw
        If this switch is enabled, the results of the DOS command instead of Get-ChildItem will be displayed. This does not run in parallel.

    .PARAMETER InputObject
        Accepts the output of Get-DbaPfDataCollector and Get-DbaPfDataCollectorSet as input via the pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter, Relog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaPfRelog

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg

        Creates C:\temp\perfmon.tsv from C:\temp\perfmon.blg.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg.

        Returns the newly created file as a file object.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2016 | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Destination C:\temp\perf

        Creates C:\temp\perf if needed, then generates computername-datacollectorname.tsv (tab separated) from the latest logs of all data collector sets on sql2016. This destination format was chosen to avoid naming conflicts with piped input.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path C:\temp\perfmon.blg -Destination C:\temp\a\b\c -Raw
        ```
        [Invoke-DbaPfRelog][21:21:35] relog "C:\temp\perfmon.blg" -f csv -o C:\temp\a\b\c

        Input
        ----------------
        File(s):
        C:\temp\perfmon.blg (Binary)

        Begin:    1/13/2018 5:13:23
        End:      1/13/2018 14:29:55
        Samples:  2227

        100.00%

        Output
        ----------------
        File:     C:\temp\a\b\c.csv

        Begin:    1/13/2018 5:13:23
        End:      1/13/2018 14:29:55
        Samples:  2227

        The command completed successfully.
        ```

        Creates the temp, a, and b directories if needed, then generates c.tsv (tab separated) from C:\temp\perfmon.blg then outputs the raw results of the relog command.

    .EXAMPLE
        PS C:\> Invoke-DbaPfRelog -Path 'C:\temp\perflog with spaces.blg' -Destination C:\temp\a\b\c -Type csv -BeginTime ((Get-Date).AddDays(-30)) -EndTime ((Get-Date).AddDays(-1))

        Creates the temp, a, and b directories if needed, then generates c.csv (comma separated) from C:\temp\perflog with spaces.blg', starts 30 days ago and ends one day ago.

    .EXAMPLE
        PS C:\> $servers | Get-DbaPfDataCollectorSet | Get-DbaPfDataCollector | Invoke-DbaPfRelog -Multithread -AllowClobber

        Relogs latest data files from all collectors within the servers listed in $servers.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector -Collector DataCollector01 | Invoke-DbaPfRelog -AllowClobber -AllTime

        Relogs all the log files from the DataCollector01 on the local computer and allows overwrite.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string]$Destination,
        [ValidateSet("tsv", "csv", "bin", "sql")]
        [string]$Type = "tsv",
        [switch]$Append,
        [switch]$AllowClobber,
        [string[]]$PerformanceCounter,
        [string]$PerformanceCounterPath,
        [int]$Interval,
        [datetime]$BeginTime,
        [datetime]$EndTime,
        [string]$ConfigPath,
        [switch]$Summary,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$Multithread,
        [switch]$AllTime,
        [switch]$Raw,
        [switch]$EnableException
    )
    begin {


        if (Test-Bound -ParameterName BeginTime) {
            $script:beginstring = ($BeginTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }
        if (Test-Bound -ParameterName EndTime) {
            $script:endstring = ($EndTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
        }

        $allpaths = @()
        $allpaths += $Path

        # to support multithreading
        if (Test-Bound -ParameterName Destination) {
            $script:destinationset = $true
            $originaldestination = $Destination
        } else {
            $script:destinationset = $false
        }
    }
    process {
        if ($Append -and $Type -ne "bin") {
            Stop-Function -Message "Append can only be used with -Type bin." -Target $Path
            return
        }

        if ($InputObject) {
            foreach ($object in $InputObject) {
                # DataCollectorSet
                if ($object.OutputLocation -and $object.RemoteOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.OutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }


                    $script:perfmonobject = $true
                }
                # DataCollector
                if ($object.LatestOutputLocation -and $object.RemoteLatestOutputLocation) {
                    $instance = [dbainstance]$object.ComputerName

                    if (-not $AllTime) {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    } else {
                        if ($instance.IsLocalHost) {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.LatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        } else {
                            $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.RemoteLatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                        }
                    }
                    $script:perfmonobject = $true
                }
            }
        }
    }

    # Gotta collect all the paths first then process them otherwise there may be duplicates
    end {
        $allpaths = $allpaths | Where-Object { $_ -match '.blg' } | Select-Object -Unique

        if (-not $allpaths) {
            Stop-Function -Message "Could not find matching .blg files" -Target $file -Continue
            return
        }

        $scriptBlock = {
            if ($args) {
                $file = $args
            } else {
                $file = $psitem
            }
            $item = Get-ChildItem -Path $file -ErrorAction SilentlyContinue

            if ($null -eq $item) {
                Stop-Function -Message "$file does not exist." -Target $file -Continue
                return
            }

            if (-not $script:destinationset -and $file -match "C\:\\.*Admin.*") {
                $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
            }

            if ($script:destinationset -eq $false -and -not $Append) {
                $Destination = Join-Path (Split-Path $file) $item.BaseName
            }

            if ($Destination -and $Destination -notmatch "\." -and -not $Append -and $script:perfmonobject) {
                # if destination is set, then it needs a different name
                if ($script:destinationset -eq $true) {
                    if ($file -match "\:") {
                        $computer = $env:COMPUTERNAME
                    } else {
                        $computer = $file.Split("\")[2]
                    }
                    # Avoid naming conflicts
                    $timestamp = Get-Date -format yyyyMMddHHmmfff
                    $Destination = Join-Path $originaldestination "$computer - $($item.BaseName) - $timestamp"
                }
            }

            $params = @("`"$file`"")

            if ($Append) {
                $params += "-a"
            }

            if ($PerformanceCounter) {
                $parsedcounters = $PerformanceCounter -join " "
                $params += "-c `"$parsedcounters`""
            }

            if ($PerformanceCounterPath) {
                $params += "-cf `"$PerformanceCounterPath`""
            }

            $params += "-f $Type"

            if ($Interval) {
                $params += "-t $Interval"
            }

            if ($Destination) {
                $params += "-o `"$Destination`""
            }

            if ($script:beginstring) {
                $params += "-b $script:beginstring"
            }

            if ($script:endstring) {
                $params += "-e $script:endstring"
            }

            if ($ConfigPath) {
                $params += "-config $ConfigPath"
            }

            if ($Summary) {
                $params += "-q"
            }


            if (-not ($Destination.StartsWith("DSN"))) {
                $outputisfile = $true
            } else {
                $outputisfile = $false
            }

            if ($outputisfile) {
                if ($Destination) {
                    $dir = Split-Path $Destination
                    if (-not (Test-Path -Path $dir)) {
                        try {
                            $null = New-Item -ItemType Directory -Path $dir -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination -Continue
                        }
                    }

                    if ((Test-Path $Destination) -and -not $Append -and ((Get-Item $Destination) -isnot [System.IO.DirectoryInfo])) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }

                    if ((Test-Path "$Destination.$type") -and -not $Append) {
                        if ($AllowClobber) {
                            try {
                                Remove-Item -Path "$Destination.$type" -ErrorAction Stop
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }
                        } else {
                            if ($Type -eq "bin") {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite or -Append to append." -Continue
                            } else {
                                Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite." -Continue
                            }
                        }
                    }
                }
            }

            $arguments = ($params -join " ")

            try {
                if ($Raw) {
                    Write-Message -Level Output -Message "relog $arguments"
                    cmd /c "relog $arguments"
                } else {
                    Write-Message -Level Verbose -Message "relog $arguments"
                    $scriptBlock = {
                        $output = (cmd /c "relog $arguments" | Out-String).Trim()

                        if ($output -notmatch "Success") {
                            Stop-Function -Continue -Message $output.Trim("Input")
                        } else {
                            Write-Message -Level Verbose -Message "$output"
                            $array = $output -Split [environment]::NewLine
                            $files = $array | Select-String "File:"

                            foreach ($rawfile in $files) {
                                $rawfile = $rawfile.ToString().Replace("File:", "").Trim()
                                $gcierror = $null
                                Get-ChildItem $rawfile -ErrorAction SilentlyContinue -ErrorVariable gcierror | Add-Member -MemberType NoteProperty -Name RelogFile -Value $true -PassThru -ErrorAction Ignore
                                if ($gcierror) {
                                    Write-Message -Level Verbose -Message "$gcierror"
                                }
                            }
                        }
                    }
                    Invoke-Command -ScriptBlock $scriptBlock
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
            }
        }

        if ($Multithread) {
            $allpaths | Invoke-Parallel -ImportVariables -ImportModules -ScriptBlock $scriptBlock -ErrorAction SilentlyContinue -ErrorVariable parallelerror
            if ($parallelerror) {
                Write-Message -Level Verbose -Message "$parallelerror"
            }
        } else {
            foreach ($file in $allpaths) { Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $file }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6aQT281m8YwSnnU5eOah5T4K
# gv6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFB7uiTu2/8TbYTd2Za/29wJzaOd/MA0GCSqGSIb3DQEBAQUABIIBAFEQHnwC
# 143GhdrrjuRvJu5wMO+/3LdXWaqhjuoZKbvWjFnPzTFoKbraulJZYRf+Kq8ti+P0
# HgXzb3d+PKY44A7t/2swlZBKW0JdfTM9ty26wT1Lc2i1niUXCNzdl7qMHKUtzq63
# N0pYYFyXTsEuq9r6bD2MixdE6BIFCdt1zj0hrZo+ahGSO5TlD3BTvUEhCXdYIPcb
# kwGBgqKHlhiXg1b9k08B0AOmBTEHjyu4HPlj6A79E0y3jtLNFgq3qh9vE5Q0H+I1
# MI/jLOo6IqwvXl4gK5VS+M18nxK6VIa4+lS2TnBeZ90i1bDuRbehMuLpKDHlQLFg
# 1XZLL+dt03Tc7/KhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MVowLwYJKoZIhvcNAQkEMSIEIDv4e2A/Z1PBBgORkgb+aYsrZbEu
# bYSd6ofY8ra4iysVMA0GCSqGSIb3DQEBAQUABIIBAHS9oHVADr1HBNh7wdLYO7nt
# Oa3OXYmzE/1QLh5FxI8HIdOxiM02BLALCHFdmLKM7K28LFet2Dp8JXpZJ9a/75/I
# ZC2dQ5FAheYujDS6mRS8nfJnpDm8EF+3CDvk8sYkWjmkCRD43cHniel1PCoTvux+
# giJzNeWGFDAWx3J2SqqQ7SDbIaiEv552VcLmDkF24VrU+k5/nKKyI11q3oUZeU7R
# wLKvayzRKCQUDpJ4hWD4OYTG46afnj220S4+K0f0tYtnVvxwfp6htQrKudsAqW9j
# UB7Xnc+3dmOx7Gbak7gTtXOxbGAlgLyWjIXuBlJvWvqLp7RRmyq5pdk115Wq7SU=
# SIG # End signature block
