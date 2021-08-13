function Import-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Imports a new Performance Monitor Data Collector Set Template either from the dbatools repository or a file you specify.

    .DESCRIPTION
        Imports a new Performance Monitor Data Collector Set Template either from the dbatools repository or a file you specify.
        When importing data collector sets from the local instance, Run As Admin is required.

        Note: The included counters will be added for all SQL instances on the machine by default.
        For specific instances in addition to the default, use -Instance.

        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371952 for more information

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Path
        The path to the xml file or files.

    .PARAMETER Template
        From one or more of the templates from the dbatools repository. Press Tab to cycle through the available options.

    .PARAMETER RootPath
        Sets the base path where the subdirectories are created.

    .PARAMETER DisplayName
        Sets the display name of the data collector set.

    .PARAMETER SchedulesEnabled
        If this switch is enabled, sets a value that indicates whether the schedules are enabled.

    .PARAMETER Segment
        Sets a value that indicates whether PLA creates new logs if the maximum size or segment duration is reached before the data collector set is stopped.

    .PARAMETER SegmentMaxDuration
        Sets the duration that the data collector set can run before it begins writing to new log files.

    .PARAMETER SegmentMaxSize
        Sets the maximum size of any log file in the data collector set.

    .PARAMETER Subdirectory
        Sets a base subdirectory of the root path where the next instance of the data collector set will write its logs.

    .PARAMETER SubdirectoryFormat
        Sets flags that describe how to decorate the subdirectory name. PLA appends the decoration to the folder name. For example, if you specify plaMonthDayHour, PLA appends the current month, day, and hour values to the folder name. If the folder name is MyFile, the result could be MyFile110816.

    .PARAMETER SubdirectoryFormatPattern
        Sets a format pattern to use when decorating the folder name. Default is 'yyyyMMdd\-NNNNNN'.

    .PARAMETER Task
        Sets the name of a Task Scheduler job to start each time the data collector set stops, including between segments.

    .PARAMETER TaskRunAsSelf
        If this switch is enabled, sets a value that determines whether the task runs as the data collector set user or as the user specified in the task.

    .PARAMETER TaskArguments
        Sets the command-line arguments to pass to the Task Scheduler job specified in the IDataCollectorSet::Task property.
        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371992 for more information.

    .PARAMETER TaskUserTextArguments
        Sets the command-line arguments that are substituted for the {usertext} substitution variable in the IDataCollectorSet::TaskArguments property.
        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371993 for more information.

    .PARAMETER StopOnCompletion
        If this switch is enabled, sets a value that determines whether the data collector set stops when all the data collectors in the set are in a completed state.

    .PARAMETER Instance
        By default, the template will be applied to all instances. If you want to set specific ones in addition to the default, supply just the instance name.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Import-DbaPfDataCollectorSetTemplate

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query'

        Creates a new data collector set named 'Long Running Query' from the dbatools repository on the SQL Server sql2017.

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query' -DisplayName 'New Long running query' -Confirm

        Creates a new data collector set named "New Long Running Query" using the 'Long Running Query' template. Forces a confirmation if the template exists.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2017 -Session db_ola_health | Remove-DbaPfDataCollectorSet
        Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template db_ola_health | Start-DbaPfDataCollectorSet

        Imports a session if it exists, then recreates it using a template.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSetTemplate | Out-GridView -PassThru | Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017

        Allows you to select a Session template then import to an instance named sql2017.

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query' -Instance SHAREPOINT

        Creates a new data collector set named 'Long Running Query' from the dbatools repository on the SQL Server sql2017 for both the default and the SHAREPOINT instance.

        If you'd like to remove counters for the default instance, use Remove-DbaPfDataCollectorCounter.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$DisplayName,
        [switch]$SchedulesEnabled,
        [string]$RootPath,
        [switch]$Segment,
        [int]$SegmentMaxDuration,
        [int]$SegmentMaxSize,
        [string]$Subdirectory,
        [int]$SubdirectoryFormat = 3,
        [string]$SubdirectoryFormatPattern = 'yyyyMMdd\-NNNNNN',
        [string]$Task,
        [switch]$TaskRunAsSelf,
        [string]$TaskArguments,
        [string]$TaskUserTextArguments,
        [switch]$StopOnCompletion,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string[]]$Template,
        [string[]]$Instance,
        [switch]$EnableException
    )
    begin {
        #Variable marked as unused by PSScriptAnalyzer
        #$metadata = Import-Clixml "$script:PSModuleRoot\bin\perfmontemplates\collectorsets.xml"

        $setscript = {
            $setname = $args[0]; $templatexml = $args[1]
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.SetXml($templatexml)
            $null = $collectorset.Commit($setname, $null, 0x0003) #add or modify.
            $null = $collectorset.Query($setname, $Null)
        }

        $instancescript = {
            $services = Get-Service -DisplayName *sql* | Select-Object -ExpandProperty DisplayName
            [regex]::matches($services, '(?<=\().+?(?=\))').Value | Where-Object { $PSItem -ne 'MSSQLSERVER' } | Select-Object -Unique
        }
    }
    process {


        if ((Test-Bound -ParameterName Path -Not) -and (Test-Bound -ParameterName Template -Not)) {
            Stop-Function -Message "You must specify Path or Template"
        }

        if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and (Test-Bound -ParameterName Template)) {
            Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist"
        }

        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            foreach ($file in $template) {
                $templatepath = "$script:PSModuleRoot\bin\perfmontemplates\collectorsets\$file.xml"
                if ((Test-Path $templatepath)) {
                    $Path += $templatepath
                } else {
                    Stop-Function -Message "Invalid template ($templatepath does not exist)" -Continue
                }
            }

            foreach ($file in $Path) {

                if ((Test-Bound -ParameterName DisplayName -Not)) {
                    Set-Variable -Name DisplayName -Value (Get-ChildItem -Path $file).BaseName
                }

                $Name = $DisplayName

                Write-Message -Level Verbose -Message "Processing $file for $computer"

                if ((Test-Bound -ParameterName RootPath -Not)) {
                    Set-Variable -Name RootName -Value "%systemdrive%\PerfLogs\Admin\$Name"
                }

                # Perform replace
                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\")
                $tempfile = "$temp\import-dbatools-perftemplate.xml"

                try {
                    # Get content
                    $contents = Get-Content $file -ErrorAction Stop

                    # Replace content
                    $replacements = 'RootPath', 'DisplayName', 'SchedulesEnabled', 'Segment', 'SegmentMaxDuration', 'SegmentMaxSize', 'SubdirectoryFormat', 'SubdirectoryFormatPattern', 'Task', 'TaskRunAsSelf', 'TaskArguments', 'TaskUserTextArguments', 'StopOnCompletion', 'DisplayNameUnresolved'

                    foreach ($replacement in $replacements) {
                        $phrase = "<$replacement></$replacement>"
                        $value = (Get-Variable -Name $replacement -ErrorAction SilentlyContinue).Value
                        if ($value -eq $false) {
                            $value = "0"
                        }
                        if ($value -eq $true) {
                            $value = "1"
                        }
                        $replacephrase = "<$replacement>$value</$replacement>"
                        $contents = $contents.Replace($phrase, $replacephrase)
                    }

                    # Set content
                    $null = Set-Content -Path $tempfile -Value $contents -Encoding Unicode
                    $xml = [xml](Get-Content $tempfile -ErrorAction Stop)
                    $plainxml = Get-Content $tempfile -ErrorAction Stop -Raw
                    $file = $tempfile
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }
                if (-not $xml.DataCollectorSet) {
                    Stop-Function -Message "$file is not a valid Performance Monitor template document" -Continue
                }

                try {
                    Write-Message -Level Verbose -Message "Importing $file as $name "

                    if ($instance) {
                        $instances = $instance
                    } else {
                        $instances = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $instancescript -ErrorAction Stop -Raw
                    }

                    $scriptBlock = {
                        try {
                            $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $Name, $plainxml -ErrorAction Stop
                            Write-Message -Level Verbose -Message " $results"
                        } catch {
                            Stop-Function -Message "Failure starting $setname on $computer" -ErrorRecord $_ -Target $computer -Continue
                        }
                    }

                    if ((Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name)) {
                        if ($Pscmdlet.ShouldProcess($computer, "CollectorSet $Name already exists. Modify?")) {
                            Invoke-Command -Scriptblock $scriptBlock
                            $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($computer, "Importing collector set $Name")) {
                            Invoke-Command -Scriptblock $scriptBlock
                            $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                        }
                    }

                    $newcollection = @()
                    foreach ($instance in $instances) {
                        $datacollector = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name | Get-DbaPfDataCollector
                        $sqlcounters = $datacollector | Get-DbaPfDataCollectorCounter | Where-Object { $_.Name -match 'sql.*\:' -and $_.Name -notmatch 'sqlclient' } | Select-Object -ExpandProperty Name

                        foreach ($counter in $sqlcounters) {
                            $split = $counter.Split(":")
                            $firstpart = switch ($split[0]) {
                                'SQLServer' { 'MSSQL' }
                                '\SQLServer' { '\MSSQL' }
                                default { $split[0] }
                            }
                            $secondpart = $split[-1]
                            $finalcounter = "$firstpart`$$instance`:$secondpart"
                            $newcollection += $finalcounter
                        }
                    }

                    if ($newcollection.Count) {
                        if ($Pscmdlet.ShouldProcess($computer, "Adding $($newcollection.Count) additional counters")) {
                            $null = Add-DbaPfDataCollectorCounter -InputObject $datacollector -Counter $newcollection
                        }
                    }

                    Remove-Item $tempfile -ErrorAction SilentlyContinue
                    $output
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZqF4qlsORPazjurDcstt5YMt
# LiegghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPIBued6oUEV10lsJjE0aiDiwVrzMA0GCSqGSIb3DQEBAQUABIIBALgjrBgc
# XUYCaYPIR3DtwmaEsNPoCB2zmehIcPqbHSMjAAeAclt93GXaHqGmhvQu0F+trb1v
# igWCty5eWiOm4zWsqxUcwYWn5Jf1AViFdVamsF9RQtC7QZR/mXDhlCCo8Ri7T4l7
# LF5SGKCl0VBOGeG3e6DHi2RNizbeDkJC6ooTy8spl4p8fy4cOQ8tvrv0CyRBRCv3
# duw0RHuauewaIfM+H7zElO0IT1ruxx4POSzFbtdaDauB8HFE1iD1S4CEDbcKT/+o
# VBaB1Cg/uquZxvhVOjwCGeKiWU2/9iEjU3YfQsI83nVbVPaVyjx9QyOZRXba2ATg
# osqKLwXe713KpcGhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzMlowLwYJKoZIhvcNAQkEMSIEIFd7RFaZ5+RY/lUN7R1EHPHwsI+X
# Tm8/sZ8mMDx4GgCEMA0GCSqGSIb3DQEBAQUABIIBACQ9jDUrBDh3ayjb+Krj/b6T
# rdT7ToWe4T3Fb/dy+zpDrSM0tOkATDIRFrQnGhK7J4V6jqFfA2mdn/nkTLvc9pmL
# c8jnycv0b0bFuS7eSljNXq1WPbmP54+qge0TKZ6dDkqyMMYPHUnYUX28AUVJ5YLB
# 57D0QBsDnDuao1MruWM6rinhKErf+E+tzvxBUJKZhoclr28nTx7ZOehpuWD0EPSk
# qDkMssGWdlUOtsfh27CPjFRajcC6+z4ydjZ/8W3qNmUFlnJsg26v1uKEjkRaQf4Q
# xQ7GcoaATVHeyqfuwWlz9BqU3dhxwR84/oDdabBdfGgkiGYN/VwnHsU940OulKI=
# SIG # End signature block
