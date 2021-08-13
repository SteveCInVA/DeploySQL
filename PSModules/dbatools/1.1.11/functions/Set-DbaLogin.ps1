function Set-DbaLogin {
    <#
    .SYNOPSIS
        Set-DbaLogin makes it possible to make changes to one or more logins.
        SQL Azure DB is not supported.

    .DESCRIPTION
        Set-DbaLogin will enable you to change the password, unlock, rename, disable or enable, deny or grant login privileges to the login. It's also possible to add or remove server roles from the login.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The login that needs to be changed

    .PARAMETER SecurePassword
        The new password for the login This can be either a credential or a secure string.

    .PARAMETER DefaultDatabase
        Default database for the login

    .PARAMETER Unlock
        Switch to unlock an account. This can be used in conjunction with the -SecurePassword or -Force parameters.
        The default is false.

    .PARAMETER MustChange
        Does the user need to change his/her password. This will only be used in conjunction with the -SecurePassword parameter.
        It is required that the login have both PasswordPolicyEnforced (check_policy) and PasswordExpirationEnabled (check_expiration) enabled for the login. See the Microsoft documentation for ALTER LOGIN for more details.
        The default is false.

    .PARAMETER NewName
        The new name for the login.

    .PARAMETER Disable
        Disable the login

    .PARAMETER Enable
        Enable the login

    .PARAMETER DenyLogin
        Deny access to SQL Server

    .PARAMETER GrantLogin
        Grant access to SQL Server

    .PARAMETER PasswordPolicyEnforced
        Enable the password policy on the login (check_policy = ON). This option must be enabled in order for -PasswordExpirationEnabled to be used.

    .PARAMETER PasswordExpirationEnabled
        Enable the password expiration check on the login (check_expiration = ON). In order to enable this option the PasswordPolicyEnforced (check_policy) must also be enabled for the login.

    .PARAMETER AddRole
        Add one or more server roles to the login
        The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER RemoveRole
        Remove one or more server roles to the login
        The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER InputObject
        Allows logins to be piped in from Get-DbaLogin

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        This switch is used with -Unlock to unlock a login without providing a password. This command will temporarily disable and enable the policy settings as described at https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaLogin

    .EXAMPLE
        PS C:\> $SecurePassword = ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force
        PS C:\> $cred = New-Object System.Management.Automation.PSCredential ("username", $SecurePassword)
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -SecurePassword $cred -Unlock -MustChange

        Set the new password for login1 using a credential, unlock the account and set the option
        that the user must change password at next logon.

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Enable

        Enable the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1, login2, login3, login4 -Enable

        Enable multiple logins

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1, sql2, sql3 -Login login1, login2, login3, login4 -Enable

        Enable multiple logins on multiple instances

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Disable

        Disable the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -DenyLogin

        Deny the login to connect to the instance

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -GrantLogin

        Grant the login to connect to the instance

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced

        Enforces the password policy on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced:$false

        Disables enforcement of the password policy on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login test -AddRole serveradmin

        Add the server role "serveradmin" to the login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login test -RemoveRole bulkadmin

        Remove the server role "bulkadmin" to the login

    .EXAMPLE
        PS C:\> $login = Get-DbaLogin -SqlInstance sql1 -Login test
        PS C:\> $login | Set-DbaLogin -Disable

        Disable the login from the pipeline

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -DefaultDatabase master

        Set the default database to master on a login

    .EXAMPLE
        PS C:\> Set-DbaLogin -SqlInstance sql1 -Login login1 -Unlock -Force

        Unlocks the login1 on the sql1 instance using the technique described at https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter Password")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [Alias("Password")]
        [object]$SecurePassword, #object so that it can accept credential or securestring
        [Alias("DefaultDB")]
        [string]$DefaultDatabase,
        [switch]$Unlock,
        [switch]$MustChange,
        [string]$NewName,
        [switch]$Disable,
        [switch]$Enable,
        [switch]$DenyLogin,
        [switch]$GrantLogin,
        [switch]$PasswordPolicyEnforced,
        [switch]$PasswordExpirationEnabled,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$AddRole,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$RemoveRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        # Check the parameters
        if ((Test-Bound -ParameterName 'SqlInstance') -and (Test-Bound -ParameterName 'Login' -Not)) {
            Stop-Function -Message 'You must specify a Login when using SqlInstance'
        }

        if ((Test-Bound -ParameterName 'NewName') -and $Login -eq $NewName) {
            Stop-Function -Message 'Login name is the same as the value in -NewName' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'Disable') -and (Test-Bound -ParameterName 'Enable')) {
            Stop-Function -Message 'You cannot use both -Enable and -Disable together' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'GrantLogin') -and (Test-Bound -ParameterName 'DenyLogin')) {
            Stop-Function -Message 'You cannot use both -GrantLogin and -DenyLogin together' -Target $Login -Continue
        }

        if (Test-bound -ParameterName 'SecurePassword') {
            switch ($SecurePassword.GetType().Name) {
                'PSCredential' { $NewSecurePassword = $SecurePassword.Password }
                'SecureString' { $NewSecurePassword = $SecurePassword }
                default {
                    Stop-Function -Message 'Password must be a PSCredential or SecureString' -Target $Login
                }
            }
        }

        if ((Test-Bound Unlock) -and (Test-Bound SecurePassword -Not) -and (Test-Bound Force -Not)) {
            Stop-Function -Message 'You must specify a password when using the -Unlock parameter or use the -Force parameter. See the help documentation for this command.'
        }

        if ((Test-Bound MustChange) -and (Test-Bound SecurePassword -Not)) {
            Stop-Function -Message 'You must specify a password when using the -MustChange parameter. See the command help for more details.'
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $allLogins = @{ }
        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -AzureUnsupported
            } catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $allLogins[$instance.ToString()] = Get-DbaLogin -SqlInstance $server
            $InputObject += $allLogins[$instance.ToString()] | Where-Object { ($_.Name -in $Login) -and ($_.Name -notlike '##*') }
        }

        # Loop through all the logins
        foreach ($l in $InputObject) {
            if ($Pscmdlet.ShouldProcess($l, "Setting Changes to Login on $($server.name)")) {
                $server = $l.Parent

                # Create the notes
                $notes = @()

                # caller wants to unlock a login without a password and has specified the -Force param
                if ((Test-Bound Unlock) -and (Test-Bound SecurePassword -Not) -and (Test-Bound Force)) {
                    if (-not $l.IsLocked) {
                        Write-Message -Message "Login $l is not locked" -Level Warning
                    } else {
                        try {
                            # save the current state of the policy options for check_policy and check_expiration
                            $checkPolicy = $l.PasswordPolicyEnforced
                            $checkExpiration = $l.PasswordExpirationEnabled

                            # alter the login to switch off the check_policy and check_expiration. Ref: https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/
                            $l.PasswordPolicyEnforced = $false
                            $l.PasswordExpirationEnabled = $false
                            $l.Alter()

                            # restore the settings immediately
                            $l.PasswordPolicyEnforced = $checkPolicy
                            $l.PasswordExpirationEnabled = $checkExpiration
                            $l.Alter()

                            # out of an abundance of caution let's refresh the login and double check the settings to see if they match what they were before
                            $l.Refresh()

                            if ($checkPolicy -ne $l.PasswordPolicyEnforced) {
                                Stop-Function -Message "Unable to restore the check_policy setting for $l" -Target $l -Continue
                            }

                            if ($checkExpiration -ne $l.PasswordExpirationEnabled) {
                                Stop-Function -Message "Unable to restore the check_expiration setting for $l" -Target $l -Continue
                            }
                        } catch {
                            $notes += "Unable to unlock"
                            Stop-Function -Message "Unable to unlock $l. Review the 'Enforce password policy' and 'Enforce password expiration' settings for $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Change the name
                if (Test-Bound -ParameterName 'NewName') {
                    # Check if the new name doesn't already exist
                    if ($allLogins[$server.Name].Name -notcontains $NewName) {
                        try {
                            $l.Rename($NewName)
                        } catch {
                            $notes += "Couldn't rename login"
                            Stop-Function -Message "Something went wrong changing the name for $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    } else {
                        $notes += 'New login name already exists'
                        Write-Message -Message "New login name $NewName already exists on $instance" -Level Verbose
                    }
                }

                # Disable the login
                if (Test-Bound -ParameterName 'Disable') {
                    if ($l.IsDisabled) {
                        Write-Message -Message "Login $l is already disabled" -Level Verbose
                    } else {
                        try {
                            $l.Disable()
                        } catch {
                            $notes += "Couldn't disable login"
                            Stop-Function -Message "Something went wrong disabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Enable the login
                if (Test-Bound -ParameterName 'Enable') {
                    if (-not $l.IsDisabled) {
                        Write-Message -Message "Login $l is already enabled" -Level Verbose
                    } else {
                        try {
                            $l.Enable()
                        } catch {
                            $notes += "Couldn't enable login"
                            Stop-Function -Message "Something went wrong enabling $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Deny access
                if (Test-Bound -ParameterName 'DenyLogin') {
                    if ($l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access denied" -Level Verbose
                    } else {
                        $l.DenyWindowsLogin = $true
                    }
                }

                # Grant access
                if (Test-Bound -ParameterName 'GrantLogin') {
                    if (-not $l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access granted" -Level Verbose
                    } else {
                        $l.DenyWindowsLogin = $false
                    }
                }

                # Enforce password policy
                if (Test-Bound -ParameterName 'PasswordPolicyEnforced') {
                    if ($l.PasswordPolicyEnforced -eq $PasswordPolicyEnforced) {
                        Write-Message -Message "Login $l password policy is already set to $($l.PasswordPolicyEnforced)" -Level Verbose
                    } else {
                        $l.PasswordPolicyEnforced = $PasswordPolicyEnforced
                    }
                }

                # Enforce password expiration
                if (Test-Bound -ParameterName 'PasswordExpirationEnabled') {

                    if ($PasswordExpirationEnabled -and $l.PasswordPolicyEnforced -eq $false) {
                        $notes += "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings."
                        Stop-Function -Message "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings." -Target $l -Continue
                    }

                    if ($l.PasswordExpirationEnabled -eq $PasswordExpirationEnabled) {
                        Write-Message -Message "Login $l password expiration check is already set to $($l.PasswordExpirationEnabled)" -Level Verbose
                    } else {
                        $l.PasswordExpirationEnabled = $PasswordExpirationEnabled
                    }
                }

                # Add server roles to login
                if ($AddRole) {
                    # Loop through each of the roles
                    foreach ($role in $AddRole) {
                        try {
                            $l.AddToRole($role)
                        } catch {
                            $notes += "Couldn't add role $role"
                            Stop-Function -Message "Something went wrong adding role $role to $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Remove server roles from login
                if ($RemoveRole) {
                    # Loop through each of the roles
                    foreach ($role in $RemoveRole) {
                        try {
                            $server.Roles[$role].DropMember($l.Name)
                        } catch {
                            $notes += "Couldn't remove role $role"
                            Stop-Function -Message "Something went wrong removing role $role to $l" -Target $l -ErrorRecord $_ -Continue
                        }
                    }
                }

                # Set the default database
                if (Test-Bound -ParameterName 'DefaultDatabase') {
                    if ($l.DefaultDatabase -eq $DefaultDatabase) {
                        Write-Message -Message "Login $l default database is already set to $($l.DefaultDatabase)" -Level Verbose
                    } else {
                        $l.DefaultDatabase = $DefaultDatabase
                    }
                }

                # Alter the login to make the changes
                $l.Alter()
                $l.Refresh()

                # Change the password after the Alter() because the must_change requires the policy settings to be enabled first.
                if (Test-bound -ParameterName 'SecurePassword') {
                    if (Test-Bound MustChange) {
                        # Validate if the check_policy and check_expiration options are enabled on the login. These are required for the must_change option for alter login.
                        if ((-not $l.PasswordPolicyEnforced) -or (-not $l.PasswordExpirationEnabled)) {
                            Stop-Function -Message "Unable to change the password and set the must_change option for $l because check_policy = $($l.PasswordPolicyEnforced) and check_expiration = $($l.PasswordExpirationEnabled). See the command help for additional information on the -MustChange parameter." -Target $l -Continue
                        }
                    }

                    try {
                        $l.ChangePassword($NewSecurePassword, $Unlock, $MustChange)
                        $passwordChanged = $true

                        if (Test-Bound MustChange) {
                            $l.Refresh()  # necessary so that the read only property MustChangePassword is updated
                        }
                    } catch {
                        $notes += "Couldn't change password"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }

                # Retrieve the server roles for the login
                $roles = Get-DbaServerRoleMember -SqlInstance $server | Where-Object { $_.Name -eq $l.Name }

                # Check if there were any notes to include in the results
                if ($notes) {
                    $notes = $notes | Get-Unique
                    $notes = $notes -Join ';'
                } else {
                    $notes = $null
                }
                $rolenames = $roles.Role | Select-Object -Unique

                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name PasswordChanged -Value $passwordChanged
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ServerRole -Value ($rolenames -join ', ')
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name Notes -Value $notes

                # backwards compatibility: LoginName, DenyLogin
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name LoginName -Value $l.Name
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name DenyLogin -Value $l.DenyWindowsLogin

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'LoginName', 'DenyLogin', 'IsDisabled', 'IsLocked',
                'PasswordPolicyEnforced', 'PasswordExpirationEnabled', 'MustChangePassword', 'PasswordChanged', 'ServerRole', 'Notes'

                Select-DefaultView -InputObject $l -Property $defaults
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPIwYpCsDbKqV28mc4goKNBDx
# HTWgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFMq3QzXCXs6ovBsDGjW2gLzmhl5GMA0GCSqGSIb3DQEBAQUABIIBAEH7JTWN
# 64izsvBSFvNqlW0aQPFUi1JkwXhkB29YPZkOvTo14kSMrohR8nnySy8KfBAlu0v7
# +n4NfO6FktaArxbc5HDuZ8RrxzyhEGasNuyZ/DyqNHCJDelVQ2hf4TPasLxn7VeJ
# KM57mAHKm2n7YBjC4OCGhCx6FXyJkQU7GX8SmmKl3POjtPZOj96JEDpyZE9Arhe/
# Bczxc2n2lQMiiPwhqqCHfFJds8oi35Gp8saTOilzmCrI3n8FYldDhAkwPNpKOB3d
# iSAONoNi6rVUqFz2NY3Me47l7bs7aNzgh2faYHEtts9TmCWbXGR0WRGqAayUFeqL
# y5URNi599/DB2eGhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1NlowLwYJKoZIhvcNAQkEMSIEIJta9TlrC5wRrpYQrZCENclApIQh
# IY8KU+5KSIeOhq3UMA0GCSqGSIb3DQEBAQUABIIBAHemEohcWusAktAff3RKYgAt
# PudgBku0ZwC+ohM49xOgqfWrggV/VqF69WHehwmy7fIArsGd+0OoprBS28IAk7f4
# /6+Xk9cwO29nlIWoynE5nnTj7zllLaA/bsOdC29CogH5FMb9WZf/wIvIGjPg112h
# dQjsRwNWtXlXOM3IvOh+e/SsMViOP5fLmh7OSwXqXzoTQmbXZBlhJKATSz29wZCN
# xpxRrVDgfw4e7dB1+aj35ai+NRmKoPYRge8w1LTaXbJOQPoalO6immlq5b2gXe5c
# 44mTwi8jOvWEvQJnLLd3KR9zN03U+I0LgjAeMoLyqqpk8+/c04/3OYbbKw8HEQg=
# SIG # End signature block
