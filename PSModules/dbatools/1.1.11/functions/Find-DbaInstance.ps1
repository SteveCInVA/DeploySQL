function Find-DbaInstance {
    <#
    .SYNOPSIS
        Search for SQL Server Instances.

    .DESCRIPTION
        This function searches for SQL Server Instances.

        It supports a variety of scans for this purpose which can be separated in two categories:
        - Discovery
        - Scan

        Discovery:
        This is where it compiles a list of computers / addresses to check.
        It supports several methods of generating such lists (including Active Directory lookup or IP Ranges), but also supports specifying a list of computers to check.
        - For details on discovery, see the documentation on the '-DiscoveryType' parameter
        - For details on explicitly providing a list, see the documentation on the '-ComputerName' parameter

        Scan:
        Once a list of computers has been provided, this command will execute a variety of actions to determine any instances present for each of them.
        This is described in more detail in the documentation on the '-ScanType' parameter.
        Additional parameters allow more granular control over individual scans (e.g. Credentials to use).

        Note on logging and auditing:
        The Discovery phase is un-problematic since it is non-intrusive, however during the scan phase, all targeted computers may be accessed repeatedly.
        This may cause issues with security teams, due to many logon events and possibly failed authentication.
        This action constitutes a network scan, which may be illegal depending on the nation you are in and whether you own the network you scan.
        If you are unsure whether you may use this command in your environment, check the detailed description on the '-ScanType' parameter and contact your IT security team for advice.

    .PARAMETER ComputerName
        The computer to scan. Can be a variety of input types, including text or the output of Get-ADComputer.
        Any extra instance information (such as connection strings or live sql server connections) beyond the computername will be discarded.

    .PARAMETER DiscoveryType
        The mechanisms to be used to discover instances.
        Supports any combination of:
        - Service Principal Name lookup ('DomainSPN'; from Active Directory)
        - SQL Instance Enumeration ('DataSourceEnumeration'; same as SSMS uses)
        - IP Address range ('IPRange'; all IP Addresses will be scanned)
        - Domain Server lookup ('DomainServer'; from Active Directory)

        SPN Lookup:
        The function tries to connect active directory to look up all computers with registered SQL Instances.
        Not all instances need to be registered properly, making this not 100% reliable.
        By default, your nearest Domain Controller is contacted for this scan.
        However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
        If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

        SQL Instance Enumeration:
        This uses the default UDP Broadcast based instance enumeration used by SSMS to detect instances.
        Note that the result from this is not used in the actual scan, but only to compile a list of computers to scan.
        To enable the same results for the scan, ensure that the 'Browser' scan is enabled.

        IP Address range:
        This 'Discovery' uses a range of IPAddresses and simply passes them on to be tested.
        See the 'Description' part of help on security issues of network scanning.
        By default, it will enumerate all ethernet network adapters on the local computer and scan the entire subnet they are on.
        By using the '-IpAddress' parameter, custom network ranges can be specified.

        Domain Server:
        This will discover every single computer in Active Directory that is a Windows Server and enabled.
        By default, your nearest Domain Controller is contacted for this scan.
        However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
        If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

    .PARAMETER Credential
        The credentials to use on windows network connection.
        These credentials are used for:
        - Contact to domain controllers for SPN lookups (only if explicit Domain Controller is specified)
        - CIM/WMI contact to the scanned computers during the scan phase (see the '-ScanType' parameter documentation on affected scans).

    .PARAMETER SqlCredential
        The credentials used to connect to SqlInstances to during the scan phase.
        See the '-ScanType' parameter documentation on affected scans.

    .PARAMETER ScanType

        The scans are the individual methods used to retrieve information about the scanned computer and any potentially installed instances.
        This parameter is optional, by default all scans except for establishing an actual SQL connection are performed.
        Scans can be specified in any arbitrary combination, however at least one instance detecting scan needs to be specified in order for data to be returned.

        Scans:
         Browser
        - Tries discovering all instances via the browser service
        - This scan detects instances.

        SQLService
        - Tries listing all SQL Services using CIM/WMI
        - This scan uses credentials specified in the '-Credential' parameter if any.
        - This scan detects instances.
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).

        SPN
        - Tries looking up the Service Principal Names for each instance
        - Will use the nearest Domain Controller by default
        - Target a specific domain controller using the '-DomainController' parameter
        - If using the '-DomainController' parameter, use the '-Credential' parameter to specify the credentials used to connect

        TCPPort
        - Tries connecting to the TCP Ports.
        - By default, port 1433 is connected to.
        - The parameter '-TCPPort' can be used to provide a list of port numbers to scan.
        - This scan detects possible instances. Since other services might bind to a given port, this is not the most reliable test.
        - This scan is also used to validate found SPNs if both scans are used in combination

        DNSResolve
        - Tries resolving the computername in DNS

        Ping
        - Tries pinging the computer. Failure will NOT terminate scans.

        SqlConnect
        - Tries to establish a SQL connection to the server
        - Uses windows credentials by default
        - Specify custom credentials using the '-SqlCredential' parameter
        - This scan is not used by default
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).

        All
        - All of the above

    .PARAMETER IpAddress
        This parameter can be used to override the defaults for the IPRange discovery.
        This parameter accepts a list of strings supporting any combination of:
        - Plain IP Addresses (e.g.: "10.1.1.1")
        - IP Address Ranges (e.g.: "10.1.1.1-10.1.1.5")
        - IP Address & Subnet Mask (e.g.: "10.1.1.1/255.255.255.0")
        - IP Address & Subnet Length: (e.g.: "10.1.1.1/24)
        Overlapping addresses will not result in duplicate scans.

    .PARAMETER DomainController
        The domain controller to contact for SPN lookups / searches.
        Uses the credentials from the '-Credential' parameter if specified.

    .PARAMETER TCPPort
        The ports to scan in the TCP Port Scan method.
        Defaults to 1433.

    .PARAMETER MinimumConfidence
        This command tries to discover instances, which isn't always a sure thing.
        Depending on the number and type of scans completed, we have different levels of confidence in our results.
        By default, we will return anything that we have at least a low confidence of being an instance.
        These are the confidence levels we support and how they are determined:
        - High: Established SQL Connection (including rejection for bad credentials) or service scan.
        - Medium: Browser reply or a combination of TCPConnect _and_ SPN test.
        - Low: Either TCPConnect _or_ SPN
        - None: Computer existence could be verified, but no sign of an SQL Instance

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Connect, SqlServer
        Author: Scott Sutherland, 2018 NetSPI | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Outside resources used and modified:
        https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b

    .LINK
        https://dbatools.io/Find-DbaInstance

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType Domain, DataSourceEnumeration

        Performs a network search for SQL Instances by:
        - Looking up the Service Principal Names of computers in Active Directory
        - Using the UDP broadcast based auto-discovery of SSMS
        After that it will extensively scan all hosts thus discovered for instances.

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType All

        Performs a network search for SQL Instances, using all discovery protocols:
        - Active directory search for Service Principal Names
        - SQL Instance Enumeration (same as SSMS does)
        - All IPAddresses in the current computer's subnets of all connected network interfaces
        Note: This scan will take a long time, due to including the IP Scan

    .EXAMPLE
        PS C:\> Get-ADComputer -Filter "*" | Find-DbaInstance

        Scans all computers in the domain for SQL Instances, using a deep probe:
        - Tries resolving the name in DNS
        - Tries pinging the computer
        - Tries listing all SQL Services using CIM/WMI
        - Tries discovering all instances via the browser service
        - Tries connecting to the default TCP Port (1433)
        - Tries connecting to the TCP port of each discovered instance
        - Tries to establish a SQL connection to the server using default windows credentials
        - Tries looking up the Service Principal Names for each instance

    .EXAMPLE
        PS C:\> Get-Content .\servers.txt | Find-DbaInstance -SqlCredential $cred -ScanType Browser, SqlConnect

        Reads all servers from the servers.txt file (one server per line),
        then scans each of them for instances using the browser service
        and finally attempts to connect to each instance found using the specified credentials.
        then scans each of them for instances using the browser service and SqlService

    .EXAMPLE
        PS C:\> Find-DbaInstance -ComputerName localhost | Get-DbaDatabase | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays all information in a formatted table.

    .EXAMPLE
        PS C:\> $databases = Find-DbaInstance -ComputerName localhost | Get-DbaDatabase
        PS C:\> $results = $databases | Select-Object SqlInstance, Name, Status, RecoveryModel, SizeMB, Compatibility, Owner, LastFullBackup, LastDiffBackup, LastLogBackup
        PS C:\> $results | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays a subset of the important information in a formatted table.

        Using this method regularly is not recommended. Use Get-DbaService or Get-DbaRegServer instead.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Computer', ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [Parameter(Mandatory, ParameterSetName = 'Discover')]
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]$DiscoveryType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [ValidateSet('Default', 'SQLService', 'Browser', 'TCPPort', 'All', 'SPN', 'Ping', 'SqlConnect', 'DNSResolve')]
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType[]]$ScanType = "Default",
        [Parameter(ParameterSetName = 'Discover')]
        [string[]]$IpAddress,
        [string]$DomainController,
        [int[]]$TCPPort = 1433,
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence = 'Low',
        [switch]$EnableException
    )

    begin {

        #region Utility Functions
        function Test-SqlInstance {
            <#
            .SYNOPSIS
                Performs the actual scanning logic

            .DESCRIPTION
                Performs the actual scanning logic
                Each potential target is accessed using the specified scan routines.

            .PARAMETER Target
                The target to scan.

            .EXAMPLE
                PS C:\> Test-SqlInstance
        #>
            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)][DbaInstance[]]$Target,
                [PSCredential]$Credential,
                [PSCredential]$SqlCredential,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]$ScanType,
                [string]$DomainController,
                [int[]]$TCPPort = 1433,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence,
                [switch]$EnableException
            )

            begin {
                [System.Collections.ArrayList]$computersScanned = @()
            }

            process {
                foreach ($computer in $Target) {
                    $stepCounter = 0
                    if ($computersScanned.Contains($computer.ComputerName)) {
                        continue
                    } else {
                        $null = $computersScanned.Add($computer.ComputerName)
                    }
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Starting"
                    Write-Message -Level Verbose -Message "Processing: $($computer)" -Target $computer -FunctionName Find-DbaInstance

                    #region Null variables to prevent scope lookup on conditional existence
                    $resolution = $null
                    $pingReply = $null
                    $sPNs = @()
                    $ports = @()
                    $browseResult = $null
                    $services = @()
                    #Variable marked as unused by PSScriptAnalyzer
                    #$serverObject = $null
                    #$browseFailed = $false
                    #endregion Null variables to prevent scope lookup on conditional existence

                    #region Gather data
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::DNSResolve) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Performing DNS resolution"
                            $resolution = [System.Net.Dns]::GetHostEntry($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Ping) {
                        $ping = New-Object System.Net.NetworkInformation.Ping
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Waiting for ping response"
                            $pingReply = $ping.Send($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SPN) {
                        $computerByName = $computer.ComputerName
                        if ($resolution.HostName) { $computerByName = $resolution.HostName }
                        if ($computerByName -notmatch "$([dbargx]::IPv4)|$([dbargx]::IPv6)") {
                            try {
                                Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SPNs"
                                $sPNs = Get-DomainSPN -DomainController $DomainController -Credential $Credential -ComputerName $computerByName -GetSPN
                            } catch {
                                # here to avoid an empty catch
                                $null = 1
                            }
                        }
                    }

                    # $ports required for all scans
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Testing TCP ports"
                    $ports = $TCPPort | Test-TcpPort -ComputerName $computer

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Browser) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Probing Browser service"
                            $browseResult = Get-SQLInstanceBrowserUDP -ComputerName $computer -EnableException
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlService) {
                        Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SQL services using SQL WMI"
                        if ($Credential) {
                            $services = Get-DbaService -ComputerName $computer -Credential $Credential -EnableException -ErrorAction Ignore -WarningAction SilentlyCOntinue
                        } else {
                            $services = Get-DbaService -ComputerName $computer -ErrorAction Ignore -WarningAction SilentlyContinue
                        }
                    }
                    #endregion Gather data

                    #region Gather list of found instance indicators
                    $instanceNames = @()
                    if ($Services) {
                        $Services | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }
                    if ($browseResult) {
                        $browseResult | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }

                    $portsDetected = @()
                    foreach ($portResult in $ports) {
                        if ($portResult.IsOpen) { $portsDetected += $portResult.Port }
                    }
                    foreach ($sPN in $sPNs) {
                        try { $inst = $sPN.Split(':')[1] }
                        catch { continue }

                        try {
                            [int]$portNumber = $inst
                            if ($portNumber -and ($portsDetected -notcontains $portNumber)) {
                                $portsDetected += $portNumber
                            }
                        } catch {
                            if ($inst -and ($instanceNames -notcontains $inst)) {
                                $instanceNames += $inst
                            }
                        }
                    }
                    #endregion Gather list of found instance indicators

                    #region Case: Nothing found
                    if ((-not $instanceNames) -and (-not $portsDetected)) {
                        if ($resolution -or ($pingReply.Status -like "Success")) {
                            if ($MinimumConfidence -eq [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]::None) {
                                New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport -Property @{
                                    MachineName  = $computer.ComputerName
                                    ComputerName = $computer.ComputerName
                                    Ping         = $pingReply.Status -like 'Success'
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Computer $computer could be contacted, but no trace of an SQL Instance was found. Skipping..." -Target $computer -FunctionName Find-DbaInstance
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Computer $computer could not be contacted, skipping." -Target $computer -FunctionName Find-DbaInstance
                        }

                        continue
                    }
                    #endregion Case: Nothing found

                    [System.Collections.ArrayList]$masterList = @()

                    #region Case: Named instance found
                    foreach ($instance in $instanceNames) {
                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.InstanceName = $instance
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.Services = $services | Where-Object InstanceName -EQ $instance
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs

                        if ($result = $browseResult | Where-Object InstanceName -EQ $instance) {
                            $object.BrowseReply = $result
                        }
                        if ($ports) {
                            $object.PortsScanned = $ports
                        }

                        if ($object.BrowseReply) {
                            $object.Confidence = 'Medium'
                            if ($object.BrowseReply.TCPPort) {
                                $object.Port = $object.BrowseReply.TCPPort

                                $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                                    $object.TcpConnected = $_.IsOpen
                                }
                            }
                        }
                        if ($object.Services) {
                            $object.Confidence = 'High'

                            $engine = $object.Services | Where-Object ServiceType -EQ "Engine"
                            switch ($engine.State) {
                                "Running" { $object.Availability = 'Available' }
                                "Stopped" { $object.Availability = 'Unavailable' }
                                default { $object.Availability = 'Unknown' }
                            }
                        }

                        $object.Timestamp = Get-Date

                        $masterList += $object
                    }
                    #endregion Case: Named instance found

                    #region Case: Port number found
                    foreach ($port in $portsDetected) {
                        if ($masterList.Port -contains $port) { continue }

                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.Port = $port
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs
                        $object.Confidence = 'Low'
                        if ($ports) {
                            $object.PortsScanned = $ports

                            if (($ports | Where-Object IsOpen).Port -eq 1433) {
                                $object.Confidence = 'Medium'
                            }
                        }

                        if (($ports.Port -contains $port) -and ($sPNs | Where-Object { $_ -like "*:$port" })) {
                            $object.Confidence = 'Medium'
                        }

                        $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                            $object.TcpConnected = $_.IsOpen
                        }
                        $object.Timestamp = Get-Date

                        if ($masterList.SqlInstance -contains $object.SqlInstance) {
                            continue
                        }

                        $masterList += $object
                    }
                    #endregion Case: Port number found

                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlConnect) {
                        $instanceHash = @{ }
                        $toDelete = @()
                        foreach ($dataSet in $masterList) {
                            try {
                                $server = Connect-DbaInstance -SqlInstance $dataSet.FullSmoName -SqlCredential $SqlCredential
                                $dataSet.SqlConnected = $true
                                $dataSet.Confidence = 'High'

                                # Remove duplicates
                                if ($instanceHash.ContainsKey($server.DomainInstanceName)) {
                                    $toDelete += $dataSet
                                } else {
                                    $instanceHash[$server.DomainInstanceName] = $dataSet

                                    try {
                                        $dataSet.MachineName = $server.ComputerNamePhysicalNetBIOS
                                    } catch {
                                        # here to avoid an empty catch
                                        $null = 1
                                    }
                                }
                            } catch {
                                # Error class definitions
                                # https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-error-severities
                                # 24 or less means an instance was found, but had some issues

                                #region Processing error (Access denied, server error, ...)
                                if ($_.Exception.InnerException.Errors.Class -lt 25) {
                                    # There IS an SQL Instance and it listened to network traffic
                                    $dataSet.SqlConnected = $true
                                    $dataSet.Confidence = 'High'
                                }
                                #endregion Processing error (Access denied, server error, ...)

                                #region Other connection errors
                                else {
                                    $dataSet.SqlConnected = $false
                                }
                                #endregion Other connection errors
                            }
                        }

                        foreach ($item in $toDelete) {
                            $masterList.Remove($item)
                        }
                    }

                    $masterList | Where-Object { $_.Confidence -ge $MinimumConfidence }
                }
            }
        }

        function Get-DomainSPN {
            <#
            .SYNOPSIS
                Returns all computernames with registered MSSQL SPNs.

            .DESCRIPTION
                Returns all computernames with registered MSSQL SPNs.

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .PARAMETER ComputerName
                Filter by computername

            .PARAMETER GetSPN
                Returns the service SPNs instead of the hostname

            .EXAMPLE
                PS C:\> Get-DomainSPN -DomainController $DomainController -Credential $Credential

                Returns all computernames with MSQL SPNs known to $DomainController, assuming credentials are valid.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [Pscredential]$Credential,
                [string]$ComputerName = "*",
                [switch]$GetSPN
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(servicePrincipalName=MSSQLsvc*)(|(name=$ComputerName)(dnshostname=$ComputerName)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($GetSPN) {
                        $computer.Properties["serviceprincipalname"] | Where-Object { $_ -like "MSSQLsvc*:*" }
                    } else {
                        if ($computer.Properties["dnshostname"] -and $computer.Properties["dnshostname"] -ne '') {
                            $computer.Properties["dnshostname"][0]
                        } else {
                            $computer.Properties["serviceprincipalname"][0] -match '(?<=/)[^:]*' > $null
                            if ($matches) {
                                $matches[0]
                            } else {
                                $computer.Properties["name"][0]
                            }
                        }
                    }
                }
            } catch {
                throw
            }
        }

        function Get-DomainServer {
            <#
            .SYNOPSIS
                Returns a list of all Domain Computer objects that are servers.

            .DESCRIPTION
                Returns a list of all Domain Computer objects that are ...
                - Enabled
                - Have an OS named like "*windows*server*"

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .EXAMPLE
                PS C:\> Get-DomainServer

                Returns a list of all Domain Computer objects that are servers.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [Pscredential]$Credential
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(objectcategory=computer)(operatingSystem=*windows*server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($computer.Properties["dnshostname"]) {
                        $computer.Properties["dnshostname"][0]
                    } else {
                        $computer.Properties["name"][0]
                    }
                }
            } catch { throw }
        }

        function Get-SQLInstanceBrowserUDP {
            <#
            .SYNOPSIS
                Requests a list of instances from the browser service.

            .DESCRIPTION
                Requests a list of instances from the browser service.

            .PARAMETER ComputerName
                Computer name or IP address to enumerate SQL Instance from.

            .PARAMETER UDPTimeOut
                Timeout in seconds. Longer timeout = more accurate.

            .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

            .EXAMPLE
                PS C:\> Get-SQLInstanceBrowserUDP -ComputerName 'sql2017'

                Contacts the browsing service on sql2017 and requests its instance information.

            .NOTES
                Original Author: Eric Gruber
                Editors:
                - Scott Sutherland (Pipeline and timeout mods)
                - Friedrich Weinmann (Cleanup & dbatools Standardization)

        #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, ValueFromPipeline)][DbaInstance[]]$ComputerName,
                [int]$UDPTimeOut = 2,
                [switch]$EnableException
            )

            process {
                foreach ($computer in $ComputerName) {
                    try {
                        #region Connect to browser service and receive response
                        $UDPClient = New-Object -TypeName System.Net.Sockets.Udpclient
                        $UDPClient.Client.ReceiveTimeout = $UDPTimeOut * 1000
                        $UDPClient.Connect($computer.ComputerName, 1434)
                        $UDPPacket = 0x03
                        $UDPEndpoint = New-Object -TypeName System.Net.IpEndPoint -ArgumentList ([System.Net.Ipaddress]::Any, 0)
                        $UDPClient.Client.Blocking = $true
                        [void]$UDPClient.Send($UDPPacket, $UDPPacket.Length)
                        $BytesRecived = $UDPClient.Receive([ref]$UDPEndpoint)
                        # Skip first three characters, since those contain trash data (SSRP metadata)
                        #$Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived[3..($BytesRecived.Length - 1)])
                        $Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived)
                        #endregion Connect to browser service and receive response

                        #region Parse Output
                        $Response | Select-String "(ServerName;(\w+);InstanceName;(\w+);IsClustered;(\w+);Version;(\d+\.\d+\.\d+\.\d+);(tcp;(\d+)){0,1})" -AllMatches | Select-Object -ExpandProperty Matches | ForEach-Object {
                            $obj = New-Object Sqlcollaborative.Dbatools.Discovery.DbaBrowserReply -Property @{
                                MachineName  = $computer.ComputerName
                                ComputerName = $_.Groups[2].Value
                                SqlInstance  = "$($_.Groups[2].Value)\$($_.Groups[3].Value)"
                                InstanceName = $_.Groups[3].Value
                                Version      = $_.Groups[5].Value
                                IsClustered  = "Yes" -eq $_.Groups[4].Value
                            }
                            if ($_.Groups[7].Success) {
                                $obj.TCPPort = $_.Groups[7].Value
                            }
                            $obj
                        }
                        #endregion Parse Output

                        $UDPClient.Close()
                    } catch {
                        try {
                            $UDPClient.Close()
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }

                        if ($EnableException) { throw }
                    }
                }
            }
        }

        function Test-TcpPort {
            <#
            .SYNOPSIS
                Tests whether a TCP Port is open or not.

            .DESCRIPTION
                Tests whether a TCP Port is open or not.

            .PARAMETER ComputerName
                The name of the computer to scan.

            .PARAMETER Port
                The port(s) to scan.

            .EXAMPLE
                PS C:\> $ports | Test-TcpPort -ComputerName "foo"

                Tests for each port in $ports whether the TCP port is open on computer "foo"
        #>
            [CmdletBinding()]
            param (
                [DbaInstance]$ComputerName,
                [Parameter(ValueFromPipeline)][int[]]$Port
            )

            begin {
                $client = New-Object Net.Sockets.TcpClient
            }
            process {
                foreach ($item in $Port) {
                    try {
                        $client.Connect($ComputerName.ComputerName, $item)
                        if ($client.Connected) {
                            $client.Close()
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $true
                        } else {
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                        }
                    } catch {
                        New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                    }
                }
            }
        }

        function Get-IPrange {
            <#
            .SYNOPSIS
                Get the IP addresses in a range

            .DESCRIPTION
                A detailed description of the Get-IPrange function.

            .PARAMETER Start
                A description of the Start parameter.

            .PARAMETER End
                A description of the End parameter.

            .PARAMETER IPAddress
                A description of the IPAddress parameter.

            .PARAMETER Mask
                A description of the Mask parameter.

            .PARAMETER Cidr
                A description of the Cidr parameter.

            .EXAMPLE
                Get-IPrange -Start 192.168.8.2 -End 192.168.8.20

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.2 -Mask 255.255.255.0

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.3 -Cidr 24

            .NOTES
                Author: BarryCWT
                Reference: https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b
        #>

            param
            (
                [string]$Start,
                [string]$End,
                [string]$IPAddress,
                [string]$Mask,
                [int]$Cidr
            )

            function IP-toINT64 {
                param ($ip)

                $octets = $ip.split(".")
                return [int64]([int64]$octets[0] * 16777216 + [int64]$octets[1] * 65536 + [int64]$octets[2] * 256 + [int64]$octets[3])
            }

            function INT64-toIP {
                param ([int64]$int)

                return ([System.Net.IPAddress](([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring()))
            }

            if ($Cidr) {
                $maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $Cidr + "0" * (32 - $Cidr)), 2))))
            }
            if ($Mask) {
                $maskaddr = [Net.IPAddress]::Parse($Mask)
            }
            if ($IPAddress) {
                $ipaddr = [Net.IPAddress]::Parse($IPAddress)
                $networkaddr = New-Object net.ipaddress ($maskaddr.address -band $ipaddr.address)
                $broadcastaddr = New-Object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))
                $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring
                $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring
            } else {
                $startaddr = IP-toINT64 -ip $Start
                $endaddr = IP-toINT64 -ip $End
            }

            for ($i = $startaddr; $i -le $endaddr; $i++) {
                INT64-toIP -int $i
            }
        }

        function Resolve-IPRange {
            <#
            .SYNOPSIS
                Returns a number of IPAddresses based on range specified.

            .DESCRIPTION
                Returns a number of IPAddresses based on range specified.
                Warning: A too large range can lead to memory exceptions.

                Scans subnet of active computer if no address is specified.

            .PARAMETER IpAddress
                The address / range / mask / cidr to scan. Example input:
                - 10.1.1.1
                - 10.1.1.1/24
                - 10.1.1.1-10.1.1.254
                - 10.1.1.1/255.255.255.0
        #>
            [CmdletBinding()]
            param (
                [AllowEmptyString()][string]$IpAddress
            )

            #region Scan defined range
            if ($IpAddress) {
                #region Determine processing mode
                $mode = 'Unknown'
                if ($IpAddress -like "*/*") {
                    $parts = $IpAddress.Split("/")

                    $address = $parts[0]
                    if ($parts[1] -match ([dbargx]::IPv4)) {
                        $mask = $parts[1]
                        $mode = 'Mask'
                    } elseif ($parts[1] -as [int]) {
                        $cidr = [int]$parts[1]

                        if (($cidr -lt 8) -or ($cidr -gt 31)) {
                            Stop-Function -Message "$IpAddress does not contain a valid cidr mask"
                            return
                        }

                        $mode = 'CIDR'
                    } else {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                    }
                } elseif ($IpAddress -like "*-*") {
                    $rangeStart = $IpAddress.Split("-")[0]
                    $rangeEnd = $IpAddress.Split("-")[1]

                    if ($rangeStart -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }
                    if ($rangeEnd -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }

                    $mode = 'Range'
                } else {
                    if ($IpAddress -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP address"
                        return
                    }
                    return $IpAddress
                }
                #endregion Determine processing mode

                switch ($mode) {
                    'CIDR' {
                        Get-IPrange -IPAddress $address -Cidr $cidr
                    }
                    'Mask' {
                        Get-IPrange -IPAddress $address -Mask $mask
                    }
                    'Range' {
                        Get-IPrange -Start $rangeStart -End $rangeEnd
                    }
                }
            }
            #endregion Scan defined range

            #region Scan own computer range
            else {
                foreach ($interface in ([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object NetworkInterfaceType -Like '*Ethernet*')) {
                    foreach ($property in ($interface.GetIPProperties().UnicastAddresses | Where-Object { $_.Address.AddressFamily -like "InterNetwork" })) {
                        Get-IPrange -IPAddress $property.Address -Cidr $property.PrefixLength
                    }
                }
            }
            #endregion Scan own computer range
        }
        #endregion Utility Functions

        #region Build parameter Splat for scan
        $paramTestSqlInstance = @{
            ScanType          = $ScanType
            TCPPort           = $TCPPort
            EnableException   = $EnableException
            MinimumConfidence = $MinimumConfidence
        }

        # Only specify when passed by user to avoid credential prompts on PS3/4
        if ($SqlCredential) {
            $paramTestSqlInstance["SqlCredential"] = $SqlCredential
        }
        if ($Credential) {
            $paramTestSqlInstance["Credential"] = $Credential
        }
        if ($DomainController) {
            $paramTestSqlInstance["DomainController"] = $DomainController
        }
        #endregion Build parameter Splat for scan

        # Prepare item processing in a pipeline compliant way
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Test-SqlInstance', [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = {
            & $wrappedCmd @paramTestSqlInstance
        }
        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($true)
    }

    process {
        if (Test-FunctionInterrupt) { return }
        #region Process items or discover stuff
        switch ($PSCmdlet.ParameterSetName) {
            'Computer' {
                $ComputerName | Invoke-SteppablePipeline -Pipeline $steppablePipeline
            }
            'Discover' {
                #region Discovery: DataSource Enumeration
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DataSourceEnumeration)) {
                    try {
                        # Discover instances
                        foreach ($instance in ([Microsoft.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources())) {
                            if ($instance.InstanceName -ne [System.DBNull]::Value) {
                                $steppablePipeline.Process("$($instance.Servername)\$($instance.InstanceName)")
                            } else {
                                $steppablePipeline.Process($instance.Servername)
                            }
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Datasource enumeration failed" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: DataSource Enumeration

                #region Discovery: SPN Search
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainSPN)) {
                    try {
                        Get-DomainSPN -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Service Principal Name discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: SPN Search

                #region Discovery: IP Range
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::IPRange)) {
                    if ($IpAddress) {
                        foreach ($address in $IpAddress) {
                            Resolve-IPRange -IpAddress $address | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                        }
                    } else {
                        Resolve-IPRange | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    }
                }
                #endregion Discovery: IP Range

                #region Discovery: Windows Server Search
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainServer)) {
                    try {
                        Get-DomainServer -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Windows Server discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: Windows Server Search
            }
            "Default" {
                Stop-Function -Message "Please specify DiscoveryType or ScanType. Try Get-Help Find-DbaInstance -Examples for working examples." -EnableException $EnableException
                return
            }
            default {
                Stop-Function -Message "Invalid parameterset, some developer probably had a beer too much. Please file an issue so we can fix this." -EnableException $EnableException
                return
            }
        }
        #endregion Process items or discover stuff
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        $steppablePipeline.End()
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWfn2PcRExuXTQIC2k6KOuoT+
# fM+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIvidyUgVzbjhPmORGG3Kk9DHsiQMA0GCSqGSIb3DQEBAQUABIIBADG8zIhT
# WFggbfW+NQC+OoDEA0VBvgV75cYFKVBN5faCbgWFr2pkpJpR5/LXVqejNxdkxP6t
# /UriaUdDL63mE4eEgTtFaC27ebR1PmmJtVWFDmJ4Dko8WvxpneIfiTvLpAuajymm
# orQKa8zkKoBQTBd94j3J0NZ9xN7pAVnt1PP/7CP6I9+ImzOPg23ElFpkzPGcmj24
# wjKKBoVrYgCqwhSBS8Jz8UaUdnhVzfozq3sDpFHz9tsWTFIKsQxjuYEDoIn0omHN
# TqtQPf806VF9dTzI5XG7L/9hnhIBzlogT9ipBOC0NRpqJe+63XEXOd0Rj8Hg4Pfc
# d1Sn/K+Fw8nLg32hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwNlowLwYJKoZIhvcNAQkEMSIEIMrw24suxj522X3FdiMzAhdg5fWQ
# +Bxtg1MxlEhCf7VhMA0GCSqGSIb3DQEBAQUABIIBAC0gMBod4fJrGEsNcAdg/uT7
# kTXEIee3ElaTwRWwvUdkPOTqhSM6627FMJDub5Wj0gLKFuaxAwEsIDuacWTLlKbe
# EhC7FTRLlRuTBcnyb+EmlOsgfmmDLJQ4ovCZ3ZkbnuJSjNVW8C2KJKEozz2tDHx8
# jAkIWCzb3sy0mFHISOegQiPdmCF7sSXVjliC1Q1SRrmMIc0t5RmGCWEDUkX/qig4
# WGbfZIdOn2QDzIOxWH/hpFNsbmslkwuOs/NQef+7zWMuzhlmdO5zrh1w/n+it0nQ
# MFyt8lj7jFGrHxirA04UGmunnmIdYDbLSR6Dl447RMGYD7+kOePX6dCbEcwwkks=
# SIG # End signature block
