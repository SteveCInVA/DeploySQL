@{
    # Version number of this module.
    moduleVersion      = '15.1.1'

    # ID used to uniquely identify this module
    GUID               = '693ee082-ed36-45a7-b490-88b07c86b42f'

    # Author of this module
    Author             = 'DSC Community'

    # Company or vendor of this module
    CompanyName        = 'DSC Community'

    # Copyright statement for this module
    Copyright          = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description        = 'Module with DSC resources for deployment and configuration of Microsoft SQL Server.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion  = '5.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion         = '4.0'

    # Functions to export from this module
    FunctionsToExport  = @()

    # Cmdlets to export from this module
    CmdletsToExport    = @()

    # Variables to export from this module
    VariablesToExport  = @()

    # Aliases to export from this module
    AliasesToExport    = @()

    DscResourcesToExport = @('SqlAG','SqlAGDatabase','SqlAgentAlert','SqlAgentFailsafe','SqlAgentOperator','SqlAGListener','SqlAGReplica','SqlAlias','SqlAlwaysOnService','SqlConfiguration','SqlDatabase','SqlDatabaseDefaultLocation','SqlDatabaseMail','SqlDatabaseObjectPermission','SqlDatabasePermission','SqlDatabaseRole','SqlDatabaseUser','SqlEndpoint','SqlEndpointPermission','SqlLogin','SqlMaxDop','SqlMemory','SqlPermission','SqlProtocol','SqlProtocolTcpIp','SqlReplication','SqlRole','SqlRS','SqlRSSetup','SqlScript','SqlScriptQuery','SqlSecureConnection','SqlServiceAccount','SqlSetup','SqlTraceFlag','SqlWaitForAG','SqlWindowsFirewall','SqlDatabaseOwner','SqlDatabaseRecoveryModel','SqlServerEndpointState','SqlServerNetwork')

    RequiredAssemblies = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData        = @{

        PSData = @{
            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease   = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/SqlServerDsc/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/SqlServerDsc'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [15.1.1] - 2021-02-12

### Fixed

- SqlTraceFlag
  - Fixed `$null` reference error when no actual trace flags are present.
    Added two arrays to prevent a `$null` reference at compare-object
    ([issue #1688](https://github.com/dsccommunity/SqlServerDsc/issues/1688)).
- SqlServerDsc
  - Removed a left-over comment in the file `analyzersettings.psd1`.

'

        } # End of PSData hashtable

    } # End of PrivateData hashtable
}




