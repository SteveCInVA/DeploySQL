function Set-DbaCmConnection {
    <#
    .SYNOPSIS
        Configures a connection object for use in remote computer management.

    .DESCRIPTION
        Configures a connection object for use in remote computer management.
        This function will either create new records for computers that have no connection registered so far, or it will configure existing connections if already present.

        As such it can be handy in making bulk-edits on connections or manually adjusting some settings.

    .PARAMETER ComputerName
        The computer to build the connection object for.

    .PARAMETER Credential
        The credential to register.

    .PARAMETER UseWindowsCredentials
        Whether using the default windows credentials is legit.
        Not setting this will not exclude using windows credentials, but only not pre-confirm them as working.

    .PARAMETER OverrideExplicitCredential
        Setting this will enable the credential override.
        The override will cause the system to ignore explicitly specified credentials, so long as known, good credentials are available.

    .PARAMETER OverrideConnectionPolicy
        Setting this will configure the connection policy override.
        By default, global configurations enforce, which connection type is available at all and which is disabled.

    .PARAMETER DisabledConnectionTypes
        Explicitly disable connection types.
        These types will then not be used for connecting to the computer.

    .PARAMETER DisableBadCredentialCache
        Will prevent the caching of credentials if set to true.

    .PARAMETER DisableCimPersistence
        Will prevent Cim-Sessions to be reused.

    .PARAMETER DisableCredentialAutoRegister
        Will prevent working credentials from being automatically cached

    .PARAMETER EnableCredentialFailover
        Will enable automatic failing over to known to work credentials, when using bad credentials.
        By default, passing bad credentials will cause the Computer Management functions to interrupt with a warning (Or exception if in silent mode).

    .PARAMETER WindowsCredentialsAreBad
        Will prevent the windows credentials of the currently logged on user from being used for the remote connection.

    .PARAMETER CimWinRMOptions
        Specify a set of options to use when connecting to the target computer using CIM over WinRM.
        Use 'New-CimSessionOption' to create such an object.

    .PARAMETER CimDCOMOptions
        Specify a set of options to use when connecting to the target computer using CIM over DCOM.
        Use 'New-CimSessionOption' to create such an object.

    .PARAMETER AddBadCredential
        Adds credentials to the bad credential cache.
        These credentials will not be used when connecting to the target remote computer.

    .PARAMETER RemoveBadCredential
        Removes credentials from the bad credential cache.

    .PARAMETER ClearBadCredential
        Clears the cache of credentials that didn't worked.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ClearCredential
        Clears the cache of credentials that worked.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ResetCredential
        Resets all credential-related caches:
        - Clears bad credential cache
        - Removes last working credential
        - Un-Confirms the windows credentials as working
        - Un-Confirms the windows credentials as not working

        Automatically implies the parameters -ClearCredential and -ClearBadCredential. Using them together is redundant.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ResetConnectionStatus
        Restores all connection status to default, as if no connection protocol had ever been tested.

    .PARAMETER ResetConfiguration
        Restores the configuration back to system default.
        Configuration elements are the basic behavior controlling settings, such as whether to cache bad credentials, etc.
        These can be configured globally using the dbatools configuration system and overridden locally on a per-connection basis.
        For a list of all available settings, use "Get-DbatoolsConfig -Module ComputerManagement".

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaCmConnection

    .EXAMPLE
        PS C:\> Get-DbaCmConnection sql2014 | Set-DbaCmConnection -ClearBadCredential -UseWindowsCredentials

        Retrieves the already existing connection to sql2014, removes the list of not working credentials and configures it to default to the credentials of the logged on user.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection | Set-DbaCmConnection -RemoveBadCredential $cred

        Removes the credentials stored in $cred from all connections' list of "known to not work" credentials.
        Handy to update changes in privilege.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection | Export-Clixml .\connections.xml
        PS C:\> Import-Clixml .\connections.xml | Set-DbaCmConnection -ResetConfiguration

        At first, the current cached connections are stored in an xml file. At a later time - possibly in the profile when starting the console again - those connections are imported again and applied again to the connection cache.

        In this example, the configuration settings will also be reset, since after re-import those will be set to explicit, rather than deriving them from the global settings.
        In many cases, using the default settings is desirable. For specific settings, use New-DbaCmConnection as part of the profile in order to explicitly configure a connection.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Credential')]
    param (
        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Credential")]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Windows")]
        [switch]$UseWindowsCredentials,
        [switch]$OverrideExplicitCredential,
        [switch]$OverrideConnectionPolicy,
        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType]$DisabledConnectionTypes = 'None',
        [switch]$DisableBadCredentialCache,
        [switch]$DisableCimPersistence,
        [switch]$DisableCredentialAutoRegister,
        [switch]$EnableCredentialFailover,
        [Parameter(ParameterSetName = "Credential")]
        [switch]$WindowsCredentialsAreBad,
        [Microsoft.Management.Infrastructure.Options.WSManSessionOptions]$CimWinRMOptions,
        [Microsoft.Management.Infrastructure.Options.DComSessionOptions]$CimDCOMOptions,
        [System.Management.Automation.PSCredential[]]$AddBadCredential,
        [System.Management.Automation.PSCredential[]]$RemoveBadCredential,
        [switch]$ClearBadCredential,
        [switch]$ClearCredential,
        [switch]$ResetCredential,
        [switch]$ResetConnectionStatus,
        [switch]$ResetConfiguration,
        [switch]$EnableException
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting execution"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $disable_cache = Get-DbatoolsConfigValue -Name 'ComputerManagement.Cache.Disable.All' -Fallback $false
    }
    process {
        foreach ($connectionObject in $ComputerName) {
            if ($Pscmdlet.ShouldProcess($($connectionObject.Connection.ComputerName), "Setting Connection")) {
                if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue }
                Write-Message -Level VeryVerbose -Message "Processing computer: $($connectionObject.Connection.ComputerName)"

                $connection = $connectionObject.Connection

                if ($ResetConfiguration) {
                    Write-Message -Level Verbose -Message "Resetting the configuration to system default"

                    $connection.RestoreDefaultConfiguration()
                }

                if ($ResetConnectionStatus) {
                    Write-Message -Level Verbose -Message "Resetting the connection status"

                    $connection.CimRM = 'Unknown'
                    $connection.CimDCOM = 'Unknown'
                    $connection.Wmi = 'Unknown'
                    $connection.PowerShellRemoting = 'Unknown'

                    $connection.LastCimRM = New-Object System.DateTime(0)
                    $connection.LastCimDCOM = New-Object System.DateTime(0)
                    $connection.LastWmi = New-Object System.DateTime(0)
                    $connection.LastPowerShellRemoting = New-Object System.DateTime(0)
                }

                if ($ResetCredential) {
                    Write-Message -Level Verbose -Message "Resetting credentials"

                    $connection.KnownBadCredentials.Clear()
                    $connection.Credentials = $null
                    $connection.UseWindowsCredentials = $false
                    $connection.WindowsCredentialsAreBad = $false
                } else {
                    if ($ClearBadCredential) {
                        Write-Message -Level Verbose -Message "Clearing bad credentials"

                        $connection.KnownBadCredentials.Clear()
                        $connection.WindowsCredentialsAreBad = $false
                    }

                    if ($ClearCredential) {
                        Write-Message -Level Verbose -Message "Clearing credentials"

                        $connection.Credentials = $null
                        $connection.UseWindowsCredentials = $false
                    }
                }

                foreach ($badCred in $RemoveBadCredential) {
                    $connection.RemoveBadCredential($badCred)
                }

                foreach ($badCred in $AddBadCredential) {
                    $connection.AddBadCredential($badCred)
                }

                if (Test-Bound "Credential") { $connection.Credentials = $Credential }
                if ($UseWindowsCredentials) {
                    $connection.Credentials = $null
                    $connection.UseWindowsCredentials = $UseWindowsCredentials
                }
                if (Test-Bound "OverrideExplicitCredential") { $connection.OverrideExplicitCredential = $OverrideExplicitCredential }
                if (Test-Bound "DisabledConnectionTypes") { $connection.DisabledConnectionTypes = $DisabledConnectionTypes }
                if (Test-Bound "DisableBadCredentialCache") { $connection.DisableBadCredentialCache = $DisableBadCredentialCache }
                if (Test-Bound "DisableCimPersistence") { $connection.DisableCimPersistence = $DisableCimPersistence }
                if (Test-Bound "DisableCredentialAutoRegister") { $connection.DisableCredentialAutoRegister = $DisableCredentialAutoRegister }
                if (Test-Bound "EnableCredentialFailover") { $connection.DisableCredentialAutoRegister = $EnableCredentialFailover }
                if (Test-Bound "WindowsCredentialsAreBad") { $connection.WindowsCredentialsAreBad = $WindowsCredentialsAreBad }
                if (Test-Bound "CimWinRMOptions") { $connection.CimWinRMOptions = $CimWinRMOptions }
                if (Test-Bound "CimDCOMOptions") { $connection.CimDCOMOptions = $CimDCOMOptions }
                if (Test-Bound "OverrideConnectionPolicy") { $connection.OverrideConnectionPolicy = $OverrideConnectionPolicy }

                if (-not $disable_cache) {
                    Write-Message -Level Verbose -Message "Writing connection to cache"
                    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$connectionObject.Connection.ComputerName] = $connection
                } else { Write-Message -Level Verbose -Message "Skipping writing to cache, since the cache has been disabled." }
                $connection
            }
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Stopping execution"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUSHEfKLa0uVbBQ5lABmlCqfrY
# zxGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFI+l+H6NW0vSU97tW7/grgSxhg1GMA0GCSqGSIb3DQEBAQUABIIBAEkfXlDi
# BBFbzWItGYhQ604oisWF8GgXiE8FEcJ35Djx4qPvb1NyiTNpbfO5r6XZHOS6TT/o
# x1TVyUBrpGuxtbftxan6JMFs7K1KXPcPU3GrPyk+PtAf+vxbkDGSBqWf1tOTF/Tm
# bovOL4dYx9J5gXSHDT2oIzd2ksRBwkSUw1Su7CY4I7gsSOokl+BMe7L9paQSqKJW
# /xG9Mzp96a58ZKMXX2XE6aNtnn8pYg4iE2baIk9Fq+ujKB9jt+BM2Y4FCk0rfT3n
# ZKirPypJz5EoTfQOjTYIypMEA4uySdIl8/RJSQDrN1BT0Uw08ONB/wWi0aaAZmlS
# GrBqXXgjh13iTCqhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1NFowLwYJKoZIhvcNAQkEMSIEIFuc/atrdbEaYPndeWVThi3lxBm3
# fH5X3MIJ/A6deT5wMA0GCSqGSIb3DQEBAQUABIIBAIPCkeN1tSF6KLI48oIWbhbs
# Mwb7Yrspjudiz6EiCb98OWQV2CPjfOhBg+bXgEz1y76BEwSeMJ5jKRLjU9wciGp+
# YoTAP0vTnDjclb17opKndDc4a9dFo++NP6f1qL4Zhk8jsJ00v3wB1AWBMdlA75q2
# 9673Q1Qvzxfiempj7udfCfDBe1B/f6AvFXOjuyamj5QVacE+sVrf7Tk4W3PAuV9E
# EV1gG7YvEjC7W0ctKf5dZ+44LBhTpPRLELwYK+mS4BhbuNhXAog/PLaey5H0VBmO
# IEfb2e6k+LtXv9HP7+ADpapE/W4Xi0wUJoMwcjNNVBeX3PtdUWdgOTCzoQJNReQ=
# SIG # End signature block
