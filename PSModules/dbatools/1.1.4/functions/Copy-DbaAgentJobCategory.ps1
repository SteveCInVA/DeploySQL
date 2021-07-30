function Copy-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Copy-DbaAgentJobCategory migrates SQL Agent categories from one SQL Server to another. This is similar to sp_add_category.

        https://msdn.microsoft.com/en-us/library/ms181597.aspx

    .DESCRIPTION
        By default, all SQL Agent categories for Jobs, Operators and Alerts are copied.

        The -OperatorCategories parameter is auto-populated for command-line completion and can be used to copy only specific operator categories.
        The -AgentCategories parameter is auto-populated for command-line completion and can be used to copy only specific agent categories.
        The -JobCategories parameter is auto-populated for command-line completion and can be used to copy only specific job categories.

        If the category already exists on the destination, it will be skipped unless -Force is used.

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

    .PARAMETER CategoryType
        Specifies the Category Type to migrate. Valid options are "Job", "Alert" and "Operator". When CategoryType is specified, all categories from the selected type will be migrated. For granular migrations, use the three parameters below.

    .PARAMETER OperatorCategory
        This parameter is auto-populated for command-line completion and can be used to copy only specific operator categories.

    .PARAMETER AgentCategory
        This parameter is auto-populated for command-line completion and can be used to copy only specific agent categories.

    .PARAMETER JobCategory
        This parameter is auto-populated for command-line completion and can be used to copy only specific job categories.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Category will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster

        Copies all operator categories from sqlserver2014a to sqlcluster using Windows authentication. If operator categories with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster -OperatorCategory PSOperator -SourceSqlCredential $cred -Force

        Copies a single operator category, the PSOperator operator category from sqlserver2014a to sqlcluster using SQL credentials to authenticate to sqlserver2014a and Windows credentials for sqlcluster. If an operator category with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobCategory -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ParameterSetName = 'SpecificAlerts')]
        [ValidateSet('Job', 'Alert', 'Operator')]
        [string[]]$CategoryType,
        [string[]]$JobCategory,
        [string[]]$AgentCategory,
        [string[]]$OperatorCategory,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        function Copy-JobCategory {
            <#
                .SYNOPSIS
                    Copy-JobCategory migrates job categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all job categories are copied. The -JobCategories parameter is auto-populated for command-line completion and can be used to copy only specific job categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the job category already exists on the destination, it will be skipped unless -Force is used.
            #>
            param (
                [string[]]$jobCategories
            )

            process {

                $serverJobCategories = $sourceServer.JobServer.JobCategories | Where-Object ID -ge 100
                $destJobCategories = $destServer.JobServer.JobCategories | Where-Object ID -ge 100

                foreach ($jobCategory in $serverJobCategories) {
                    $categoryName = $jobCategory.Name

                    $copyJobCategoryStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $categoryName
                        Type              = "Agent Job Category"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($jobCategories.Count -gt 0 -and $jobCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destJobCategories.Name -contains $jobCategory.name) {
                        if ($force -eq $false) {
                            $copyJobCategoryStatus.Status = "Skipped"
                            $copyJobCategoryStatus.Notes = "Already exists on destination"
                            $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Job category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping job category $categoryName")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Job category $categoryName"
                                    $destServer.JobServer.JobCategories[$categoryName].Drop()
                                } catch {
                                    $copyJobCategoryStatus.Status = "Failed"
                                    $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Stop-Function -Message "Issue dropping job category" -Target $categoryName -ErrorRecord $_ -Continue
                                }
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Creating Job category $categoryName")) {
                        try {
                            Write-Message -Level Verbose -Message "Copying Job category $categoryName"
                            $sql = $jobCategory.Script() | Out-String
                            Write-Message -Level Debug -Message "SQL Statement: $sql"
                            $destServer.Query($sql)

                            $copyJobCategoryStatus.Status = "Successful"
                            $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            $copyJobCategoryStatus.Status = "Failed"
                            $copyJobCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue copying job category" -Target $categoryName -ErrorRecord $_
                        }
                    }
                }
            }
        }

        function Copy-OperatorCategory {
            <#
                .SYNOPSIS
                    Copy-OperatorCategory migrates operator categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all operator categories are copied. The -OperatorCategories parameter is auto-populated for command-line completion and can be used to copy only specific operator categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the operator category already exists on the destination, it will be skipped unless -Force is used.
            #>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
            param (
                [string[]]$operatorCategories
            )
            process {
                $serverOperatorCategories = $sourceServer.JobServer.OperatorCategories | Where-Object ID -ge 100
                $destOperatorCategories = $destServer.JobServer.OperatorCategories | Where-Object ID -ge 100

                foreach ($operatorCategory in $serverOperatorCategories) {
                    $categoryName = $operatorCategory.Name

                    $copyOperatorCategoryStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Agent Operator Category"
                        Name              = $categoryName
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($operatorCategories.Count -gt 0 -and $operatorCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destOperatorCategories.Name -contains $operatorCategory.Name) {
                        if ($force -eq $false) {
                            $copyOperatorCategoryStatus.Status = "Skipped"
                            $copyOperatorCategoryStatus.Notes = "Already exists on destination"
                            $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Operator category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping operator category $categoryName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Operator category $categoryName"
                                    $destServer.JobServer.OperatorCategories[$categoryName].Drop()
                                    Write-Message -Level Verbose -Message "Copying Operator category $categoryName"
                                    $sql = $operatorCategory.Script() | Out-String
                                    Write-Message -Level Debug -Message $sql
                                    $destServer.Query($sql)
                                } catch {
                                    $copyOperatorCategoryStatus.Status = "Failed"
                                    $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Stop-Function -Message "Issue dropping operator category" -Target $categoryName -ErrorRecord $_
                                }
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating Operator category $categoryName")) {
                            try {
                                Write-Message -Level Verbose -Message "Copying Operator category $categoryName"
                                $sql = $operatorCategory.Script() | Out-String
                                Write-Message -Level Debug -Message $sql
                                $destServer.Query($sql)

                                $copyOperatorCategoryStatus.Status = "Successful"
                                $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                $copyOperatorCategoryStatus.Status = "Failed"
                                $copyOperatorCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue copying operator category" -Target $categoryName -ErrorRecord $_
                            }
                        }
                    }
                }
            }
        }

        function Copy-AlertCategory {
            <#
                .SYNOPSIS
                    Copy-AlertCategory migrates alert categories from one SQL Server to another.

                .DESCRIPTION
                    By default, all alert categories are copied. The -AlertCategories parameter is auto-populated for command-line completion and can be used to copy only specific alert categories.

                    If the associated credential for the category does not exist on the destination, it will be skipped. If the alert category already exists on the destination, it will be skipped unless -Force is used.
            #>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
            param (
                [string[]]$AlertCategories
            )

            process {
                if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
                    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
                }

                $serverAlertCategories = $sourceServer.JobServer.AlertCategories | Where-Object ID -ge 100
                $destAlertCategories = $destServer.JobServer.AlertCategories | Where-Object ID -ge 100

                foreach ($alertCategory in $serverAlertCategories) {
                    $categoryName = $alertCategory.Name

                    $copyAlertCategoryStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Type              = "Agent Alert Category"
                        Name              = $categoryName
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($alertCategories.Length -gt 0 -and $alertCategories -notcontains $categoryName) {
                        continue
                    }

                    if ($destAlertCategories.Name -contains $alertCategory.name) {
                        if ($force -eq $false) {
                            $copyAlertCategoryStatus.Status = "Skipped"
                            $copyAlertCategoryStatus.Notes = "Already exists on destination"
                            $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Alert category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping alert category $categoryName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping Alert category $categoryName"
                                    $destServer.JobServer.AlertCategories[$categoryName].Drop()
                                    Write-Message -Level Verbose -Message "Copying Alert category $categoryName"
                                    $sql = $alertcategory.Script() | Out-String
                                    Write-Message -Level Debug -Message "SQL Statement: $sql"
                                    $destServer.Query($sql)
                                } catch {
                                    $copyAlertCategoryStatus.Status = "Failed"
                                    $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Stop-Function -Message "Issue dropping alert category" -Target $categoryName -ErrorRecord $_
                                }
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating Alert category $categoryName")) {
                            try {
                                Write-Message -Level Verbose -Message "Copying Alert category $categoryName"
                                $sql = $alertCategory.Script() | Out-String
                                Write-Message -Level Debug -Message $sql
                                $destServer.Query($sql)

                                $copyAlertCategoryStatus.Status = "Successful"
                                $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                $copyAlertCategoryStatus.Status = "Failed"
                                $copyAlertCategoryStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue creating alert category" -Target $categoryName -ErrorRecord $_
                            }
                        }
                    }
                }
            }
        }

        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
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

            if ($CategoryType.count -gt 0) {

                switch ($CategoryType) {
                    "Job" {
                        Copy-JobCategory
                    }

                    "Alert" {
                        Copy-AlertCategory
                    }

                    "Operator" {
                        Copy-OperatorCategory
                    }
                }
                continue
            }

            if (($OperatorCategory.Count + $AlertCategory.Count + $jobCategory.Count) -gt 0) {

                if ($OperatorCategory.Count -gt 0) {
                    Copy-OperatorCategory -OperatorCategories $OperatorCategory
                }

                if ($AlertCategory.Count -gt 0) {
                    Copy-AlertCategory -AlertCategories $AlertCategory
                }

                if ($jobCategory.Count -gt 0) {
                    Copy-JobCategory -JobCategories $jobCategory
                }
                continue
            }
            Copy-OperatorCategory
            Copy-AlertCategory
            Copy-JobCategory
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUmVpZYdXCewgCV0dwGBYgFlN
# 1EKgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFGciQLZfMlvlL/w42Hg8nIAugOxCMA0GCSqGSIb3DQEBAQUABIIBADXC4Npf
# VOaQwaEgipYntsGM3UclXT2VDOhriu/jx2j0YnPMZACoNSk0NsvRG7oKXf1NDZHI
# n2guMETDnjby1hSySeGcW4hOBHkoLNwPNtBkW9HpmgAgvFSqxhO0WB66aa8JGkvp
# +4LZILfbUF3cHqfar9kryOLPiW63X1wMG0QhqGONdqAlRdGMbOn8B7ZxMQB2T3Du
# 4O7eCi9CuPtGktQYzEWDhePnu3Zu4kDzdFDpj3GgLcGUbm+rXCIh0hyS1Pw5rts8
# 9CYpINXKm0EjxXPd9nhH+M5//rRhYIAjuieeIajFIM98/oxQMhQ0XH0rgrztUfrs
# fwqQrjRpgeiu43ChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkxNVowLwYJKoZIhvcNAQkEMSIEIDr1a2Y8CgswsPnaVmHjiiz9QieU
# 1MRxDCx1nhdpYPD/MA0GCSqGSIb3DQEBAQUABIIBAFqDwl2iAC4X8Qm62FoQ/XdS
# /qCQqm4F9+87PpqID8AirnsetLrswpyXwEDrLlbaxtuTWbyAuwj266Zrpk0NS4Gn
# AD/7ECiKWduvv4/HTXCr9huH2V/cJAl9ay5/ZFJxbnmnIz6hwwLo0imkYi0oGo6s
# Snlt6HMJ0iRyY+SntJumei/gS9txAuQ5F8BE7zMD7uA7fUkqfokODkfchtFmWuFv
# M3v6YrYuveLsu+Y8+uYpyPxx5B/ZhFqXYzOZaWCRmCAZtVOHVqDmOUhsfSCUSSCR
# M7HVE0YsvwIkqK4JgBtf0rIQZRM9v8bkJ8YcI2t434vXHFm7aSxkcchOunt+R+U=
# SIG # End signature block
