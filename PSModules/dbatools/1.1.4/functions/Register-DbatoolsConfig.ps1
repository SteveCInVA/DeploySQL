function Register-DbatoolsConfig {
    <#
    .SYNOPSIS
        Registers an existing configuration object in registry.

    .DESCRIPTION
        Registers an existing configuration object in registry.
        This allows simple persisting of settings across powershell consoles.
        It also can be used to generate a registry template, which can then be used to create policies.

    .PARAMETER Config
        The configuration object to write to registry.
        Can be retrieved using Get-DbatoolsConfig.

    .PARAMETER FullName
        The full name of the setting to be written to registry.

    .PARAMETER Module
        The name of the module, whose settings should be written to registry.

    .PARAMETER Name
        Default: "*"
        Used in conjunction with the -Module parameter to restrict the number of configuration items written to registry.

    .PARAMETER Scope
        Default: UserDefault
        Who will be affected by this export how? Current user or all? Default setting or enforced?
        Legal values: UserDefault, UserMandatory, SystemDefault, SystemMandatory

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Register-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig message.style.* | Register-DbatoolsConfig

        Retrieves all configuration items that that start with message.style. and registers them in registry for the current user.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -FullName "message.consoleoutput.disable" -Scope SystemDefault

        Retrieves the configuration item "message.consoleoutput.disable" and registers it in registry as the default setting for all users on this machine.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -Module Message -Scope SystemMandatory

        Retrieves all configuration items of the module Message, then registers them in registry to enforce them for all users on the current system.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $Config,

        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [string[]]
        $FullName,

        [Parameter(Mandatory = $true, ParameterSetName = "Name", Position = 0)]
        [string]
        $Module,

        [Parameter(ParameterSetName = "Name", Position = 1)]
        [string]
        $Name = "*",

        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope = "UserDefault",

        [switch]$EnableException
    )

    begin {
        if ($script:NoRegistry -and ($Scope -band 14)) {
            Stop-Function -Message "Cannot register configurations on non-windows machines to registry. Please specify a file-based scope" -Tag 'NotSupported' -Category NotImplemented
            return
        }

        # Linux and MAC default to local user store file
        if ($script:NoRegistry -and ($Scope -eq "UserDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileUserLocal
        }
        # Linux and MAC get redirection for SystemDefault to FileSystem
        if ($script:NoRegistry -and ($Scope -eq "SystemDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileSystem
        }

        $parSet = $PSCmdlet.ParameterSetName

        function Write-Config {
            [CmdletBinding()]
            Param (
                [Sqlcollaborative.Dbatools.Configuration.Config]
                $Config,

                [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
                $Scope,

                [bool]
                $EnableException,

                [string]
                $FunctionName = (Get-PSCallStack)[0].Command
            )

            if (-not $Config -or ($Config.RegistryData -eq "<type not supported>")) {
                Stop-Function -Message "Invalid Input, cannot export $($Config.FullName), type not supported" -EnableException $EnableException -Category InvalidArgument -Tag "config", "fail" -Target $Config -FunctionName $FunctionName
                return
            }

            try {
                Write-Message -Level Verbose -Message "Registering $($Config.FullName) for $Scope" -Tag "Config" -Target $Config -FunctionName $FunctionName
                #region User Default
                if (1 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Default

                #region User Mandatory
                if (2 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Mandatory

                #region System Default
                if (4 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Default

                #region System Mandatory
                if (8 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Mandatory
            } catch {
                Stop-Function -Message "Failed to export $($Config.FullName), to scope $Scope" -EnableException $EnableException -Tag "config", "fail" -Target $Config -ErrorRecord $_ -FunctionName $FunctionName
                return
            }
        }

        function Ensure-RegistryPath {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
            [CmdletBinding()]
            Param (
                [string]
                $Path
            )

            if (-not (Test-Path $Path)) {
                $null = New-Item $Path -Force
            }
        }

        # For file based persistence
        $configurationItems = @()
    }
    process {
        if (Test-FunctionInterrupt) { return }

        #region Registry Based
        if ($Scope -band 15) {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }

                    foreach ($item in $FullName) {
                        if ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant())) {
                            Write-Config -Config ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]) -Scope $Scope -EnableException $EnableException
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }
                }
            }
        }
        #endregion Registry Based

        #region File Based
        else {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }

                    foreach ($item in $FullName) {
                        if (($configurationItems.FullName -notcontains $item) -and ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant()))) {
                            $configurationItems += [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }
                }
            }
        }
        #endregion File Based
    }
    end {
        if (Test-FunctionInterrupt) { return }

        #region Finish File Based Persistence
        if ($Scope -band 16) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserLocal "psf_config.json")
        }
        if ($Scope -band 32) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserShared "psf_config.json")
        }
        if ($Scope -band 64) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileSystem "psf_config.json")
        }
        #endregion Finish File Based Persistence
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULl6G3I1+nLNqU1BVfgE1ZV/c
# U4ygghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFEALyQr8pJF//8HDPhkbCv7bJBAlMA0GCSqGSIb3DQEBAQUABIIBAEudTyI+
# S8O2qO620BVpXHLMgN72C+9NNIExfQg8XifE34zGmjT8ld2CFEf7W1gguW3K0Ich
# gITtIcrJRAhqrbPtrHJoKzo8TVUgscBwJXDEsUjD437qeu06r27FvIBIgvfGyZxB
# +XMi6iblFUR+VNyfTjq3F5TaqqXFMLUf7Ihv4ALgqLEOQ+e58qNtVO2siegvLwPh
# 5+/XtiVeWS43h/cAt7XCsMT3Hm1cj80wFUR3i7Pmqb3iLoBQnRrjGa0IddQX15HJ
# vkB6C5TGkboctDMkEJDNfUCokBlh4wS64Pn5cXE3zSRizS18XQVEW9gtzwnsbHiC
# X47Bk/4ZUazoELuhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1OVowLwYJKoZIhvcNAQkEMSIEICSGi0xf0+CHCKyBvfy2sOD4sRgK
# M3qiO1vWDg8AsyqtMA0GCSqGSIb3DQEBAQUABIIBAEnKwWgQByYkBYU+Ds6bCuhG
# yS7ll65kwoXpUFEriTfig281PO/MWk0p7Eh5w+oAfSypXpYK8q3EaRTTSyUEN/5/
# K9Y2zBGcNMB44IYvL3BbDIqwf8Y7WayVWMRT8RQwCwWbG6fcC4AVDzOotFnEj8iH
# 1hnN0QyNd65U25QgKfzEnsllzMkS2psDNvOek1EmzPtUw1jlLY96IwiVghbAtRtg
# UQWAkq8DcRBTqzD6kfubrnZFn6iwFuCyWS1ENDOHJH8hmA0hOUzSuzdt8GQoVXrG
# NItjP2zEq2TF1nn0t9vdAOK8WFIq6Xv80bufmbn39pqZE0JWx7UdjRI+dfE5yas=
# SIG # End signature block
