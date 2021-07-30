function Copy-DbaAgentJob {
    <#
    .SYNOPSIS
        Copy-DbaAgentJob migrates jobs from one SQL Server to another.

    .DESCRIPTION
        By default, all jobs are copied. The -Job parameter is auto-populated for command-line completion and can be used to copy only specific jobs.

        If the job already exists on the destination, it will be skipped unless -Force is used.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The job(s) to process. This list is auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude. This list is auto-populated from the server.

    .PARAMETER DisableOnSource
        If this switch is enabled, the job will be disabled on the source server.

    .PARAMETER DisableOnDestination
        If this switch is enabled, the newly migrated job will be disabled on the destination server.

     .PARAMETER InputObject
        Piped in jobs from Get-DbaAgentJob

        .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Job will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent, Job
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaAgentJob

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster

        Copies all jobs from sqlserver2014a to sqlcluster, using Windows credentials. If jobs with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -Job PSJob -SourceSqlCredential $cred -Force

        Copies a single job, the PSJob job from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a job with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sqlserver2014a | Where-Object Category -eq "Report Server" | Copy-DbaAgentJob -Destination sqlserver2014b

        Copies all SSRS jobs (subscriptions) from AlwaysOn Primary SQL instance sqlserver2014a to AlwaysOn Secondary SQL instance sqlserver2014b
    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [switch]$DisableOnSource,
        [switch]$DisableOnDestination,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Source) {
            try {
                $InputObject = Get-DbaAgentJob -SqlInstance $Source -SqlCredential $SourceSqlCredential -Job $Job -ExcludeJob $ExcludeJob
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destJobs = $destServer.JobServer.Jobs

            foreach ($serverJob in $InputObject) {
                $jobName = $serverJob.Name
                $jobId = $serverJob.JobId
                $sourceserver = $serverJob.Parent.Parent

                $copyJobStatus = [pscustomobject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $jobName
                    Type              = "Agent Job"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Job -and $jobName -notin $Job -or $jobName -in $ExcludeJob) {
                    Write-Message -Level Verbose -Message "Job [$jobName] filtered. Skipping."
                    continue
                }
                Write-Message -Message "Working on job: $jobName" -Level Verbose
                $sql = "
                SELECT sp.[name] AS MaintenancePlanName
                FROM msdb.dbo.sysmaintplan_plans AS sp
                INNER JOIN msdb.dbo.sysmaintplan_subplans AS sps
                    ON sps.plan_id = sp.id
                WHERE job_id = '$($jobId)'"
                Write-Message -Message $sql -Level Debug

                $MaintenancePlanName = $sourceServer.Query($sql).MaintenancePlanName

                if ($MaintenancePlanName) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanNam")) {
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is associated with maintenance plan"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanName"
                    }
                    continue
                }

                $dbNames = ($serverJob.JobSteps | Where-Object { $_.SubSystem -ne 'ActiveScripting' }).DatabaseName | Where-Object { $_.Length -gt 0 }
                $missingDb = $dbNames | Where-Object { $destServer.Databases.Name -notcontains $_ }

                if ($missingDb.Count -gt 0 -and $dbNames.Count -gt 0) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobName].")) {
                        $missingDb = ($missingDb | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on database: $missingDb"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobName]."
                    }
                    continue
                }

                $missingLogin = $serverJob.OwnerLoginName | Where-Object { $destServer.Logins.Name -notcontains $_ }

                if ($missingLogin.Count -gt 0) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Login(s) $missingLogin doesn't exist on destination. Use -Force to set owner to [sa]. Skipping job [$jobName].")) {
                            $missingLogin = ($missingLogin | Sort-Object | Get-Unique) -join ", "
                            $copyJobStatus.Status = "Skipped"
                            $copyJobStatus.Notes = "Job is dependent on login $missingLogin"
                            $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Login(s) $missingLogin doesn't exist on destination. Use -Force to set owner to [sa]. Skipping job [$jobName]."
                        }
                        continue
                    }
                }

                $proxyNames = ($serverJob.JobSteps | Where-Object ProxyName).ProxyName
                $missingProxy = $proxyNames | Where-Object { $destServer.JobServer.ProxyAccounts.Name -notcontains $_ }

                if ($missingProxy -and $proxyNames) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Proxy Account(s) $missingProxy doesn't exist on destination. Skipping job [$jobName].")) {
                        $missingProxy = ($missingProxy | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on proxy $missingProxy"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Proxy Account(s) $missingProxy doesn't exist on destination. Skipping job [$jobName]."
                    }
                    continue
                }

                $operators = $serverJob.OperatorToEmail, $serverJob.OperatorToNetSend, $serverJob.OperatorToPage | Where-Object { $_.Length -gt 0 }
                $missingOperators = $operators | Where-Object { $destServer.JobServer.Operators.Name -notcontains $_ }

                if ($missingOperators.Count -gt 0 -and $operators.Count -gt 0) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]")) {
                        $missingOperator = ($operators | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on operator $missingOperator"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]"
                    }
                    continue
                }

                if ($destJobs.name -contains $serverJob.name) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Job $jobName exists at destination. Use -Force to drop and migrate.")) {
                            $copyJobStatus.Status = "Skipped"
                            $copyJobStatus.Notes = "Already exists on destination"
                            $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Job $jobName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping job $jobName and recreating")) {
                            try {
                                Write-Message -Message "Dropping Job $jobName" -Level Verbose
                                $destServer.JobServer.Jobs[$jobName].Drop()
                            } catch {
                                $copyJobStatus.Status = "Failed"
                                $copyJobStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue dropping job" -Target $jobName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating Job $jobName")) {
                    try {
                        Write-Message -Message "Copying Job $jobName" -Level Verbose
                        $sql = $serverJob.Script() | Out-String

                        if ($missingLogin.Count -gt 0 -and $force) {
                            $saLogin = Get-SqlSaLogin -SqlInstance $destServer
                            $sql = $sql -replace [Regex]::Escape("@owner_login_name=N'$missingLogin'"), [Regex]::Escape("@owner_login_name=N'$saLogin'")
                        }

                        $sql = $sql -replace [Regex]::Escape("@server=N'$($sourceserver.DomainInstanceName)'"), [Regex]::Escape("@server=N'$($destServer.DomainInstanceName)'")

                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql)

                        $destServer.JobServer.Jobs.Refresh()
                        $destServer.JobServer.Jobs[$serverJob.name].IsEnabled = $sourceServer.JobServer.Jobs[$serverJob.name].IsEnabled
                        $destServer.JobServer.Jobs[$serverJob.name].Alter()
                    } catch {
                        $copyJobStatus.Status = "Failed"
                        $copyJobStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying job" -Target $jobName -ErrorRecord $_ -Continue
                    }
                }

                if ($DisableOnDestination) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Disabling $jobName")) {
                        Write-Message -Message "Disabling $jobName on $destinstance" -Level Verbose
                        $destServer.JobServer.Jobs[$serverJob.name].IsEnabled = $False
                        $destServer.JobServer.Jobs[$serverJob.name].Alter()
                    }
                }

                if ($DisableOnSource) {
                    if ($Pscmdlet.ShouldProcess($source, "Disabling $jobName")) {
                        Write-Message -Message "Disabling $jobName on $source" -Level Verbose
                        $serverJob.IsEnabled = $false
                        $serverJob.Alter()
                    }
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Reporting status of migration for $jobname")) {
                    $copyJobStatus.Status = "Successful"
                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIfwmHMXNmvYuah/wJaDDLsYo
# h5OgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFOti0Qf7DhTFhCDNvBZoqCQRqfZoMA0GCSqGSIb3DQEBAQUABIIBAF03N0GD
# ZzfFJjLrFaCVPr1bgvmup/LCVcLVPE3KcOKBN8A3+Il+tWsPKasDYrcqFrPTe60b
# mChoBhFckYwBKDp9+/JijJ3JAfc+U/6QTxbjtebqARpTi6x7LG8sTLLTVT4MXt8S
# Me04oNneDa+IbCMGjJlMiYmnEFDWJ7oMVTtPBEFCpBm0b3u9BQpvjupKcQqtERca
# Z/GOK/RLwIBZi3HCi++ln9SzMHEx+U3YjVrqsyY+4Qme6eio0vXa8BW8DoCtqUWt
# XATiXZ8c/ueheoS4PqB5iLmGhEfPRewdgBGlpWZtEKpv5BJX48OSQQMn8rwlCduJ
# FYDsRRQlkPWpxBKhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkxNVowLwYJKoZIhvcNAQkEMSIEIJ3MRl05+FG9OVF1MYX8wn+x2Wet
# 6c3feP2qij+spvD+MA0GCSqGSIb3DQEBAQUABIIBAGaSuHm7+eYjs6ASz9Kbq6vq
# DDcD0Uc8XpgBBES9dgMlh1vOYpKI74lQ0ab7bIaZPmznzurMukPxGSiSavf7BHZ3
# knXhyOJeYX53YlpUm+Vv/fVfjuoYKNbhcLPefCjb5ENpyzSiSSPO+s1Etc/EOgtE
# SCH1ipGpph/hQffsrqaqJ8ux1jMUgvfdObpzXlgOftL5h835NeHZhjEDANxNYe4Z
# Jw623pZbWC/dcCSGne1w6jMRJAtqMJrHDbBh6IEkp/HPmzH6kaWAAYYLCGgX60dm
# EjBzQZpgXSRGK/cnhdvsIIATwmcIAZZQ35w9XdAd00CA4W58k6ACMRCPXXjL7a4=
# SIG # End signature block
