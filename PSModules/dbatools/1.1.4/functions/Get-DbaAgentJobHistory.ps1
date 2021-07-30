function Get-DbaAgentJobHistory {
    <#
    .SYNOPSIS
        Gets execution history of SQL Agent Job on instance(s) of SQL Server.

    .DESCRIPTION
        Get-DbaAgentJobHistory returns all information on the executions still available on each instance(s) of SQL Server submitted.
        The cleanup of SQL Agent history determines how many records are kept.

        https://msdn.microsoft.com/en-us/library/ms201680.aspx
        https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job from which the history is wanted. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server

    .PARAMETER StartDate
        The DateTime starting from which the history is wanted. If unspecified, all available records will be processed.

    .PARAMETER EndDate
        The DateTime before which the history is wanted. If unspecified, all available records will be processed.

    .PARAMETER OutcomeType
        The CompletionResult to filter the history for. Valid values are: Failed, Succeeded, Retry, Cancelled, InProgress, Unknown

    .PARAMETER ExcludeJobSteps
        Use this switch to discard all job steps, and return only the job totals

    .PARAMETER WithOutputFile
        Use this switch to retrieve the output file (only if you want step details). Bonus points, we handle the quirks
        of SQL Agent tokens to the best of our knowledge (https://technet.microsoft.com/it-it/library/ms175575(v=sql.110).aspx)

    .PARAMETER JobCollection
        An array of SMO jobs

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Klaas Vandenberghe (@PowerDbaKlaas) | Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobHistory

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost

        Returns all SQL Agent Job execution results on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

        Returns all SQL Agent Job execution results for the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> 'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

        Returns all SQL Agent Job execution results for sql1 and sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 | Select-Object *

        Returns all properties for all SQl Agent Job execution results on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup'

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup' -WithOutputFile

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17,
        with additional properties that show the output filename path

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -ExcludeJobSteps

        Returns the SQL Agent Job execution results for the whole jobs on sql2\Inst2K17, leaving out job step execution results.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -StartDate '2017-05-22' -EndDate '2017-05-23 12:30:00'

        Returns the SQL Agent Job execution results between 2017/05/22 00:00:00 and 2017/05/23 12:30:00 on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Where-Object Name -Match backup | Get-DbaAgentJobHistory

        Gets all jobs with the name that match the regex pattern "backup" and then gets the job history from those. You can also use -Like *backup* in this example.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2016 -OutcomeType Failed

        Returns only the failed SQL Agent Job execution results for the sql2016 SQL Server instance.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [DateTime]$StartDate = "1900-01-01",
        [DateTime]$EndDate = $(Get-Date),
        [ValidateSet('Failed', 'Succeeded', 'Retry', 'Cancelled', 'InProgress', 'Unknown')]
        [Microsoft.SqlServer.Management.Smo.Agent.CompletionResult]$OutcomeType,
        [switch]$ExcludeJobSteps,
        [switch]$WithOutputFile,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Collection")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job]$JobCollection,
        [switch]$EnableException
    )

    begin {
        $filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
        $filter.StartRunDate = $StartDate
        $filter.EndRunDate = $EndDate

        if (Test-Bound OutcomeType) {
            $filter.OutcomeTypes = $OutcomeType
        }

        if ($ExcludeJobSteps -and $WithOutputFile) {
            Stop-Function -Message "You can't use -ExcludeJobSteps and -WithOutputFile together"
        }

        function Get-JobHistory {
            [CmdletBinding()]
            param (
                $Server,
                $Job,
                [switch]$WithOutputFile
            )
            $tokenrex = [regex]'\$\((?<method>[^()]+)\((?<tok>[^)]+)\)\)|\$\((?<tok>[^)]+)\)'
            $propmap = @{
                'INST'      = $Server.ServiceName
                'MACH'      = $Server.ComputerName
                'SQLDIR'    = $Server.InstallDataDirectory
                'SQLLOGDIR' = $Server.ErrorLogPath
                #'STEPCT' loop number ?
                'SRVR'      = $Server.DomainInstanceName
                # WMI( property ) impossible
            }


            $squote_rex = [regex]"(?<!')'(?!')"
            $dquote_rex = [regex]'(?<!")"(?!")'
            $rbrack_rex = [regex]'(?<!])](?!])'

            function Resolve-TokenEscape($method, $value) {
                if (!$method) {
                    return $value
                }
                $value = switch ($method) {
                    'ESCAPE_SQUOTE' { $squote_rex.Replace($value, "''") }
                    'ESCAPE_DQUOTE' { $dquote_rex.Replace($value, '""') }
                    'ESCAPE_RBRACKET' { $rbrack_rex.Replace($value, ']]') }
                    'ESCAPE_NONE' { $value }
                    default { $value }
                }
                return $value
            }

            #'STEPID' =  stepid
            #'STRTTM' job begin time
            #'STRTDT' job begin date
            #'JOBID' = JobId
            function Resolve-JobToken($exec, $outfile, $outcome) {
                $n = $tokenrex.Matches($outfile)
                foreach ($x in $n) {
                    $tok = $x.Groups['tok'].Value
                    $EscMethod = $x.Groups['method'].Value
                    if ($propmap.containskey($tok)) {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $propmap[$tok]
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STEPID') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.StepID
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'JOBID') {
                        # convert(binary(16), ?)
                        $repl = @('0x') + @($exec.JobID.ToByteArray() | ForEach-Object -Process { $_.ToString('X2') }) -join ''
                        $repl = Resolve-TokenEscape -method $EscMethod -value $repl
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTDT') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $outcome.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTTM') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$outcome.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'DATE') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'TIME') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$exec.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                }
                return $outfile
            }
            try {
                Write-Message -Message "Attempting to get job history from $instance" -Level Verbose
                if ($Job) {
                    foreach ($currentjob in $Job) {
                        $filter.JobName = $currentjob
                        $executions += $server.JobServer.EnumJobHistory($filter)
                    }
                } else {
                    $executions = $server.JobServer.EnumJobHistory($filter)
                }
                if ($ExcludeJobSteps) {
                    $executions = $executions | Where-Object { $_.StepID -eq 0 }
                }

                if ($WithOutputFile) {
                    $outmap = @{ }
                    $outfiles = Get-DbaAgentJobOutputFile -SqlInstance $Server -SqlCredential $SqlCredential -Job $Job

                    foreach ($out in $outfiles) {
                        if (!$outmap.ContainsKey($out.Job)) {
                            $outmap[$out.Job] = @{ }
                        }
                        $outmap[$out.Job][$out.StepId] = $out.OutputFileName
                    }
                }
                $outcome = [pscustomobject]@{ }
                foreach ($execution in $executions) {
                    $status = switch ($execution.RunStatus) {
                        0 { "Failed" }
                        1 { "Succeeded" }
                        2 { "Retry" }
                        3 { "Canceled" }
                    }

                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    $DurationInSeconds = ($execution.RunDuration % 100) + [math]::floor( ($execution.RunDuration % 10000 ) / 100 ) * 60 + [math]::floor( ($execution.RunDuration % 1000000 ) / 10000 ) * 60 * 60
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name StartDate -value ([dbadatetime]$execution.RunDate)
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name EndDate -value ([dbadatetime]$execution.RunDate.AddSeconds($DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Duration -value ([prettytimespan](New-TimeSpan -Seconds $DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Status -value $status
                    if ($WithOutputFile) {
                        if ($execution.StepID -eq 0) {
                            $outcome = $execution
                        }
                        try {
                            $outname = $outmap[$execution.JobName][$execution.StepID]
                            $outname = Resolve-JobToken -exec $execution -outcome $outcome -outfile $outname
                            $outremote = Join-AdminUNC $Server.ComputerName $outname
                        } catch {
                            $outname = ''
                            $outremote = ''
                        }
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name OutputFileName -value $outname
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name RemoteOutputFileName -value $outremote
                        # Add this in for easier ConvertTo-DbaTimeline Support
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message, OutputFileName, RemoteOutputFileName -TypeName AgentJobHistory
                    } else {
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message -TypeName AgentJobHistory
                    }

                }
            } catch {
                Stop-Function -Message "Could not get Agent Job History from $instance" -Target $instance -Continue
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($JobCollection) {
            foreach ($currentjob in $JobCollection) {
                Get-JobHistory -Server $currentjob.Parent.Parent -Job $currentjob.Name -WithOutputFile:$WithOutputFile
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            if ($ExcludeJob) {
                $jobs = $server.JobServer.Jobs.Name | Where-Object { $_ -notin $ExcludeJob }
                foreach ($currentjob in $jobs) {
                    Get-JobHistory -Server $server -Job $currentjob -WithOutputFile:$WithOutputFile
                }
            } else {
                Get-JobHistory -Server $server -Job $Job -WithOutputFile:$WithOutputFile
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIBW42yeLDUFmTyEiCWkPN0NE
# eaigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFLcpzF8EyXN3mTuAEDZjZ3z6V/nAMA0GCSqGSIb3DQEBAQUABIIBAEC0rMfP
# /uck9N0myHTz4J8z2FJEtd9LfyKnfoibFKFtLckbXwZ+y43cxUD9VKLjvgSu6Tut
# WU/fuwDeIPIZOyRieX87gdMQCRCKZ0fTCofN2iOJJBQyXbqYsUdcl6p74e9lU1Ta
# DcnrdZfDI4emKIHC7Bvh4vBjbRdihJN5VkTApWzx7UNnkQS3JIOcOQS4m7JDMDh3
# HSxltl5BCchqnKajgG2uiDtVMhMN4Un+TftSdoGiluGnNm2vI5yDZxNUloSHpiDj
# WqfuDd4+eOWxvpcqU3Mh8ZyEDTiLr7x47OMQBbvv48IxDIPBZsknVXqux2k9N9vf
# QGIJRIFEIPgED1ehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyNVowLwYJKoZIhvcNAQkEMSIEIHQt5UkwhGhcaiiEOlBPiTRwWZnA
# S0iKklWVDKB3f2rzMA0GCSqGSIb3DQEBAQUABIIBAF7g01kxKdQPj3DA2eN/qZ3U
# Q6bN7gC4r04/rTs28FOoQvYQUaOh37wBsUgru4nws4J+Z7IbsJKIus6fN9Y6tic3
# o22VSo1YjA/z64VlCTcyoAGgTcexldqVmXXZ7SSkIA54tFuYDr42HNvDldEBuX28
# eU3RjAYCtsGyAF03i2p1fY8uDfAnHgXwBbdJ/YbwDPCh0w9DE5+wyPskv6d/dZvz
# 6W1Fg7c7aTAvnKqAlNGrQgR1KIFzD6g6EZXBwkNxDmqkw0KwEzY1pRO1406yLbMs
# eyOfF1YsxrZuc0uaimOthDYI1JOT9xu0mX08yYBdfpLOulMdnxAiLMF7Na6m9vg=
# SIG # End signature block
