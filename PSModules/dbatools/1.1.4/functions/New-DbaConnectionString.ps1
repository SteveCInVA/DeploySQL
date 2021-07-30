function New-DbaConnectionString {
    <#
    .SYNOPSIS
        Builds or extracts a SQL Server Connection String

    .DESCRIPTION
        Builds or extracts a SQL Server Connection String. Note that dbatools-style syntax is used.

        So you do not need to specify "Data Source", you can just specify -SqlInstance and -SqlCredential and we'll handle it for you.

        This is the simplified PowerShell approach to connection string building. See examples for more info.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AccessToken
        Basically tells the connection string to ignore authentication. Does not include the AccessToken in the resulting connecstring.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and, optionally, -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server. Possible values are ReadOnly and ReadWrite.

    .PARAMETER BatchSeparator
        By default, this is "GO"

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER Database
        Database name

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are greater than or equal to 0 and less than or equal to 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        When true, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed. Recognized values are true, false, yes, and no. For more information, see Connection String Syntax.

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication.

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "", then Initial Catalog must be present, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER IsActiveDirectoryUniversalAuth
        Azure related

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        When used, an application can maintain multiple active result sets (MARS). When false, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If your application is connecting to an AlwaysOn availability group (AG) on different subnets, setting MultiSubnetFailover provides faster detection of and connection to the (currently) active server. For more information about SqlClient support for Always On Availability Groups

    .PARAMETER NetworkProtocol
        Connect explicitly using 'TcpIp','NamedPipes','Multiprotocol','AppleTalk','BanyanVines','Via','SharedMemory' and 'NWLinkIpxSpx'

    .PARAMETER NonPooledConnection
        Request a non-pooled connection

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time, and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include CaptureSql, ExecuteAndCaptureSql and ExecuteSql.

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a time-out error.

    .PARAMETER TrustServerCertificate
        Sets a value that indicates whether the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

    .PARAMETER Legacy
        Use this switch to create a connection string using System.Data.SqlClient instead of Microsoft.Data.SqlClient.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Connection, Connect, ConnectionString
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaConnectionString

    .EXAMPLE
        PS C:\> New-DbaConnectionString -SqlInstance sql2014

        Creates a connection string that connects using Windows Authentication

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2016 | New-DbaConnectionString

        Builds a connected SMO object using Connect-DbaInstance then extracts and displays the connection string

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> New-DbaConnectionString -SqlInstance sql2014 -Credential $wincred

        Creates a connection string that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -Credential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString -SqlInstance mydb.database.windows.net -SqlCredential me@myad.onmicrosoft.com -Database db

        Creates a connection string for an Azure Active Directory login to Azure SQL db. Output looks like this:
        Data Source=TCP:mydb.database.windows.net,1433;Initial Catalog=db;User ID=me@myad.onmicrosoft.com;Password=fakepass;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;Application Name="dbatools PowerShell module - dbatools.io";Authentication="Active Directory Password"

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -ClientName "mah connection"

        Creates a connection string that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates a connection string that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates a connection string with Windows Authentication that uses TCPIP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString sql2016 -ApplicationIntent ReadOnly

        Creates a connection string with ReadOnly ApplicationIntent.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "Server", "DataSource")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("SqlCredential")]
        [PSCredential]$Credential,
        [string]$AccessToken,
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [string]$BatchSeparator,
        [string]$ClientName = "custom connection",
        [int]$ConnectTimeout,
        [string]$Database,
        [switch]$EncryptConnection,
        [string]$FailoverPartner,
        [switch]$IsActiveDirectoryUniversalAuth,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover,
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol,
        [switch]$NonPooledConnection,
        [int]$PacketSize,
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout,
        [switch]$TrustServerCertificate,
        [string]$WorkstationId,
        [switch]$Legacy,
        [string]$AppendConnectionString
    )
    begin {
        function Test-Azure {
            Param (
                [DbaInstanceParameter[]]$SqlInstance
            )
            if ($SqlInstance.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "Test for Azure is positive"
                return $true
            } else {
                Write-Message -Level Debug -Message "Test for Azure is negative"
                return $false
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            <#
            The new code path (formerly known as experimental) is now the default.
            To have a quick way to switch back in case any problems occur, the switch "legacy" is introduced: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            #>
            if (-not (Get-DbatoolsConfigValue -FullName sql.connection.legacy)) {
                <#
                Maybe more docs...
                #>
                Write-Message -Level Debug -Message "We have to build a connect string, using these parameters: $($PSBoundParameters.Keys)"

                # Test for unsupported parameters
                if (Test-Bound -ParameterName 'LockTimeout') {
                    Write-Message -Level Warning -Message "Parameter LockTimeout not supported, because it is not part of a connection string."
                }
                # TODO: That can be added to the Data Source - but why?
                #if (Test-Bound -ParameterName 'NetworkProtocol') {
                #    Write-Message -Level Warning -Message "Parameter NetworkProtocol not supported, because it is not part of a connection string."
                #}
                if (Test-Bound -ParameterName 'StatementTimeout') {
                    Write-Message -Level Warning -Message "Parameter StatementTimeout not supported, because it is not part of a connection string."
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    Write-Message -Level Warning -Message "Parameter SqlExecutionModes not supported, because it is not part of a connection string."
                }

                # Set defaults like in Connect-DbaInstance
                if (Test-Bound -Not -ParameterName 'Database') {
                    $Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database')
                }
                if (Test-Bound -Not -ParameterName 'ClientName') {
                    $ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname')
                }
                if (Test-Bound -Not -ParameterName 'ConnectTimeout') {
                    $ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
                }
                if (Test-Bound -Not -ParameterName 'EncryptConnection') {
                    $EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt')
                }
                if (Test-Bound -Not -ParameterName 'NetworkProtocol') {
                    $np = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol')
                    if ($np) {
                        $NetworkProtocol = $np
                    }
                }
                if (Test-Bound -Not -ParameterName 'PacketSize') {
                    $PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize')
                }
                if (Test-Bound -Not -ParameterName 'TrustServerCertificate') {
                    $TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert')
                }
                # TODO: Maybe put this in a config item:
                $AzureDomain = "database.windows.net"

                # Rename credential parameter to align with other commands, later rename parameter
                $SqlCredential = $Credential

                if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                    if ($instance.Type -like "Server") {
                        Write-Message -Level Debug -Message "server object passed in, connection string is: $($instance.InputObject.ConnectionContext.ConnectionString)"
                        if ($Legacy) {
                            $converted = $instance.InputObject.ConnectionContext.ConnectionString | Convert-ConnectionString
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $converted
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $instance.InputObject.ConnectionContext.ConnectionString
                        }
                        # In Azure, check for a database change
                        if ((Test-Azure -SqlInstance $instance) -and $Database) {
                            $connStringBuilder['Initial Catalog'] = $Database
                        }
                        $connstring = $connStringBuilder.ConnectionString
                        # TODO: Should we check the other parameters and change the connection string accordingly?
                    } else {
                        if ($Legacy) {
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
                        }
                        $connStringBuilder['Data Source'] = $instance.FullSmoName
                        if ($ApplicationIntent) { $connStringBuilder['ApplicationIntent'] = $ApplicationIntent }
                        if ($ClientName) { $connStringBuilder['Application Name'] = $ClientName }
                        if ($ConnectTimeout) { $connStringBuilder['Connect Timeout'] = $ConnectTimeout }
                        if ($Database) { $connStringBuilder['Initial Catalog'] = $Database }
                        if ($EncryptConnection) { $connStringBuilder['Encrypt'] = $true } else { $connStringBuilder['Encrypt'] = $false }
                        if ($FailoverPartner) { $connStringBuilder['Failover Partner'] = $FailoverPartner }
                        if ($MaxPoolSize) { $connStringBuilder['Max Pool Size'] = $MaxPoolSize }
                        if ($MinPoolSize) { $connStringBuilder['Min Pool Size'] = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $connStringBuilder['MultipleActiveResultSets'] = $true } else { $connStringBuilder['MultipleActiveResultSets'] = $false }
                        if ($MultiSubnetFailover) { $connStringBuilder['MultiSubnetFailover'] = $true }
                        if ($NonPooledConnection) { $connStringBuilder['Pooling'] = $false }
                        if ($PacketSize) { $connStringBuilder['Packet Size'] = $PacketSize }
                        if ($PooledConnectionLifetime) { $connStringBuilder['Load Balance Timeout'] = $PooledConnectionLifetime }
                        if ($TrustServerCertificate) { $connStringBuilder['TrustServerCertificate'] = $true } else { $connStringBuilder['TrustServerCertificate'] = $false }
                        if ($WorkstationId) { $connStringBuilder['Workstation Id'] = $WorkstationId }
                        if ($SqlCredential) {
                            Write-Message -Level Debug -Message "We have a SqlCredential"
                            $username = ($SqlCredential.UserName).TrimStart("\")
                            # support both ad\username and username@ad
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $username = "$login@$domain"
                            }
                            $connStringBuilder['User ID'] = $username
                            $connStringBuilder['Password'] = $SqlCredential.GetNetworkCredential().Password
                            if ((Test-Azure -SqlInstance $instance) -and ($username -like "*@*")) {
                                Write-Message -Level Debug -Message "We connect to Azure with Azure AD account, so adding Authentication=Active Directory Password"
                                $connStringBuilder['Authentication'] = 'Active Directory Password'
                            }
                        } else {
                            Write-Message -Level Debug -Message "We don't have a SqlCredential"
                            if (Test-Azure -SqlInstance $instance) {
                                Write-Message -Level Debug -Message "We connect to Azure, so adding Authentication=Active Directory Integrated"
                                $connStringBuilder['Authentication'] = 'Active Directory Integrated'
                            } else {
                                Write-Message -Level Debug -Message "We don't connect to Azure, so setting Integrated Security=True"
                                $connStringBuilder['Integrated Security'] = $true
                            }
                        }

                        # special config for Azure
                        if (Test-Azure -SqlInstance $instance) {
                            if (Test-Bound -Not -ParameterName ConnectTimeout) {
                                $connStringBuilder['Connect Timeout'] = 30
                            }
                            $connStringBuilder['Encrypt'] = $true
                            # Why adding tcp:?
                            #$connStringBuilder['Data Source'] = "tcp:$($instance.ComputerName),$($instance.Port)"
                        }
                        if ($Legacy) {
                            $connstring = $connStringBuilder.ConnectionString
                        } else {
                            $connstring = $connStringBuilder.ToString()
                        }
                        if ($AppendConnectionString) {
                            # TODO: Check if new connection string is still valid
                            $connstring = "$connstring;$AppendConnectionString"
                        }
                    }
                    $connstring
                    continue
                }
            }
            <#
            This is the end of the new default code path.
            All session with the configuration "sql.connection.legacy" set to $true will run through the following code.
            To use the legacy code path: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            #>

            Write-Message -Level Debug -Message "sql.connection.legacy is used"

            if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                if ($instance.ComputerName -match "database\.windows\.net" -or $instance.InputObject.ComputerName -match "database\.windows\.net") {
                    if ($instance.InputObject.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                        $connstring = $instance.InputObject.ConnectionContext.ConnectionString
                        if ($Database) {
                            $olddb = $connstring -split ';' | Where-Object { $_.StartsWith("Initial Catalog") }
                            $newdb = "Initial Catalog=$Database"
                            if ($olddb) {
                                $connstring = $connstring.Replace("$olddb", "$newdb")
                            } else {
                                $connstring = "$connstring;$newdb;"
                            }
                        }
                        $connstring
                        continue
                    } else {
                        $isAzure = $true

                        if (-not (Test-Bound -ParameterName ConnectTimeout)) {
                            $ConnectTimeout = 30
                        }

                        if (-not (Test-Bound -ParameterName ClientName)) {
                            $ClientName = "dbatools PowerShell module - dbatools.io"

                        }
                        $EncryptConnection = $true
                        $instance = [DbaInstanceParameter]"tcp:$($instance.ComputerName),$($instance.Port)"
                    }
                }

                if ($instance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                    return $instance.ConnectionContext.ConnectionString
                } else {
                    $guid = [System.Guid]::NewGuid()
                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $guid

                    if ($AppendConnectionString) {
                        $connstring = $server.ConnectionContext.ConnectionString
                        $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                        $server.ConnectionContext.ConnectionString
                    } else {

                        $server.ConnectionContext.ApplicationName = $ClientName
                        if ($BatchSeparator) { $server.ConnectionContext.BatchSeparator = $BatchSeparator }
                        if ($ConnectTimeout) { $server.ConnectionContext.ConnectTimeout = $ConnectTimeout }
                        if ($Database) { $server.ConnectionContext.DatabaseName = $Database }
                        if ($EncryptConnection) { $server.ConnectionContext.EncryptConnection = $true }
                        if ($IsActiveDirectoryUniversalAuth) { $server.ConnectionContext.IsActiveDirectoryUniversalAuth = $true }
                        if ($LockTimeout) { $server.ConnectionContext.LockTimeout = $LockTimeout }
                        if ($MaxPoolSize) { $server.ConnectionContext.MaxPoolSize = $MaxPoolSize }
                        if ($MinPoolSize) { $server.ConnectionContext.MinPoolSize = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $server.ConnectionContext.MultipleActiveResultSets = $true }
                        if ($NetworkProtocol) { $server.ConnectionContext.NetworkProtocol = $NetworkProtocol }
                        if ($NonPooledConnection) { $server.ConnectionContext.NonPooledConnection = $true }
                        if ($PacketSize) { $server.ConnectionContext.PacketSize = $PacketSize }
                        if ($PooledConnectionLifetime) { $server.ConnectionContext.PooledConnectionLifetime = $PooledConnectionLifetime }
                        if ($StatementTimeout) { $server.ConnectionContext.StatementTimeout = $StatementTimeout }
                        if ($SqlExecutionModes) { $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes }
                        if ($TrustServerCertificate) { $server.ConnectionContext.TrustServerCertificate = $true }
                        if ($WorkstationId) { $server.ConnectionContext.WorkstationId = $WorkstationId }

                        if ($null -ne $Credential.username) {
                            $username = ($Credential.username).TrimStart("\")

                            if ($username -like "*\*") {
                                $username = $username.Split("\")[1]
                                $server.ConnectionContext.LoginSecure = $true
                                $server.ConnectionContext.ConnectAsUser = $true
                                $server.ConnectionContext.ConnectAsUserName = $username
                                $server.ConnectionContext.ConnectAsUserPassword = ($Credential).GetNetworkCredential().Password
                            } else {
                                $server.ConnectionContext.LoginSecure = $false
                                $server.ConnectionContext.set_Login($username)
                                $server.ConnectionContext.set_SecurePassword($Credential.Password)
                            }
                        }

                        $connstring = $server.ConnectionContext.ConnectionString
                        if ($MultiSubnetFailover) { $connstring = "$connstring;MultiSubnetFailover=True" }
                        if ($FailoverPartner) { $connstring = "$connstring;Failover Partner=$FailoverPartner" }
                        if ($ApplicationIntent) { $connstring = "$connstring;ApplicationIntent=$ApplicationIntent;" }

                        if ($isAzure) {
                            if ($Credential) {
                                if ($Credential.UserName -like "*\*" -or $Credential.UserName -like "*@*") {
                                    $connstring = "$connstring;Authentication=`"Active Directory Password`""
                                } else {
                                    $username = ($Credential.username).TrimStart("\")
                                    $server.ConnectionContext.LoginSecure = $false
                                    $server.ConnectionContext.set_Login($username)
                                    $server.ConnectionContext.set_SecurePassword($Credential.Password)
                                }
                            } else {
                                $connstring = $connstring.Replace("Integrated Security=True;", "Persist Security Info=True;")
                                if (-not $AccessToken) {
                                    $connstring = "$connstring;Authentication=`"Active Directory Integrated`""
                                }
                            }
                        }

                        if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                            $server.ConnectionContext.ConnectionString = $connstring
                        }

                        ($server.ConnectionContext.ConnectionString).Replace($guid, $instance)
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU7JBJl+hAfpQMaZ0PQx1n2Xpp
# hlygghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFCu38xS8/kXGqB2Zsz+Su81NGrQOMA0GCSqGSIb3DQEBAQUABIIBALaTxY/Q
# /feBQs5j9fOWytpdK1Hvptdf9vPsWzrMpgOL28mHGRMjMaPiB2dApI8Y+ZnorXH3
# 3Sz4W+rWpFEHLFU4/fHPDWzgZ0FK23BLCpgEpKa85Kkthk5faUdpB+kGyxL5QzAx
# 6q6zmBzp+h1TrtTSFfDqSnkIMG4tgAroI30xj5mC8knSQt7PkFzsj288hAEbN5Q9
# 8AvnjF0kuJFbRCmOtVTTR4iRdyTk5GoG6zKZG37ToZ39w3VwViuQvckkowJruYKl
# fUSuTm1SakijZd2Wq8ISrsYZKSpjAJLPZqdn9OuYPrhXPlAMLRe/bEJWhuqctCT+
# kW5EdnmhEKgw4A6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1NFowLwYJKoZIhvcNAQkEMSIEIB7q57Lub+7EtWl2vdK6Qd7ExNDB
# 2iyKpXSFKiL8H/iEMA0GCSqGSIb3DQEBAQUABIIBAJEO54LVHONRz2ibOpA3QMKZ
# 95+DRP6x3M1F6bnUBowitvp/af3wzmKh2RprFDQjEJtmCNRQ73FNti2D8Y5Nronj
# ROX6iY3sA38ypNH2Y/Rp9xogPouuv5Ez3zuKn4PNwRFQysuBh9ZJKQLj3mLcSZDR
# R4E5taLUUyaLfuO/IV3xOZkd/M9bSg+77JfrEkOoN5gnNPI4cyntnk7u4lQksxaP
# v6V0iCExbmp8uHo4Lps6CmkRBRVfUYvJ88UI70OhD0Lsb2qzaNGvVJMagZfHN5vj
# jSu/SS9Le3z8wuODtsCNYvwNtPZOa1di9nWPCVNG9+2OBsM2gIyqTRxqgXwRSlA=
# SIG # End signature block
