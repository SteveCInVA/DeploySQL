function Reset-DbaAdmin {
    <#
    .SYNOPSIS
        This function allows administrators to regain access to SQL Servers in the event that passwords or access was lost.

        Supports SQL Server 2005 and above. Windows administrator access is required.

    .DESCRIPTION
        This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding the sysadmin role to existing login, or adding a new login (SQL or Windows) and granting it sysadmin privileges.

        This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line using the /mReset-DbaAdmin parameter which starts the server in Single-User mode and only allows this script to connect.

        Once the service is restarted, the following tasks are performed:
        - Login is added if it doesn't exist
        - If login is a Windows User, an attempt is made to ensure it exists
        - If login is a SQL Login, password policy will be set to OFF when creating the login, and SQL Server authentication will be set to Mixed Mode.
        - Login will be enabled and unlocked
        - Login will be added to sysadmin role

        If failures occur at any point, a best attempt is made to restart the SQL Server.

        In order to make this script as portable as possible, Microsoft.Data.SqlClient and Get-WmiObject are used (as opposed to requiring the Failover Cluster Admin tools or SMO).

        If using this function against a remote SQL Server, ensure WinRM is configured and accessible. If this is not possible, run the script locally.

        Tested on Windows XP, 7, 8.1, Server 2012 and Windows Server Technical Preview 2.
        Tested on SQL Server 2005 SP4 through 2016 CTP2.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server must be 2005 and above, and can be a clustered or stand-alone instance.

    .PARAMETER SqlCredential
        Instead of using Login and SecurePassword, you can just pass in a credential object.

    .PARAMETER Login
        By default, the Login parameter is "sa" but any other SQL or Windows account can be specified. If a login does not currently exist, it will be added.

        When adding a Windows login to remote servers, ensure the SQL Server can add the login (ie, don't add WORKSTATION\Admin to remoteserver\instance. Domain users and Groups are valid input.

    .PARAMETER SecurePassword
        By default, if a SQL Login is detected, you will be prompted for a password. Use this to securely bypass the prompt.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $instance is not local

    .LINK
        https://dbatools.io/Reset-DbaAdmin

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlcluster -SqlCredential sqladmin

        Prompts for password, then resets the "sqladmin" account password on sqlcluster.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login ad\administrator -Confirm:$false

        Adds the domain account "ad\administrator" as a sysadmin to the SQL instance.

        If the account already exists, it will be added to the sysadmin role.

        Does not prompt for a password since it is not a SQL login. Does not prompt for confirmation since -Confirm is set to $false.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login sqladmin -Force

        Skips restart confirmation, prompts for password, then adds a SQL Login "sqladmin" with sysadmin privileges.
        If the account already exists, it will be added to the sysadmin role and the password will be reset.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject for client backwards compatibilty")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Login = "sa",
        [SecureString]$SecurePassword,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        #region Utility functions
        function ConvertTo-PlainText {
            <#
                .SYNOPSIS
                Internal function.
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Security.SecureString]$Password
            )
            $marshal = [Runtime.InteropServices.Marshal]
            $plaintext = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($Password))
            return $plaintext
        }

        function Invoke-ResetSqlCmd {
            <#
                .SYNOPSIS
                Internal function. Executes a SQL statement against specified computer, and uses "Reset-DbaAdmin" as the Application Name.
            #>
            [OutputType([System.Boolean])]
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter]$instance,
                [string]$sql,
                [switch]$EnableException
            )
            try {
                $connstring = "Data Source=$instance;Integrated Security=True;Connect Timeout=20;Application Name=Reset-DbaAdmin"
                $conn = New-Object Microsoft.Data.SqlClient.SqlConnection $connstring
                $conn.Open()
                $cmd = New-Object Microsoft.Data.sqlclient.sqlcommand($null, $conn)
                $cmd.CommandText = $sql
                $null = $cmd.ExecuteNonQuery()
                $true
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -EnableException $EnableException
                $false
            } finally {
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
            }
        }
        #endregion Utility functions
        if ($Force) { $ConfirmPreference = 'none' }

        if ($SqlCredential) {
            $Login = $SqlCredential.UserName
            $SecurePassword = $SqlCredential.Password
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $stepcounter = 0
            $baseaddress = $instance.ComputerName
            # Get hostname

            if ($instance.IsLocalHost) {
                $ipaddr = "."
                $hostName = $env:COMPUTERNAME
                $baseaddress = $env:COMPUTERNAME
            } else {
                $resolved = Resolve-DbaNetworkName -ComputerName $baseaddress
                $ipaddr = $resolved.IPAddress
                $hostName = $resolved.FullComputerName
            }

            # Setup remote session if server is not local
            if (-not $instance.IsLocalHost) {
                try {
                    $connectionParams = @{
                        ComputerName = $hostName
                        ErrorAction  = "Stop"
                        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
                    }
                    $session = New-PSSession @connectionParams
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Can't access $hostName using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally."
                }
            }

            Write-Message -Level Verbose -Message "Detecting login type."
            # Is login a Windows login? If so, does it exist?
            if ($Login -match "\\") {
                Write-Message -Level Verbose -Message "Windows login detected. Checking to ensure account is valid."
                $windowslogin = $true
                try {
                    if ($hostName -eq $env:COMPUTERNAME) {
                        $account = New-Object System.Security.Principal.NTAccount($Login)
                        #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                        $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                    } else {
                        Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $Login -ScriptBlock {
                            $account = New-Object System.Security.Principal.NTAccount($args)
                            #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                        }
                    }
                } catch {
                    Write-Message -Level Warning -Message "Cannot resolve Windows User or Group $Login. Trying anyway."
                }
            }

            # If it's not a Windows login, it's a SQL login, so it needs a password.
            if (-not $windowslogin -and -not $SecurePassword) {
                Write-Message -Level Verbose -Message "SQL login detected"
                do {
                    $password = Read-Host -AsSecureString "Please enter a new password for $Login"
                } while ($password.Length -eq 0)
            }

            If ($SecurePassword) {
                $password = $SecurePassword
            }

            # Get instance and service display name, then get services
            $instanceName = $instance.InstanceName
            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }
            $displayName = "SQL Server ($instanceName)"

            try {
                if ($hostName -eq $env:COMPUTERNAME) {
                    $instanceServices = Get-Service -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                } else {
                    $instanceServices = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                }
            } catch {
                Stop-Function -Message "Cannot connect to WMI on $hostName or SQL Service does not exist. Check permissions, firewall and SQL Server running status." -ErrorRecord $_ -Target $instance
                return
            }

            if (-not $instanceServices) {
                Stop-Function -Message "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again." -Target $instance
                return
            }

            Write-Message -Level Verbose -Message "Attempting to stop SQL Services."

            # Check to see if service is clustered. Clusters don't support -m (since the cluster service
            # itself connects immediately) or -f, so they are handled differently.
            try {
                $checkcluster = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.Name -eq "ClusSvc" -and $_.Status -eq "Running" }
            } catch {
                Stop-Function -Message "Can't check services." -Target $instance -ErrorRecord $_
                return
            }

            if ($null -ne $checkcluster) {
                $clusterResource = Get-DbaCmObject -ClassName "MSCluster_Resource" -Namespace "root\mscluster" -ComputerName $hostName | Where-Object { $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instanceName)" }
            }

            if ($pscmdlet.ShouldProcess($baseaddress, "Stop $instance to restart in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Stopping $instance to restart in single-user mode"
                # Take SQL Server offline so that it can be started in single-user mode
                if ($clusterResource.count -gt 0) {
                    $isClustered = $true
                    try {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.TakeOffline(60) }
                    } catch {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                } else {
                    try {
                        Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Successfully stopped SQL service."
                    } catch {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                }
            }

            # /mReset-DbaAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
            if ($pscmdlet.ShouldProcess($baseaddress, "Starting $instance in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting $instance in single-user mode"
                try {
                    if ($instance.IsLocalHost) {
                        $netstart = net start ""$displayName"" /mReset-DbaAdmin 2>&1
                        if ("$netstart" -notmatch "success") {
                            Stop-Function -Message "Restart failure" -Continue
                        }
                    } else {
                        $netstart = Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $displayName -ScriptBlock { net start ""$args"" /mReset-DbaAdmin } 2>&1
                        foreach ($line in $netstart) {
                            if ($line.length -gt 0) {
                                Write-Message -Level Verbose -Message $line
                            }
                        }
                    }
                } catch {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue

                    if ($isClustered) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                    }
                    Stop-Function -Message "Couldn't execute net start command. Restarted services and quit." -ErrorRecord $_
                    return
                }
            }

            if ($pscmdlet.ShouldProcess($baseaddress, "Testing $instance to ensure it's back up")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Testing $instance to ensure it's back up"
                try {
                    $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                } catch {
                    try {
                        Start-Sleep 3
                        $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                    } catch {
                        Stop-Service Input-Object $sqlservice -Force -ErrorAction SilentlyContinue
                        if ($isClustered) {
                            $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                            $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        } else {
                            Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                        }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_
                    }
                }
            }

            # Get login. If it doesn't exist, create it.
            if ($pscmdlet.ShouldProcess($instance, "Adding login $Login if it doesn't exist")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding login $Login if it doesn't exist"
                if ($windowslogin) {
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] FROM WINDOWS END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create Windows login."
                    }

                } elseif ($Login -ne "sa") {
                    # Create new sql user
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create SQL login."
                    }
                }
            }

            # If $Login is a SQL Login, Mixed mode authentication is required.
            if ($windowslogin -ne $true) {
                if ($pscmdlet.ShouldProcess($instance, "Enabling mixed mode authentication for $Login and ensuring account is unlocked")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling mixed mode authentication for $Login and ensuring account is unlocked"
                    $sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't set to Mixed Mode."
                    }

                    $sql = "ALTER LOGIN [$Login] WITH CHECK_POLICY = OFF
                    ALTER LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)' UNLOCK"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't unlock account."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Enabling $Login")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring login is enabled"
                $sql = "ALTER LOGIN [$Login] ENABLE"
                if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                    Write-Message -Level Warning -Message "Couldn't enable login."
                }
            }

            if ($Login -ne "sa") {
                if ($pscmdlet.ShouldProcess($instance, "Ensuring $Login exists within sysadmin role")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring $Login exists within sysadmin role"
                    $sql = "EXEC sp_addsrvrolemember '$Login', 'sysadmin'"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't add to sysadmin role."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Finished with login tasks. Restarting")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Finished with login tasks. Restarting."
                try {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                    if ($isClustered -eq $true) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Logging in to get account information")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Logging in to get account information"
                if ($SecurePassword) {
                    $cred = New-Object System.Management.Automation.PSCredential ($Login, $SecurePassword)
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $cred -Login $Login
                } elseif ($SqlCredential) {
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
                } else {
                    try {
                        Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login -EnableException
                    } catch {
                        Stop-Function -Message "Password not supplied, tried logging in with Integrated authentication and it failed. Either way, $Login should work now on $instance." -Continue
                    }
                }
            }

        }
    }
    end {
        Write-Message -Level Verbose -Message "Script complete."
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6Lu2I8ChGTTbt+3dQFEsXqOg
# tBugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFG6ZHyo93qPuHdzSLLsL/IBaOo4lMA0GCSqGSIb3DQEBAQUABIIBAJbrZ5Rs
# B9p+Gbiiob5c/kpxWw1PiRhY2ZsrExrURZyUOCekh11X9e2Z7D5Q2l5ht9SS8lQ1
# iptsC6gJ4KXlIK1XDtDw1KpCexGoP6oR+73X56mOMM3jvanb/qmT666M4aVqaRa5
# 51zFHsJHmyI9845L01KC8inPljy9Ibu/c0Afyc5+7qbPjsClWy4Q+CqqbiLRtCq/
# aLeC3WW32T7n8RMHBh9rjB8rVRpgI0PrtIIZLxaGBcdSs4Wd8j5vX9trhKzCWRY0
# hi3yj4n4mMWLnz/65Y1nU6LI5z109RrKLncUk159zRBU8bCvTbWd5beqmUrBMH24
# Q7Nh0QfZFxdyAW+hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwNVowLwYJKoZIhvcNAQkEMSIEIFlcUukJFKyD89dIya/7rxZUsjGg
# +hXlA1FTaC+iiSfEMA0GCSqGSIb3DQEBAQUABIIBAJ5tcEQOnKh1rsiV/FoNYY5U
# +q2aA4WXZJfMbB2XLekM2WU5yzuL4t81nDdHlFsMOmTso7w98J0WD+yivqR+zbKS
# oF//W0Dgap0AtzmcpZf2sujY/iOpInxVzHDQ9C40GeQyYwOTnRRI3hiCTbLtO2tx
# QuB6FqF4uSM46zvk8dHrD2psnT0PM67K+ptrZEODS7xM427VVavKRyY4qBVhx8xk
# vS5wiIL4r5Ad0pzCs9i1T3KcwoLVSUzgmG9ldoNPCcbr0WwccxnnNNs4Qk2nMiGs
# fLHG5iOKZLx+5gWQeDiL028RoWFgCrVShk+X6kil0aga+oL+J6dXdHu13/okBUg=
# SIG # End signature block
