function Get-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Returns all SQL Agent Shared Schedules on a SQL Server Agent.

    .DESCRIPTION
        This function returns SQL Agent Shared Schedules.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        Parameter to filter the schedules returned

    .PARAMETER ScheduleUid
        The unique identifier of the schedule

    .PARAMETER Id
        Parameter to filter the schedules returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Schedule
        Author: Chris McKeown (@devopsfu), http://www.devopsfu.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost

        Returns all SQL Agent Shared Schedules on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016

        Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -Id 3

        Returns the SQL Agent Shared Schedules with the Id of 3

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Returns the SQL Agent Shared Schedules with the UID

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance sql2016 -Schedule "Maintenance10min","Maintenance60min"

        Returns the "Maintenance10min" & "Maintenance60min" schedules from the sql2016 SQL Server instance
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Schedule,
        [string[]]$ScheduleUid,
        [int[]]$Id,
        [switch]$EnableException
    )

    begin {
        function Get-ScheduleDescription {
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [object]$currentschedule

            )

            # Get the culture to make sure the right date and time format is displayed
            $datetimeFormat = (Get-Culture).DateTimeFormat

            # Set the intial description
            $description = ""

            # Get the date and time values
            $startDate = Get-Date $currentschedule.ActiveStartDate -format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date ($currentschedule.ActiveStartTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern
            $endDate = Get-Date $currentschedule.ActiveEndDate -format $datetimeFormat.ShortDatePattern
            $endTime = Get-Date ($currentschedule.ActiveEndTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern

            # Start setting the description based on the frequency type
            switch ($currentschedule.FrequencyTypes) {
                { ($_ -eq 1) -or ($_ -eq "Once") } { $description += "Occurs on $startDate at $startTime" }
                { ($_ -in 4, 8, 16, 32) -or ($_ -in "Daily", "Weekly", "Monthly") } { $description += "Occurs every " }
                { ($_ -eq 64) -or ($_ -eq "AutoStart") } { $description += "Start automatically when SQL Server Agent starts " }
                { ($_ -eq 128) -or ($_ -eq "OnIdle") } { $description += "Start whenever the CPUs become idle" }
            }

            # Check the frequency types for daily or weekly i.e.
            switch ($currentschedule.FrequencyTypes) {
                # Daily
                { $_ -in 4, "Daily" } {
                    if ($currentschedule.FrequencyInterval -eq 1) {
                        $description += "day "
                    } elseif ($currentschedule.FrequencyInterval -gt 1) {
                        $description += "$($currentschedule.FrequencyInterval) day(s) "
                    }
                }

                # Weekly
                { $_ -in 8, "Weekly" } {
                    # Check if it's for one or more weeks
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "week on "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) week(s) on "
                    }

                    # Save the interval for the loop
                    $frequencyInterval = $currentschedule.FrequencyInterval

                    # Create the array to hold the days
                    $days = ($false, $false, $false, $false, $false, $false, $false)

                    # Loop through the days
                    while ($frequencyInterval -gt 0) {

                        switch ($FrequenctInterval) {
                            { ($frequencyInterval - 64) -ge 0 } {
                                $days[5] = "Saturday"
                                $frequencyInterval -= 64
                            }
                            { ($frequencyInterval - 32) -ge 0 } {
                                $days[4] = "Friday"
                                $frequencyInterval -= 32
                            }
                            { ($frequencyInterval - 16) -ge 0 } {
                                $days[3] = "Thursday"
                                $frequencyInterval -= 16
                            }
                            { ($frequencyInterval - 8) -ge 0 } {
                                $days[2] = "Wednesday"
                                $frequencyInterval -= 8
                            }
                            { ($frequencyInterval - 4) -ge 0 } {
                                $days[1] = "Tuesday"
                                $frequencyInterval -= 4
                            }
                            { ($frequencyInterval - 2) -ge 0 } {
                                $days[0] = "Monday"
                                $frequencyInterval -= 2
                            }
                            { ($frequencyInterval - 1) -ge 0 } {
                                $days[6] = "Sunday"
                                $frequencyInterval -= 1
                            }
                        }

                    }

                    # Add the days to the description by selecting the days and exploding the array
                    $description += ($days | Where-Object { $_ -ne $false }) -join ", "
                    $description += " "

                }

                # Monthly
                { $_ -in 16, "Monthly" } {
                    # Check if it's for one or more months
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "month "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) month(s) "
                    }

                    # Add the interval
                    $description += "on day $($currentschedule.FrequencyInterval) of that month "
                }

                # Monthly relative
                { $_ -in 32, "MonthlyRelative" } {
                    # Check for the relative day
                    switch ($currentschedule.FrequencyRelativeIntervals) {
                        { $_ -in 1, "First" } { $description += "first " }
                        { $_ -in 2, "Second" } { $description += "second " }
                        { $_ -in 4, "Third" } { $description += "third " }
                        { $_ -in 8, "Fourth" } { $description += "fourth " }
                        { $_ -in 16, "Last" } { $description += "last " }
                    }

                    # Get the relative day of the week
                    switch ($currentschedule.FrequencyInterval) {
                        1 { $description += "Sunday " }
                        2 { $description += "Monday " }
                        3 { $description += "Tuesday " }
                        4 { $description += "Wednesday " }
                        5 { $description += "Thursday " }
                        6 { $description += "Friday " }
                        7 { $description += "Saturday " }
                        8 { $description += "Day " }
                        9 { $description += "Weekday " }
                        10 { $description += "Weekend day " }
                    }

                    $description += "of every $($currentschedule.FrequencyRecurrenceFactor) month(s) "

                }
            }

            # Check the frequency type
            if ($currentschedule.FrequencyTypes -notin 64, 128) {

                # Check the subday types for minutes or hours i.e.
                if ($currentschedule.FrequencySubDayInterval -in 0, 1) {
                    $description += "at $startTime. "
                } else {

                    switch ($currentschedule.FrequencySubDayTypes) {
                        { $_ -in 2, "Seconds" } { $description += "every $($currentschedule.FrequencySubDayInterval) second(s) " }
                        { $_ -in 4, "Minutes" } { $description += "every $($currentschedule.FrequencySubDayInterval) minute(s) " }
                        { $_ -in 8, "Hours" } { $description += "every $($currentschedule.FrequencySubDayInterval) hour(s) " }
                    }

                    $description += "between $startTime and $endTime. "
                }

                # Check if an end date has been given
                if ($currentschedule.ActiveEndDate.Year -eq 9999) {
                    $description += "Schedule will be used starting on $startDate."
                } else {
                    $description += "Schedule will used between $startDate and $endDate."
                }
            }

            return $description
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "$($server.Edition) does not support SQL Server Agent. Skipping $server." -Continue
            }

            $scheduleCollection = @()

            if ($Schedule -or $ScheduleUid -or $Id) {
                if ($Schedule) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Name -in $Schedule }
                }

                if ($ScheduleUid) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.ScheduleUid -in $ScheduleUid }
                }

                if ($Id) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Id -in $Id }
                }
            } else {
                $scheduleCollection = $server.JobServer.SharedSchedules
            }

            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name as ScheduleName", "ActiveEndDate", "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled", "JobCount", "Description", "ScheduleUid"

            foreach ($currentschedule in $scheduleCollection) {
                $description = Get-ScheduleDescription -CurrentSchedule $currentschedule

                $currentschedule | Add-Member -Type NoteProperty -Name ComputerName -Value $server.ComputerName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name InstanceName -Value $server.ServiceName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name SqlInstance -Value $server.DomainInstanceName -Force
                $currentschedule | Add-Member -Type NoteProperty -Name Description -Value $description -Force

                Select-DefaultView -InputObject $currentschedule -Property $defaults
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUY1Pd9EACCM2bGN/G90tJDxvg
# rEigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFG/oUIHXrZHsb0QdWRaDqonvnl55MA0GCSqGSIb3DQEBAQUABIIBAIaVNzX9
# HCxY+UaUTGNXxTmx/j41e9U9AQvlrqFaILkteYAY3stCcRH+RcfNZU2uc7CBU5bf
# xPZugUN9M5k1g2D1Dz7iGeN53CSptLXfhmMHUM49mspE1YMiX2vK1x5lsEHOcD6N
# z6oZJ4AkkZ7g0TV3VXVRnmYKqTK+fRZ0HTlyGGSBkPmR9eWCDbarZrXotHCYjjHC
# 6PhJQEMWXoha8QPPtIfnt4NCV9/VZXDck2io4Q8Ikl2aXB5aXco1S5OhIxIYw1Pe
# 0Z+lc1f/iXEhJZ70zSaQZeOc16LOHxq0BbLqDjDt/Z0l+BgTxsWIjj6sZiLuQ2dy
# UmOahLeo21iq54mhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyNVowLwYJKoZIhvcNAQkEMSIEIFnBckmrsIJyJ6D+fL6M+SsJ5iGh
# KuIky3/zwqCKg2PYMA0GCSqGSIb3DQEBAQUABIIBAJ4ef7hyf9wwdszcTP2kYZK0
# c0XQdcZxj81jhFYIFobKPiiC4HIpvBZbBYKdCHhfE6Rrtx0FcpOFRvXFpPGAtkXa
# 8hU6H7MZTaCtkIjat/IKntmaRHnZ6od/rCfvpxqhZQ98yv3OpupXAx8FbRx7MmZz
# Jt1BI4UfUa/7G6AFM6/YS7A+3LsHROSJTsP0ShEuACfqlcemFOjxKEk28wQVEFFM
# rz2aEpbpAbkPtK0y4y8yo8DzvddHkyZLFyWngxZ4Q21lRayg4Dona3SQgmBwysbq
# WU7GWboXbsI+MryJ1X0Gu/e2f12b4ujjAW2p3bkC6/rJtSur92HIrSEnL2u8aTs=
# SIG # End signature block
