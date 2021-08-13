function Set-DbaAgentJob {
    <#
    .SYNOPSIS
        Set-DbaAgentJob updates a job.

    .DESCRIPTION
        Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job.

    .PARAMETER Schedule
        Schedule to attach to job. This can be more than one schedule.

    .PARAMETER ScheduleId
        Schedule ID to attach to job. This can be more than one schedule ID.

    .PARAMETER NewName
        The new name for the job.

    .PARAMETER Enabled
        Enabled the job.

    .PARAMETER Disabled
        Disabled the job

    .PARAMETER Description
        The description of the job.

    .PARAMETER StartStepId
        The identification number of the first step to execute for the job.

    .PARAMETER Category
        The category of the job.

    .PARAMETER OwnerLogin
        The name of the login that owns the job.

    .PARAMETER EventLogLevel
        Specifies when to place an entry in the Microsoft Windows application log for this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailLevel
        Specifies when to send an e-mail upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER NetsendLevel
        Specifies when to send a network message upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER PageLevel
        Specifies when to send a page upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailOperator
        The e-mail name of the operator to whom the e-mail is sent when EmailLevel is reached.

    .PARAMETER NetsendOperator
        The name of the operator to whom the network message is sent.

    .PARAMETER PageOperator
        The name of the operator to whom a page is sent.

    .PARAMETER DeleteLevel
        Specifies when to delete the job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER InputObject
        Enables piping job objects

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJob

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -Disabled

        Changes the job to disabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -OwnerLogin user1

        Changes the owner of the job

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EventLogLevel OnSuccess

        Changes the job and sets the notification to write to the Windows Application event log on success

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EmailLevel OnFailure -EmailOperator dba

        Changes the job and sets the notification to send an e-mail to the e-mail operator

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled on multiple servers

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -Description 'Just another job' -Whatif

        Doesn't Change the job but shows what would happen.

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job 'Job One' -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentJob -Job Job1 -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description using pipe line

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$Schedule,
        [int[]]$ScheduleId,
        [string]$NewName,
        [switch]$Enabled,
        [switch]$Disabled,
        [string]$Description,
        [int]$StartStepId,
        [string]$Category,
        [string]$OwnerLogin,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EventLogLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EmailLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$NetsendLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel,
        [string]$EmailOperator,
        [string]$NetsendOperator,
        [string]$PageOperator,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check of the event log level is of type string and set the integer value
        if (($EventLogLevel -notin 0, 1, 2, 3) -and ($null -ne $EventLogLevel)) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the email level is of type string and set the integer value
        if (($EmailLevel -notin 0, 1, 2, 3) -and ($null -ne $EmailLevel)) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the net send level is of type string and set the integer value
        if (($NetsendLevel -notin 0, 1, 2, 3) -and ($null -ne $NetsendLevel)) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the page level is of type string and set the integer value
        if (($PageLevel -notin 0, 1, 2, 3) -and ($null -ne $PageLevel)) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the delete level is of type string and set the integer value
        if (($DeleteLevel -notin 0, 1, 2, 3) -and ($null -ne $DeleteLevel)) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $SqlInstance
            return
        }

        # Check the e-mail level parameter
        if ($EmailOperator -and ($null -eq $EmailLevel)) {
            Stop-Function -Message "Please set the e-mail level parameter when the e-mail level operator is set." -Target $SqlInstance
            return
        }

        # Check the net send operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance
            return
        }

        # Check the net send level parameter
        if ($NetsendOperator -and ($null -eq $NetsendLevel)) {
            Stop-Function -Message "Please set the net send level parameter when the net send level operator is set." -Target $SqlInstance
            return
        }

        # Check the page operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance
            return
        }

        # Check the page level parameter
        if ($PageOperator -and ($null -eq $PageLevel)) {
            Stop-Function -Message "Please set the page level parameter when the page level operator is set." -Target $SqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance
                } else {
                    # Get the job
                    try {
                        $InputObject += $server.JobServer.Jobs[$j]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job" -Target $j -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        foreach ($currentjob in $InputObject) {
            $server = $currentjob.Parent.Parent

            #region job options
            # Settings the options for the job
            if ($NewName) {
                Write-Message -Message "Setting job name to $NewName" -Level Verbose
                $currentjob.Rename($NewName)
            }

            if ($Schedule) {
                # Loop through each of the schedules
                foreach ($s in $Schedule) {
                    if ($server.JobServer.SharedSchedules.Name -contains $s) {
                        # Get the schedule ID
                        $sID = $server.JobServer.SharedSchedules[$s].ID

                        # Add schedule to job
                        Write-Message -Message "Adding schedule id $sID to job" -Level Verbose
                        $currentjob.AddSharedSchedule($sID)
                    } else {
                        Stop-Function -Message "Schedule $s cannot be found on instance $instance" -Target $s -Continue
                    }

                }
            }

            if ($ScheduleId) {
                # Loop through each of the schedules IDs
                foreach ($sID in $ScheduleId) {
                    # Check if the schedule is
                    if ($server.JobServer.SharedSchedules.ID -contains $sID) {
                        # Add schedule to job
                        Write-Message -Message "Adding schedule id $sID to job" -Level Verbose
                        $currentjob.AddSharedSchedule($sID)

                    } else {
                        Stop-Function -Message "Schedule ID $sID cannot be found on instance $instance" -Target $sID -Continue
                    }
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting job to enabled" -Level Verbose
                $currentjob.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting job to disabled" -Level Verbose
                $currentjob.IsEnabled = $false
            }

            if ($Description) {
                Write-Message -Message "Setting job description to $Description" -Level Verbose
                $currentjob.Description = $Description
            }

            if ($Category) {
                # Check if the job category exists
                if ($Category -notin $server.JobServer.JobCategories.Name) {
                    if ($Force) {
                        if ($PSCmdlet.ShouldProcess($instance, "Creating job category on $instance")) {
                            try {
                                # Create the category
                                New-DbaAgentJobCategory -SqlInstance $server -Category $Category

                                Write-Message -Message "Setting job category to $Category" -Level Verbose
                                $currentjob.Category = $Category
                            } catch {
                                Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -ErrorRecord $_
                            }
                        }
                    } else {
                        Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance
                        return
                    }
                } else {
                    Write-Message -Message "Setting job category to $Category" -Level Verbose
                    $currentjob.Category = $Category
                }
            }

            if ($StartStepId) {
                # Get the job steps
                $currentjobSteps = $currentjob.JobSteps

                # Check if there are any job steps
                if ($currentjobSteps.Count -ge 1) {
                    # Check if the start step id value is one of the job steps in the job
                    if ($currentjobSteps.ID -contains $StartStepId) {
                        Write-Message -Message "Setting job start step id to $StartStepId" -Level Verbose
                        $currentjob.StartStepID = $StartStepId
                    } else {
                        Write-Message -Message "The step id is not present in job $j on instance $instance" -Warning
                    }

                } else {
                    Stop-Function -Message "There are no job steps present for job $j on instance $instance" -Target $instance -Continue
                }

            }

            if ($OwnerLogin) {
                # Check if the login name is present on the instance
                if ($server.Logins.Name -contains $OwnerLogin) {
                    Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose
                    $currentjob.OwnerLoginName = $OwnerLogin
                } else {
                    Stop-Function -Message "The given owner log in name $OwnerLogin does not exist on instance $instance" -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName EventLogLevel) {
                Write-Message -Message "Setting job event log level to $EventlogLevel" -Level Verbose
                $currentjob.EventLogLevel = $EventLogLevel
            }

            if (Test-Bound -ParameterName EmailLevel) {
                # Check if the notifiction needs to be removed
                if ($EmailLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToEmail = $null

                    # Remove the notification
                    $currentjob.EmailLevel = $EmailLevel
                } else {
                    # Check if either the operator e-mail parameter is set or the operator is set in the job
                    if ($EmailOperator -or $currentjob.OperatorToEmail) {
                        Write-Message -Message "Setting job e-mail level to $EmailLevel" -Level Verbose
                        $currentjob.EmailLevel = $EmailLevel
                    } else {
                        Stop-Function -Message "Cannot set e-mail level $EmailLevel without a valid e-mail operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName NetsendLevel) {
                # Check if the notifiction needs to be removed
                if ($NetsendLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToNetSend = $null

                    # Remove the notification
                    $currentjob.NetSendLevel = $NetsendLevel
                } else {
                    # Check if either the operator netsend parameter is set or the operator is set in the job
                    if ($NetsendOperator -or $currentjob.OperatorToNetSend) {
                        Write-Message -Message "Setting job netsend level to $NetsendLevel" -Level Verbose
                        $currentjob.NetSendLevel = $NetsendLevel
                    } else {
                        Stop-Function -Message "Cannot set netsend level $NetsendLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName PageLevel) {
                # Check if the notifiction needs to be removed
                if ($PageLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToPage = $null

                    # Remove the notification
                    $currentjob.PageLevel = $PageLevel
                } else {
                    # Check if either the operator pager parameter is set or the operator is set in the job
                    if ($PageOperator -or $currentjob.OperatorToPage) {
                        Write-Message -Message "Setting job pager level to $PageLevel" -Level Verbose
                        $currentjob.PageLevel = $PageLevel
                    } else {
                        Stop-Function -Message "Cannot set page level $PageLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            # Check the current setting of the job's email level
            if ($EmailOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                    Write-Message -Message "Setting job e-mail operator to $EmailOperator" -Level Verbose
                    $currentjob.OperatorToEmail = $EmailOperator
                } else {
                    Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($NetsendOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                    Write-Message -Message "Setting job netsend operator to $NetsendOperator" -Level Verbose
                    $currentjob.OperatorToNetSend = $NetsendOperator
                } else {
                    Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($PageOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $PageOperator) {
                    Write-Message -Message "Setting job pager operator to $PageOperator" -Level Verbose
                    $currentjob.OperatorToPage = $PageOperator
                } else {
                    Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName DeleteLevel) {
                Write-Message -Message "Setting job delete level to $DeleteLevel" -Level Verbose
                $currentjob.DeleteLevel = $DeleteLevel
            }
            #endregion job options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Changing the job $j")) {
                try {
                    Write-Message -Message "Changing the job" -Level Verbose

                    # Change the job
                    $currentjob.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the job" -ErrorRecord $_ -Target $instance -Continue
                }
                Get-DbaAgentJob -SqlInstance $server | Where-Object Name -eq $currentjob.name
            }
        }
    }

    end {
        Write-Message -Message "Finished changing job(s)" -Level Verbose
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUHEMB24FYBx9lCNhmH7Ggvl0O
# zragghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFIoS3JOpDAHgnaP84vOQyQ9bPEOMA0GCSqGSIb3DQEBAQUABIIBAKQ0UqPt
# ANDx7dtqsIyO3A/3iT3TEXV9j74vmjshYACWB7/4hPoadj1DK5R1/rJZ+Xg/XQ+V
# TCSDtuvQPThxF+m0mgBIl2OEFopAXPtWdH70edfQYxIapcKtreEea9r+X6uQ2bGC
# lVUun2BHyYPwVopke/hjGwvV68Te47YIReyBWUnso2WE+6IocJzC6yjTfux/9AQ0
# xB/zvG3qq5IJbRNmFvuXvRJ17Bn7l8L+rl1ozqBV5bqRG4H56kfsQyDnDE6z1Ntw
# 0VV5XpFmKrlkn/P+UjqsSMIdpy9S1TfjWN4FsJOzwFis+qhOc8lKlGm4VL9fdKjb
# QDcl3GxJP36hrm+hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1MlowLwYJKoZIhvcNAQkEMSIEIFNSaBexntTA2r9Zi9sm/LJIPN2V
# O2WllYI+m4bVONXlMA0GCSqGSIb3DQEBAQUABIIBAAQFBtGe5JWLnu10qe9w6x1j
# w92m1g4ZUm++dF0qRsZbdDFhqYikrpwgD3C3mDQpiVZZI5EGjWNY6KsEHE76Bft9
# QSutr4pFlY1a1zp1c2MML4zpeyMkDb2fl1IWxAKVMkXgsKLO8fNO1qL8fMBYoVZs
# oP96qvjHo4fMNE03T0RaNCMJO3yB9CtqvlVFEN4sCpNVuPSEzGLX6jBLyYSNBjKv
# 5vq5hHT3Tx2mPRotX4+ccyr+PmFSqV64GT1/LojPtxiQnGrlhTrdmBpghgzNLkWs
# c1kiSyKrp/jaJAvP/U4Ai50zfPmbqw2KBFpjIXFYujyApUyJf071Mq8wYkV/XRg=
# SIG # End signature block
