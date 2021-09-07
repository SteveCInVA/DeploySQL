﻿@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'PendingReboot.psm1'

    # Version number of this module.
    ModuleVersion = '0.9.0.6'

    # ID used to uniquely identify this module
    GUID = '7c868fa4-b23e-4994-b74a-e938aef933dd'

    # Author of this module
    Author = 'Brian Wilhite'

    # Copyright statement for this module
    Copyright = '(c) 2018 Brian Wilhite. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Module to detect Windows OS pending reboots.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '3.0'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @('Test-PendingReboot')

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('PendingReboot')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/bcwilhite/PendingReboot/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/bcwilhite/PendingReboot/'
        }
    }
}
