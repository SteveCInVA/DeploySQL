function New-DbaLogin {
    <#
    .SYNOPSIS
        Creates a new SQL Server login

    .DESCRIPTION
        Creates a new SQL Server login with provided specifications

    .PARAMETER SqlInstance
        The target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The Login name(s)

    .PARAMETER SecurePassword
        Secure string used to authenticate the Login

    .PARAMETER HashedPassword
        Hashed password string used to authenticate the Login

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER LoginRenameHashtable
        Pass a hash table into this parameter to change login names when piping objects into the procedure

    .PARAMETER MapToCertificate
        Map the login to a certificate

    .PARAMETER MapToAsymmetricKey
        Map the login to an asymmetric key

    .PARAMETER MapToCredential
        Map the login to a credential

    .PARAMETER Sid
        Provide an explicit Sid that should be used when creating the account. Can be [byte[]] or hex [string] ('0xFFFF...')

    .PARAMETER DefaultDatabase
        Default database for the login

    .PARAMETER Language
        Login's default language

    .PARAMETER PasswordExpirationEnabled
        Enforces password expiration policy. Requires PasswordPolicyEnforced to be enabled. Can be $true or $false(default)

    .PARAMETER PasswordPolicyEnforced
        Enforces password complexity policy. Can be $true or $false(default)

    .PARAMETER PasswordMustChange
        Enforces user must change password at next login.
        When specified will enforce PasswordExpirationEnabled and PasswordPolicyEnforced as they are required for the must change.

    .PARAMETER Disabled
        Create the login in a disabled state

    .PARAMETER DenyWindowsLogin
        Create the login and deny Windows login ability

    .PARAMETER NewSid
        Ignore sids from the piped login object to generate new sids on the server. Useful when copying login onto the same server

    .PARAMETER Force
        If login exists, drop and recreate

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaLogin

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance Server1,Server2 -Login Newlogin

        You will be prompted to securely enter the password for a login [Newlogin]. The login would be created on servers Server1 and Server2 with default parameters.

    .EXAMPLE
        PS C:\> $securePassword = Read-Host "Input password" -AsSecureString
        PS C:\> New-DbaLogin -SqlInstance Server1\sql1 -Login Newlogin -SecurePassword $securePassword -PasswordPolicyEnforced -PasswordExpirationEnabled

        Creates a login on Server1\sql1 with a predefined password. The login will have password and expiration policies enforced onto it.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql1 -Login Oldlogin | New-DbaLogin -SqlInstance sql1 -LoginRenameHashtable @{Oldlogin = 'Newlogin'} -Force -NewSid -Disabled:$false

        Copies a login [Oldlogin] to the same instance sql1 with the same parameters (including password). New login will have a new sid, a new name [Newlogin] and will not be disabled. Existing login [Newlogin] will be removed prior to creation.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql1 -Login Login1,Login2 | New-DbaLogin -SqlInstance sql2 -PasswordPolicyEnforced -PasswordExpirationEnabled -DefaultDatabase tempdb -Disabled

        Copies logins [Login1] and [Login2] from instance sql1 to instance sql2, but enforces password and expiration policies for the new logins. New logins will also have a default database set to [tempdb] and will be created in a disabled state.

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance sql1 -Login domain\user

        Creates a new Windows Authentication backed login on sql1. The login will be part of the public server role.

    .EXAMPLE
        PS C:\> New-DbaLogin -SqlInstance sql1 -Login domain\user1, domain\user2 -DenyWindowsLogin

        Creates two new Windows Authentication backed login on sql1. The logins would be denied from logging in.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Password", ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters Password and MapToCredential")]
    param (
        [parameter(Mandatory, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Name", "LoginName")]
        [parameter(ParameterSetName = "Password", Position = 2)]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string[]]$Login,
        [parameter(ValueFromPipeline)]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [parameter(ParameterSetName = "MapToCertificate")]
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [object[]]$InputObject,
        [Alias("Rename")]
        [hashtable]$LoginRenameHashtable,
        [parameter(ParameterSetName = "Password", Position = 3)]
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [Alias("Hash", "PasswordHash")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$HashedPassword,
        [parameter(ParameterSetName = "MapToCertificate")]
        [string]$MapToCertificate,
        [parameter(ParameterSetName = "MapToAsymmetricKey")]
        [string]$MapToAsymmetricKey,
        [string]$MapToCredential,
        [object]$Sid,
        [Alias("DefaultDB")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$DefaultDatabase,
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [string]$Language,
        [Alias("Expiration", "CheckExpiration")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordExpirationEnabled,
        [Alias("Policy", "CheckPolicy")]
        [parameter(ParameterSetName = "Password")]
        [parameter(ParameterSetName = "PasswordHash")]
        [switch]$PasswordPolicyEnforced,
        [Alias("MustChange")]
        [parameter(ParameterSetName = "Password")]
        [switch]$PasswordMustChange,
        [Alias("Disable")]
        [switch]$Disabled,
        [switch]$DenyWindowsLogin,
        [switch]$NewSid,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Sid) {
            if ($Sid.GetType().Name -ne 'Byte[]') {
                foreach ($symbol in $Sid.TrimStart("0x").ToCharArray()) {
                    if ($symbol -notin "0123456789ABCDEF".ToCharArray()) {
                        Stop-Function -Message "Sid has invalid character '$symbol', cannot proceed." -Category InvalidArgument -EnableException $EnableException
                        return
                    }
                }
                $Sid = Convert-HexStringToByte $Sid
            }
        }

        if ($HashedPassword) {
            if ($HashedPassword.GetType().Name -eq 'Byte[]') {
                $HashedPassword = Convert-ByteToHexString $HashedPassword
            }
        }
    }

    process {
        #At least one of those should be specified
        if (!($Login -or $InputObject)) {
            Stop-Function -Message "No logins have been specified." -Category InvalidArgument -EnableException $EnableException
            Return
        }

        if ($PasswordMustChange -and (-not $SecurePassword)) {
            Stop-Function -Message "You need to specified -SecurePassword when using -PasswordMustChange parameter." -Category InvalidArgument -EnableException $EnableException
            Return
        }

        $loginCollection = @()
        if ($InputObject) {
            $loginCollection += $InputObject
            if ($Login) {
                Stop-Function -Message "Parameter -Login is not supported when processing objects from -InputObject. If you need to rename the logins, please use -LoginRenameHashtable." -Category InvalidArgument -EnableException $EnableException
                Return
            }
        } else {
            $loginCollection += $Login
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($loginItem in $loginCollection) {
                $usedTsql = $false
                #check if $loginItem is an SMO Login object
                if ($loginItem.GetType().Name -eq 'Login') {
                    #Get all the necessary fields
                    $loginName = $loginItem.Name
                    $loginType = $loginItem.LoginType
                    $currentSid = $loginItem.Sid
                    $currentDefaultDatabase = $loginItem.DefaultDatabase
                    $currentLanguage = $loginItem.Language
                    $currentPasswordExpirationEnabled = $loginItem.PasswordExpirationEnabled
                    $currentPasswordPolicyEnforced = $loginItem.PasswordPolicyEnforced
                    $currentPasswordMustChange = $loginItem.MustChangePassword
                    $currentDisabled = $loginItem.IsDisabled
                    $currentDenyWindowsLogin = $loginItem.DenyWindowsLogin
                    #Get previous password
                    if ($loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                        $sourceServer = $loginItem.Parent
                        switch ($sourceServer.versionMajor) {
                            0 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$loginName'" }
                            8 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM dbo.syslogins WHERE name='$loginName'" }
                            9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins where name='$loginName'" }
                            default {
                                $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
                                    AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass
                                    FROM sys.server_principals
                                    WHERE principal_id = $($loginItem.id)"
                            }
                        }

                        try {
                            $hashedPass = $sourceServer.ConnectionContext.ExecuteScalar($sql)
                        } catch {
                            $hashedPassDt = $sourceServer.Databases['master'].ExecuteWithResults($sql)
                            $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                        }

                        if ($hashedPass.GetType().Name -ne "String") {
                            $hashedPass = Convert-ByteToHexString $hashedPass
                        }
                        $currentHashedPassword = $hashedPass
                    }

                    #Get cryptography and attached credentials
                    if ($loginType -eq 'AsymmetricKey') {
                        $currentAsymmetricKey = $loginItem.AsymmetricKey
                    }
                    if ($loginType -eq 'Certificate') {
                        $currentCertificate = $loginItem.Certificate
                    }
                    #This method or property is accessible only while working with SQL Server 2008 or later.
                    if ($sourceServer.versionMajor -gt 9) {
                        if ($loginItem.EnumCredentials()) {
                            $currentCredential = $loginItem.EnumCredentials()
                        }
                    }
                } else {
                    $loginName = $loginItem
                    $currentSid = $currentDefaultDatabase = $currentLanguage = $currentPasswordExpirationEnabled = $currentAsymmetricKey = $currentCertificate = $currentCredential = $currentDisabled = $currentPasswordPolicyEnforced = $currentDenyWindowsLogin = $null

                    if ($PsCmdlet.ParameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
                    elseif ($PsCmdlet.ParameterSetName -eq "MapToAsymmetricKey") { $loginType = 'AsymmetricKey' }
                    elseif ($loginItem.IndexOf('\') -eq -1) { $loginType = 'SqlLogin' }
                    else { $loginType = 'WindowsUser' }
                }

                if ((-not $server.IsAzure) -and ($server.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($loginType -eq 'SqlLogin')) {
                    Write-Message -Level Warning -Message "$instance does not have Mixed Mode enabled. [$loginName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
                }

                if ($Sid) {
                    $currentSid = $Sid
                }
                if ($DefaultDatabase) {
                    $currentDefaultDatabase = $DefaultDatabase
                }
                if ($Language) {
                    $currentLanguage = $Language
                }
                if ($PSBoundParameters.Keys -contains 'PasswordExpirationEnabled') {
                    $currentPasswordExpirationEnabled = $PasswordExpirationEnabled
                }
                if ($PSBoundParameters.Keys -contains 'PasswordPolicyEnforced') {
                    $currentPasswordPolicyEnforced = $PasswordPolicyEnforced
                }
                if ($PSBoundParameters.Keys -contains 'PasswordMustChange') {
                    $currentPasswordMustChange = $PasswordMustChange
                    # Enforce Expiration and Policy properties as they are needed when we want to use "Must Change" property
                    Write-Message -Level Verbose -Message "Forcing 'Expiration' and 'Policy' properties to 'ON' because MustChange was specified."
                    $currentPasswordExpirationEnabled = $true
                    $currentPasswordPolicyEnforced = $true
                }
                if ($PSBoundParameters.Keys -contains 'MapToAsymmetricKey') {
                    $currentAsymmetricKey = $MapToAsymmetricKey
                }
                if ($PSBoundParameters.Keys -contains 'MapToCertificate') {
                    $currentCertificate = $MapToCertificate
                }
                if ($PSBoundParameters.Keys -contains 'MapToCredential') {
                    $currentCredential = $MapToCredential
                }
                if ($PSBoundParameters.Keys -contains 'Disabled') {
                    $currentDisabled = $Disabled
                }
                if (Test-Bound -Parameter DenyWindowsLogin) {
                    $currentDenyWindowsLogin = $DenyWindowsLogin
                }

                #Apply renaming if necessary
                if ($LoginRenameHashtable.Keys -contains $loginName) {
                    $loginName = $LoginRenameHashtable[$loginName]
                }

                #Requesting password if required
                if ($loginItem.GetType().Name -ne 'Login' -and $loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                    $SecurePassword = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
                }

                #verify if login exists on the server
                if (($existingLogin = $server.Logins[$loginName])) {
                    if ($force) {
                        if ($Pscmdlet.ShouldProcess($existingLogin, "Dropping existing login $loginName on $instance because -Force was used")) {
                            try {
                                $existingLogin.Drop()
                            } catch {
                                Stop-Function -Message "Could not remove existing login $loginName on $instance, skipping." -Target $loginName -Continue
                            }
                        }
                    } else {
                        Stop-Function -Message "Login $loginName already exists on $instance and -Force was not specified" -Target $loginName -Continue
                    }
                }


                if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
                    try {
                        $loginName = $loginName.Replace('[', '').Replace(']', '')
                        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
                        $newLogin.LoginType = $loginType

                        $withParams = ""

                        if ($loginType -eq 'SqlLogin' -and $currentSid -and !$NewSid) {
                            Write-Message -Level Verbose -Message "Setting $loginName SID"
                            $withParams += ", SID = " + (Convert-ByteToHexString $currentSid)
                            $newLogin.Set_Sid($currentSid)
                        }

                        if ($loginType -in ("WindowsUser", "WindowsGroup", "SqlLogin")) {
                            if ($currentDefaultDatabase) {
                                Write-Message -Level Verbose -Message "Setting $loginName default database to $currentDefaultDatabase"
                                $withParams += ", DEFAULT_DATABASE = [$currentDefaultDatabase]"
                                $newLogin.DefaultDatabase = $currentDefaultDatabase
                            }

                            if ($currentLanguage) {
                                Write-Message -Level Verbose -Message "Setting $loginName language to $currentLanguage"
                                $withParams += ", DEFAULT_LANGUAGE = [$currentLanguage]"
                                $newLogin.Language = $currentLanguage
                            }

                            #CHECK_EXPIRATION: default - OFF
                            if ($currentPasswordExpirationEnabled) {
                                $withParams += ", CHECK_EXPIRATION = ON"
                                $newLogin.PasswordExpirationEnabled = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_EXPIRATION = OFF"
                                $newLogin.PasswordExpirationEnabled = $false
                            }

                            #CHECK_POLICY: default - ON
                            if ($currentPasswordPolicyEnforced) {
                                $withParams += ", CHECK_POLICY = ON"
                                $newLogin.PasswordPolicyEnforced = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_POLICY = OFF"
                                $newLogin.PasswordPolicyEnforced = $false
                            }

                            # DENY CONNECT SQL
                            if ($currentDenyWindowsLogin) {
                                Write-Message -Level VeryVerbose -Message "Setting $loginName DenyWindowsLogin to $currentDenyWindowsLogin"
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                            }

                            #Generate hashed password if necessary
                            if ($SecurePassword) {
                                $currentHashedPassword = Get-PasswordHash $SecurePassword $server.versionMajor
                            } elseif ($HashedPassword) {
                                $currentHashedPassword = $HashedPassword
                            }
                        } elseif ($loginType -eq 'AsymmetricKey') {
                            $newLogin.AsymmetricKey = $currentAsymmetricKey
                        } elseif ($loginType -eq 'Certificate') {
                            $newLogin.Certificate = $currentCertificate
                        }

                        #Add credential
                        if ($currentCredential) {
                            $withParams += ", CREDENTIAL = [$currentCredential]"
                        }

                        Write-Message -Level Verbose -Message "Adding as login type $loginType"

                        # Attempt to add login using SMO, then T-SQL
                        try {
                            if ($loginType -in ("WindowsUser", "WindowsGroup", "AsymmetricKey", "Certificate")) {
                                if ($withParams) { $withParams = " WITH " + $withParams.TrimStart(',') }
                                $newLogin.Create()
                            } elseif ($loginType -eq "SqlLogin") {
                                $newLogin.Create($currentHashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                            }
                            $newLogin.Refresh()

                            #Adding credential
                            if ($currentCredential) {
                                try {
                                    $newLogin.AddCredential($currentCredential)
                                } catch {
                                    $newLogin.Drop()
                                    Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                            Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                        } catch {
                            Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
                            try {
                                if ($loginType -eq 'AsymmetricKey') { $sql = "CREATE LOGIN [$loginName] FROM ASYMMETRIC KEY [$currentAsymmetricKey]" }
                                elseif ($loginType -eq 'Certificate') { $sql = "CREATE LOGIN [$loginName] FROM CERTIFICATE [$currentCertificate]" }
                                elseif ($loginType -eq 'SqlLogin' -and $server.DatabaseEngineType -eq 'SqlAzureDatabase') {
                                    # Azure SQL doesn't support HASHED so we have to dump out the plain text password :(
                                    $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = '$($SecurePassword | ConvertFrom-SecurePass)'"
                                } elseif ($loginType -eq 'SqlLogin' ) {
                                    $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $currentHashedPassword HASHED" + $withParams
                                } else {
                                    $sql = "CREATE LOGIN [$loginName] FROM WINDOWS" + $withParams
                                }
                                $null = $server.Query($sql)
                                $newLogin = $server.logins[$loginName]
                                Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
                                $usedTsql = $true
                            } catch {
                                Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                            }
                        }

                        #Process the Disabled property
                        if ($currentDisabled) {
                            try {
                                $newLogin.Disable()
                                Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to disable $loginName on $instance using SMO, trying T-SQL."
                                try {
                                    $sql = "ALTER LOGIN [$loginName] DISABLE"
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance."
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to disable $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }
                        #Process the DenyWindowsLogin property
                        if ($currentDenyWindowsLogin -ne $newLogin.DenyWindowsLogin) {
                            try {
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                                $newLogin.Alter()
                                Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance."
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to deny from logging in $loginName on $instance using SMO, trying T-SQL."
                                try {
                                    $sql = "DENY CONNECT SQL TO [{0}]" -f $newLogin.Name
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance."
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to set deny windows login priviledge $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }

                        #Process the MustChangePassword property
                        if ($currentPasswordMustChange -ne $newLogin.MustChangePassword) {
                            try {
                                $newLogin.ChangePassword($SecurePassword, $true, $true)
                                Write-Message -Level Verbose -Message "Login $loginName has been marked as must change password."

                                # We need to refresh login after ChangePassword. Otherwise, MustChangePassword will appear as False
                                $server.Logins[$loginName].Refresh()
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to marked as must change password in $loginName on $instance using SMO."
                            }
                        }

                        #Display results
                        # If we ever used T-SQL, the smo is some times not up to date and should be refreshed
                        if ($usedTsql) {
                            $server.Logins.Refresh()
                        }

                        Add-TeppCacheItem -SqlInstance $server -Type login -Name $loginName

                        Get-DbaLogin -SqlInstance $server -Login $loginName

                    } catch {
                        Stop-Function -Message "Failed to create login $loginName on $instance." -Target $credential -InnerErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU8YVxb+8zr8tdWrOoYUHJF2Ie
# +G6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFCkcG0otcuOy0sfEscHCWj7I/a9YMA0GCSqGSIb3DQEBAQUABIIBAINJKdna
# yz8lfJcGOYEayOVUqQED1N/vHeyLaaWDJfACeV03pf4IuvShijDhEBpMY5k7OZE8
# ewbv0uJA5F/BPwrVSMVxjt21y/l8HOdAmFOqLEU6913LCBR2rTekhRBp/q9pYY36
# azGNt5Ij7CvDOFAiXyK6AmQ2CB72XtNGbwbpWSIksDHQ1ECrvtXykKlo/3JOR0wf
# 0AaMc+2hnP926YSqIDLRNnNkgo/N6pfa2rWjn4pduq9PcAEEh/2V5gW2twrp+RjQ
# hTKAwwFY5P8tSKzVLtOr4x4556p7gElHj/Xab3nbOLCcrrwct241Dq8Vqif4in8K
# pkrHMMVuX7QswBehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU0M1owLwYJKoZIhvcNAQkEMSIEIGf1wdCO24g0DHXD+fUbn+LxN2Lu
# zOJ4xmO9Qrm56x9AMA0GCSqGSIb3DQEBAQUABIIBAIbwp6izUGQTlPGxxeV4CcuK
# rTqvgnigq/PkMQLvMtbVPVDxHPsMZg5eI+NqDA1Phq8WDHx9oQeXfX8V03hfqZrB
# s0cnmuhxWeh724bct4QeAHhKHRvMruufA3nHDwkl/HtSrfuIDG59GRGMeTnkc80u
# EoMhqnLWFjoFXiftAdWiW/xLDOwThuIqloixF+aqqDDu4Ruvsyo1mTdOn54EPvhy
# vzlD+EX9vEirmzw50hxdgy95Vf7kRQ+8JnPf2WyWdH5LS3+TFzcatK3H5l8GZyYe
# SiC8LyBKtXB/4S2Sm8XZ53ccaky6a6hcnV3CiB+4Nv1sBo2Cu2xQ4W3yEnMMjvg=
# SIG # End signature block
