function Export-DbaDacPackage {
    <#
    .SYNOPSIS
        Exports a dacpac from a server.

    .DESCRIPTION
        Using SQLPackage, export a dacpac from an instance of SQL Server.

        Note - Extract from SQL Server is notoriously flaky - for example if you have three part references to external databases it will not work.

        For help with the extract action parameters and properties, refer to https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllUserDatabases
        Run command against all user databases

    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.

    .PARAMETER Table
        List of the tables to include into the export. Should be provided as an array of strings: dbo.Table1, Table2, Schema1.Table3.

    .PARAMETER DacOption
        Export options for a corresponding export type. Can be created by New-DbaDacOption -Type Dacpac | Bacpac

    .PARAMETER ExtendedParameters
        Optional parameters used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER ExtendedProperties
        Optional properties used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Database, Dacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDacPackage

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config -FilePath C:\SharePoint_Config.dacpac

        Exports the dacpac for SharePoint_Config on sql2016 to C:\SharePoint_Config.dacpac

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for DB1 on sql2016 to C:\Users\username\Documents\DbatoolsExport\sql2016-DB1-20201227140759-dacpackage.dacpac including all table data. As noted the generated filename will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -AllUserDatabases -ExcludeDatabase "DBMaintenance","DBMonitoring" -Path "C:\temp"
        Exports dacpac packages for all USER databases, excluding "DBMaintenance" & "DBMonitoring", on sql2016 and saves them to C:\temp. The generated filename(s) will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.

    .EXAMPLE
        PS C:\> $moreparams = "/OverwriteFiles:$true /Quiet:$true"
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config -Path C:\temp -ExtendedParameters $moreparams

        Using extended parameters to over-write the files and performs the extraction in quiet mode to C:\temp\sql2016-SharePoint_Config-20201227140759-dacpackage.dacpac. Uses command line instead of SMO behind the scenes. As noted the generated filename will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.
    #>
    [CmdletBinding(DefaultParameterSetName = 'SMO')]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [parameter(ParameterSetName = 'SMO')]
        [Alias('ExtractOptions', 'ExportOptions', 'DacExtractOptions', 'DacExportOptions', 'Options', 'Option')]
        [object]$DacOption,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedParameters,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedProperties,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [parameter(ParameterSetName = 'SMO')]
        [string[]]$Table,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        if ($IsMacOS) {
            Stop-Function -Message "OS X not supported. Please use Linux or Windows."
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName ExcludeDatabase) -and (Test-Bound -Not -ParameterName AllUserDatabases)) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        if (-not $script:core) {
            $dacfxPath = Resolve-Path -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"

            if ((Test-Path $dacfxPath) -eq $false) {
                Stop-Function -Message 'Dac Fx library not found.' -EnableException $EnableException
                return
            } else {
                try {
                    Add-Type -Path $dacfxPath
                    Write-Message -Level Verbose -Message "Dac Fx loaded."
                } catch {
                    Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
                    return
                }
            }
        }

        #check that at least one of the DB selection parameters was specified
        if (!$AllUserDatabases -and !$Database) {
            Stop-Function -Message "Either -Database or -AllUserDatabases should be specified" -Continue
        }
        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExtractOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExtractOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        }

        #Create a tuple to be used as a table filter
        if ($Table) {
            $tblList = New-Object 'System.Collections.Generic.List[Tuple[String, String]]'
            foreach ($tableItem in $Table) {
                $tableSplit = $tableItem.Split('.')
                if ($tableSplit.Count -gt 1) {
                    $tblName = $tableSplit[-1]
                    $schemaName = $tableSplit[-2]
                } else {
                    $tblName = [string]$tableSplit
                    $schemaName = 'dbo'
                }
                $tblList.Add((New-Object "tuple[String, String]" -ArgumentList $schemaName, $tblName))
            }
        } else {
            $tblList = $null
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Database) {
                $dbs = Get-DbaDatabase -SqlInstance $server -OnlyAccessible -Database $Database -ExcludeDatabase $ExcludeDatabase
            } else {
                # all user databases by default
                $dbs = Get-DbaDatabase -SqlInstance $server -OnlyAccessible -ExcludeSystem -ExcludeDatabase $ExcludeDatabase
            }
            if (-not $dbs) {
                Stop-Function -Message "Databases not found on $instance"-Target $instance -Continue
            }

            foreach ($db in $dbs) {
                $resultstime = [diagnostics.stopwatch]::StartNew()
                $dbName = $db.name
                $connstring = $server.ConnectionContext.ConnectionString | Convert-ConnectionString
                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbName"
                }

                Write-Message -Level Verbose -Message "Using connection string $connstring"

                if ($Type -eq 'Dacpac') {
                    $ext = 'dacpac'
                } elseif ($Type -eq 'Bacpac') {
                    $ext = 'bacpac'
                }

                $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type $ext -ServerName $instance -DatabaseName $dbName

                #using SMO by default
                if ($PsCmdlet.ParameterSetName -eq 'SMO') {
                    try {
                        $dacSvc = New-Object -TypeName Microsoft.SqlServer.Dac.DacServices -ArgumentList $connstring -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Could not connect to the connection string $connstring"-Target $instance -Continue
                    }
                    if (-not $DacOption) {
                        $opts = New-DbaDacOption -Type $Type -Action Export
                    } else {
                        $opts = $DacOption
                    }

                    $null = $output = Register-ObjectEvent -InputObject $dacSvc -EventName "Message" -SourceIdentifier "msg" -Action { $EventArgs.Message.Message }

                    if ($Type -eq 'Dacpac') {
                        Write-Message -Level Verbose -Message "Initiating Dacpac extract to $FilePath"
                        #not sure how to extract that info from the existing DAC application, leaving 1.0.0.0 for now
                        $version = New-Object System.Version -ArgumentList '1.0.0.0'
                        try {
                            $dacSvc.Extract($FilePath, $dbName, $dbName, $version, $null, $tblList, $opts, $null)
                        } catch {
                            Stop-Function -Message "DacServices extraction failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        Write-Message -Level Verbose -Message "Initiating Bacpac export to $FilePath"
                        try {
                            $dacSvc.ExportBacpac($FilePath, $dbName, $opts, $tblList, $null)
                        } catch {
                            Stop-Function -Message "DacServices export failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    }
                    $finalResult = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                } elseif ($PsCmdlet.ParameterSetName -eq 'CMD') {
                    if ($Type -eq 'Dacpac') { $action = 'Extract' }
                    elseif ($Type -eq 'Bacpac') { $action = 'Export' }
                    $cmdConnString = $connstring.Replace('"', "'")

                    $sqlPackageArgs = "/action:$action /tf:""$FilePath"" /SourceConnectionString:""$cmdConnString"" $ExtendedParameters $ExtendedProperties"

                    try {
                        $startprocess = New-Object System.Diagnostics.ProcessStartInfo
                        if ($IsLinux) {
                            $startprocess.FileName = "$script:PSModuleRoot/bin/smo/coreclr/sqlpackage"
                        } else {
                            $startprocess.FileName = "$script:PSModuleRoot\bin\smo\sqlpackage.exe"
                        }
                        $startprocess.Arguments = $sqlPackageArgs
                        $startprocess.RedirectStandardError = $true
                        $startprocess.RedirectStandardOutput = $true
                        $startprocess.UseShellExecute = $false
                        $startprocess.CreateNoWindow = $true
                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo = $startprocess
                        $process.Start() | Out-Null
                        $stdout = $process.StandardOutput.ReadToEnd()
                        $stderr = $process.StandardError.ReadToEnd()
                        $process.WaitForExit()
                        Write-Message -level Verbose -Message "StandardOutput: $stdout"
                        $finalResult = $stdout
                    } catch {
                        Stop-Function -Message "SQLPackage Failure" -ErrorRecord $_ -Continue
                    }

                    if ($process.ExitCode -ne 0) {
                        Stop-Function -Message "Standard output - $stderr"-Continue
                    }
                }
                [pscustomobject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $dbName
                    Path         = $FilePath
                    Elapsed      = [prettytimespan]($resultstime.Elapsed)
                    Result       = $finalResult
                } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0PR6OhqEi2xZITfdsFILbnY3
# b0KgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFA0DyphwRpk17B86rfMawJ+9lPa4MA0GCSqGSIb3DQEBAQUABIIBAHuLNvoH
# ZD5DDiYVukN1FIh+AdhCk+paO95WQ+apMY9kgCXBpyFPHtDhr2yr1KqrR9HkOMHR
# HjHytHj9j3yJPpFXBzaFjiad5IrU3RlnX7RDi/4TxWZ9QMxYNX5GcZ0SjWQ2HrCV
# HJ0sAVNse0vDRPKX7WMBw3eXHOd42W9Czubm6oYQJeOfzRXvMEMDZb+J+SXnmpBx
# Ghk8bTNiJa4KmtWXyjeOudIFMMcBTjVaR7nhUDZbi1UFeaR3fIRPOtamLVaAAcF7
# peqi+XU2Pji1dplG+RE7tXK4XPA/s8p2p2E22gcnj2HrEuUrX9/zYbAWEv9ib0R/
# pIjA3nmVRTaLuWWhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwM1owLwYJKoZIhvcNAQkEMSIEIMosfm4mDYCSaVKmIbbPbo3CCaUm
# 2UMI9k5PKvlpBznOMA0GCSqGSIb3DQEBAQUABIIBAARuCBg3T6nodGxbRO1ltRjF
# C71bkG3FvO8n1/JL9J4KoQl15LskRy9MqqL562LDTDGgB0pvetDe3zGraIXQvCoE
# hX2dfuW5qf+RoR3pFctN0lR68bW9kqXd7vTT4p8qDWrD/tfcEKrnHrxE8mXcPxk8
# k8PHl3pOHXcA0D4S/ynDnM9y198ej2yiRtYPf1KNkJf6TOEOlqeQHoRzAYHl2DEn
# cZwC2uE6YGpJqNnOS6RZm14wmGUX3jx4uH48L+lPMg6oVMffbjpfQLXe+X1xy3gV
# HCa5gcNQfvOQff1CESeQc0jq7fUXCKLnzKOUhrKxXcb2KMLGanpAwRvvj2sEr/s=
# SIG # End signature block
