function Remove-DbaAgentAlertCategory {
    <#
    .SYNOPSIS
        Remove-DbaAgentAlertCategory removes an alert category.

    .DESCRIPTION
        Remove-DbaAgentAlertCategory makes it possible to remove an alert category.
        Insure that the category you want to remove is not used with any alerts. If an alert uses this category it will be get the category [Uncategorized].

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert, AlertCategory
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentAlertCategory

    .EXAMPLE
        PS C:\> Remove-DbaAgentAlertCategory -SqlInstance sql1 -Category 'Category 1'

        Remove the alert category Category 1 from the instance.

    .EXAMPLE
        PS C:\> Remove-DbaAgentAlertCategory -SqlInstance sql1 -Category Category1, Category2, Category3

        Remove multiple alert categories from the instance.

    .EXAMPLE
        PS C:\> Remove-DbaAgentAlertCategory -SqlInstance sql1, sql2, sql3 -Category Category1, Category2, Category3

        Remove multiple alert categories from the multiple instances.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cat in $Category) {
                if ($cat -notin $server.JobServer.AlertCategories.Name) {
                    Stop-Function -Message "Alert category $cat doesn't exist on $instance" -Target $instance -Continue
                }

                if ($PSCmdlet.ShouldProcess($instance, "Removing the alert category $Category")) {
                    try {
                        $currentCategory = $server.JobServer.AlertCategories[$cat]

                        Write-Message -Message "Removing alert category $cat" -Level Verbose

                        $currentCategory.Drop()
                    } catch {
                        Stop-Function -Message "Something went wrong removing the alert category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                    }
                }
            }
        }
    }
}