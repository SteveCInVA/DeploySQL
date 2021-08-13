function Install-DbaMultiTool {
    <#
    .SYNOPSIS
        Installs or updates the DBA MultiTool stored procedures.

    .DESCRIPTION
        Downloads, extracts and installs the DBA MultiTool stored procedures.

        DBA MultiTool links:
        https://dba-multitool.org
        https://github.com/LowlyDBA/dba-multitool/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install DBA MultiTool stored procedures into.

    .PARAMETER Branch
        Specifies an alternate branch of the DBA MultiTool to install.
        Allowed values:
            master (default)
            development

    .PARAMETER LocalFile
        Specifies the path to a local file to install DBA MultiTool from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/LowlyDBA/dba-multitool/.

    .PARAMETER Force
        If this switch is enabled, the DBA MultiTool will be downloaded from the internet even if previously cached.

    .PARAMETER Confirm
        Prompts to confirm actions.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, DbaMultiTool
        Author: John McCall (@lowlydba), https://lowlydba.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://dba-multitool.org

    .LINK
        https://dbatools.io/Install-DbaMultiTool

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1 -Database master

        Logs into server1 with Windows authentication and then installs the DBA MultiTool in the master database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs the DBA MultiTool in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1\instance1 -Database master -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs the DBA MultiTool in the master database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the DBA MultiTool in the master database.

    .EXAMPLE
        PS C:\> $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
        PS C:\> $servers | Install-DbaMultiTool

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the DBA MultiTool in the master database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance sql2016 -Branch development

        Installs the development branch version of the DBA MultiTool in the master database on sql2016 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('master', 'development')]
        [string]$Branch = "master",
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        if (-not $DbatoolsData) {
            $DbatoolsData = [System.IO.Path]::GetTempPath()
        }

        $url = "https://github.com/LowlyDBA/dba-multitool/archive/$Branch.zip"
        $temp = [System.IO.Path]::GetTempPath()
        $zipFile = Join-Path -Path $temp -ChildPath "DBA-MultiTool-$Branch.zip"
        $zipFolder = Join-Path -Path $temp -ChildPath "DBA-MultiTool-$Branch"
        $localCachedCopy = Join-Path -Path $DbatoolsData -ChildPath "DBA-MultiTool-$Branch"
        $minimumVersion = 11

        if ($Force -or -not(Test-Path -Path $localCachedCopy -PathType Container) -or $LocalFile) {
            # Force was passed, or we don't have a local copy, or $LocalFile was passed
            if (Test-Path $zipFile) {
                if ($PSCmdlet.ShouldProcess($zipFile, "File found, dropping $zipFile")) {
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                }
            }

            if ($LocalFile) {
                if (-not (Test-Path $LocalFile)) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "File does not exists, returning to prompt")) {
                        Stop-Function -Message "$LocalFile doesn't exist."
                        return
                    }
                }
                if (Test-Path $LocalFile -PathType Container) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "File is not a zip file, returning to prompt")) {
                        Stop-Function -Message "$LocalFile should be a zip file."
                        return
                    }
                }
                if (Test-Windows -NoWarn) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "Checking if Windows system, unblocking file")) {
                        Unblock-File $LocalFile -ErrorAction SilentlyContinue
                    }
                }
                if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $temp path")) {
                    Expand-Archive -Path $LocalFile -DestinationPath $temp -Force
                }
            } else {
                Write-Message -Level Verbose -Message "Downloading and unzipping the DBA MultiTool zip file."
                if ($PSCmdlet.ShouldProcess($url, "Downloading zip file")) {
                    try {
                        try {
                            Invoke-TlsWebRequest $url -OutFile $zipFile -ErrorAction Stop -UseBasicParsing
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            Invoke-TlsWebRequest $url -OutFile $zipFile -ErrorAction Stop -UseBasicParsing
                        }

                        # Unblock if there's a block
                        if (Test-Windows -NoWarn) {
                            Unblock-File $zipFile -ErrorAction SilentlyContinue
                        }

                        Expand-Archive -Path $zipFile -DestinationPath $temp -Force
                        Remove-Item -Path $zipFile
                    } catch {
                        Stop-Function -Message "Couldn't download the DBA MultiTool. Download and install manually from $url." -ErrorRecord $_
                        return
                    }
                }
            }

            ## Copy it into local area
            if ($PSCmdlet.ShouldProcess("LocalCachedCopy", "Copying extracted files to the local module cache")) {
                if (Test-Path -Path $localCachedCopy -PathType Container) {
                    Remove-Item -Path (Join-Path $localCachedCopy '*') -Recurse -ErrorAction SilentlyContinue
                } else {
                    $null = New-Item -Path $localCachedCopy -ItemType Container
                }
                Copy-Item -Path "$zipFolder\sp_*.sql" -Destination $localCachedCopy
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }
            if ($PSCmdlet.ShouldProcess($Database, "Installing DBA MultiTool procedures in $Database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating the DBA MultiTool stored procedures in $Database on $instance."
                $allProcedures_Query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0;"
                $allProcedures = ($server.Query($allProcedures_Query, $Database)).Name

                # Install/Update each stored procedure
                $sqlScripts = Get-ChildItem $localCachedCopy -Filter "sp_*.sql"
                foreach ($script in $sqlScripts) {
                    $scriptName = $script.Name
                    $scriptError = $false

                    $baseRes = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = $script.BaseName
                        Status       = $null
                    }
                    if ($server.VersionMajor -lt $minimumVersion) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2012, skipping $scriptName."
                        $baseRes.Status = 'Skipped'
                        $baseRes
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $Database")) {
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                        } catch {
                            Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_
                            $scriptError = $true
                        }

                        if ($scriptError) {
                            $baseRes.Status = 'Error'
                        } elseif ($script.BaseName -in $allProcedures) {
                            $baseRes.Status = 'Updated'
                        } else {
                            $baseRes.Status = 'Installed'
                        }
                        $baseRes
                    }
                }
            }
            Write-Message -Level Verbose -Message "Finished installing/updating DBA MultiTool stored procedures in $Database on $instance."
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUz7KRZJJnNZnsAGuVOoHWvbw0
# dNOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIgVW4g5bIeMhkMRUOnO8ly5c/rrMA0GCSqGSIb3DQEBAQUABIIBAI3SYRjg
# OBJLBDGFUODYag9uaG9BDDmoWYQKX298N6xIvBgHtMbjgxhcyqEvo8U3bDzswdJP
# yAmdfBY9sjNVC7znbJAgHHj8Vfl3LXuuSK/Q43NNGkK1bK0i5PMXj7NtLxFrMnJr
# Q6rwY3cFrr3P/n5aJ97LMEqkKHiX7TElgjP9m0jU+pd8/l1rWtHMbDEmDpGBFk0b
# yfuPKZ0whd7gp8p1zR560nGeT0pRgnA8L6NSO9smyFpNx2XhY94yo9BvJhqGWaLb
# FkSpyUBEAOY0+xL7d/ouEFeeKWywuIHJYQXWYunDVfn3fmu4CASaeLxo7K7Z8ixX
# ClM2UcBrUmIp7wOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzM1owLwYJKoZIhvcNAQkEMSIEIM6KnYYHNHapfhGGwZ9l7F4YPLHm
# ld3yxyZXzrzzDs33MA0GCSqGSIb3DQEBAQUABIIBALScwu5BbIRM98FIrgEFM4ci
# R/JZZDhhVYjj7KTIUmJHci/uV/A+0ct/skIj6SeUOb5nDsO5ePPObLUzmS1KBwz7
# BTg+7iTmp3IZ1KQPSAeMSsHHVxly2iPZNJUyCNh89nBj/8FrhPmfiTmB2Lbp9iHT
# 0MhZOIp00Eee8589s5cDQilxKzuSF8ICG1YYKb+6Lby0Uf/uFgdzf7l2k3QFXprM
# HnWVp69gxj0DaHym7Lj0EHRddJu8JCtk97vIYyj3bHRYZgJjnhy+w7134sfc1GEj
# /J5nVogXjdWYlcnplTttiFB9WAPIyNcxmIl7eibD9ZUBD4o3g/xkVgJJEnLxmMw=
# SIG # End signature block
