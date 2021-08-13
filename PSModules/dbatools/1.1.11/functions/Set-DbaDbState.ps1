function Set-DbaDbState {
    <#
    .SYNOPSIS
        Sets various options for databases, hereby called "states"

    .DESCRIPTION
        Sets some common "states" on databases:
        - "RW" options (ReadOnly, ReadWrite)
        - "Status" options (Online, Offline, Emergency, plus a special "Detached")
        - "Access" options (SingleUser, RestrictedUser, MultiUser)

        Returns an object with SqlInstance, Database, RW, Status, Access, Notes

        Notes gets filled when something went wrong setting the state

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. if unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllDatabases
        This is a parameter that was included for safety, so you don't accidentally set options on all databases without specifying

    .PARAMETER ReadOnly
        RW Option : Sets the database as READ_ONLY

    .PARAMETER ReadWrite
        RW Option : Sets the database as READ_WRITE

    .PARAMETER Online
        Status Option : Sets the database as ONLINE

    .PARAMETER Offline
        Status Option : Sets the database as OFFLINE

    .PARAMETER Emergency
        Status Option : Sets the database as EMERGENCY

    .PARAMETER Detached
        Status Option : Detaches the database

    .PARAMETER SingleUser
        Access Option : Sets the database as SINGLE_USER

    .PARAMETER RestrictedUser
        Access Option : Sets the database as RESTRICTED_USER

    .PARAMETER MultiUser
        Access Option : Sets the database as MULTI_USER

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        For most options, this translates to instantly rolling back any open transactions
        that may be stopping the process.
        For -Detached it is required to break mirroring and Availability Groups

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Accepts piped database objects

    .NOTES
        Tags: Database, State
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbState

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -Offline

        Sets the HR database as OFFLINE

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -AllDatabases -Exclude HR -ReadOnly -Force

        Sets all databases of the sqlserver2014a instance, except for HR, as READ_ONLY

    .EXAMPLE
        PS C:\> Get-DbaDbState -SqlInstance sql2016 | Where-Object Status -eq 'Offline' | Set-DbaDbState -Online

        Finds all offline databases and sets them to online

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -SingleUser

        Sets the HR database as SINGLE_USER

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -SingleUser -Force

        Sets the HR database as SINGLE_USER, dropping all other connections (and rolling back open transactions)

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR | Set-DbaDbState -SingleUser -Force

        Gets the databases from Get-DbaDatabase, and sets them as SINGLE_USER, dropping all other connections (and rolling back open transactions)

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [switch]$ReadOnly,
        [switch]$ReadWrite,
        [switch]$Online,
        [switch]$Offline,
        [switch]$Emergency,
        [switch]$Detached,
        [switch]$SingleUser,
        [switch]$RestrictedUser,
        [switch]$MultiUser,
        [switch]$Force,
        [switch]$EnableException,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Database")]
        [PsCustomObject[]]$InputObject
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function Get-WrongCombo($optset, $allParams) {
            $x = 0
            foreach ($opt in $optset) {
                if ($allParams.ContainsKey($opt)) { $x += 1 }
            }
            if ($x -gt 1) {
                $msg = $optset -Join ',-'
                $msg = "You can only specify one of: -" + $msg
                throw $msg
            }
        }

        function Edit-DatabaseState($SqlInstance, $dbName, $opt, $immediate = $false) {
            $warn = $null
            $sql = "ALTER DATABASE [$dbName] SET $opt"
            if ($immediate) {
                $sql += " WITH ROLLBACK IMMEDIATE"
            } else {
                $sql += " WITH NO_WAIT"
            }
            try {
                Write-Message -Level System -Message $sql
                if ($immediate) {
                    # this can be helpful only for SINGLE_USER databases
                    # but since $immediate is called, it does no more harm
                    # than the immediate rollback
                    try {
                        $SqlInstance.KillAllProcesses($dbName)
                    } catch {
                        Write-Message -Level Verbose -Message "KillAllProcesses failed, moving on to WITH ROLLBACK IMMEDIATE"
                    }
                }
                $null = $SqlInstance.Query($sql)
            } catch {
                $warn = "Failed to set '$dbName' to $opt"
                Write-Message -Level Warning -Message $warn
            }
            return $warn
        }

        $statusHash = @{
            'Offline'       = 'OFFLINE'
            'Normal'        = 'ONLINE'
            'EmergencyMode' = 'EMERGENCY'
        }

        function Get-DbState($databaseName, $dbStatuses) {
            $base = $dbStatuses | Where-Object DatabaseName -ceq $databaseName
            foreach ($status in $statusHash.Keys) {
                if ($base.Status -match $status) {
                    $base.Status = $statusHash[$status]
                    break
                }
            }
            return $base
        }

        $RWExclusive = @('ReadOnly', 'ReadWrite')
        $statusExclusive = @('Online', 'Offline', 'Emergency', 'Detached')
        $accessExclusive = @('SingleUser', 'RestrictedUser', 'MultiUser')
        $allParams = $PSBoundParameters
        try {
            Get-WrongCombo -optset $RWExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
        try {
            Get-WrongCombo -optset $statusExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
        try {
            Get-WrongCombo -optset $accessExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $dbs = @()
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue"
            return
        }

        if ($InputObject) {
            if ($InputObject.Database) {
                # comes from Get-DbaDbState
                $dbs += $InputObject.Database
            } elseif ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $all_dbs = $server.Databases
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }

                if ($database) {
                    $dbs = $dbs | Where-Object { $database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # need to pick up here
        foreach ($db in $dbs) {
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $db is a system one, skipping"
                Continue
            }
            $dbStatuses = @{ }
            $server = $db.Parent
            if ($server -notin $dbStatuses.Keys) {
                $dbStatuses[$server] = Get-DbaDbState -SqlInstance $server
            }

            # normalizing properties returned by SMO to something more "fixed"
            $db_status = Get-DbState -DatabaseName $db.Name -dbStatuses $dbStatuses[$server]


            $warn = @()

            if ($db.DatabaseSnapshotBaseName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $db is a snapshot, skipping"
                Continue
            }

            if ($ReadOnly -eq $true) {
                if ($db_status.RW -eq 'READ_ONLY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_ONLY"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_ONLY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_ONLY"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_ONLY" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_ONLY'
                        }
                    }
                }
            }

            if ($ReadWrite -eq $true) {
                if ($db_status.RW -eq 'READ_WRITE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_WRITE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_WRITE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_WRITE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_WRITE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_WRITE'
                        }
                    }
                }
            }

            if ($Online -eq $true) {
                if ($db_status.Status -eq 'ONLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already ONLINE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to ONLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to ONLINE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "ONLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'ONLINE'
                        }
                    }
                }
            }

            if ($Offline -eq $true) {
                if ($db_status.Status -eq 'OFFLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already OFFLINE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to OFFLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to OFFLINE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'OFFLINE'
                        }
                    }
                }
            }

            if ($Emergency -eq $true) {
                if ($db_status.Status -eq 'EMERGENCY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already EMERGENCY"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to EMERGENCY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to EMERGENCY"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "EMERGENCY" -immediate $Force
                        if (!$partial) {
                            $db_status.Status = 'EMERGENCY'
                        }
                    }
                }
            }

            if ($SingleUser -eq $true) {
                if ($db_status.Access -eq 'SINGLE_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already SINGLE_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to SINGLE_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to SINGLE_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "SINGLE_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'SINGLE_USER'
                        }
                    }
                }
            }

            if ($RestrictedUser -eq $true) {
                if ($db_status.Access -eq 'RESTRICTED_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already RESTRICTED_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to RESTRICTED_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to RESTRICTED_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "RESTRICTED_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'RESTRICTED_USER'
                        }
                    }
                }
            }

            if ($MultiUser -eq $true) {
                if ($db_status.Access -eq 'MULTI_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already MULTI_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to MULTI_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to MULTI_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "MULTI_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'MULTI_USER'
                        }
                    }
                }
            }

            if ($Detached -eq $true) {
                # Refresh info about database state here (before detaching)
                $db.Refresh()
                # we need to see what snaps are on the server, as base databases cannot be dropped
                $snaps = $server.Databases | Where-Object { $_.DatabaseSnapshotBaseName.Length -gt 0 }
                $snaps = $snaps.DatabaseSnapshotBaseName | Get-Unique
                if ($db.Name -in $snaps) {
                    Write-Message -Level Warning -Message "Database $db has snapshots, you need to drop them before detaching, skipping..."
                    Continue
                }
                if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                    if ($Force -eq $false) {
                        Write-Message -Level Warning -Message "Needs -Force to detach $db, skipping"
                        Continue
                    }
                }

                if ($db.IsMirroringEnabled) {
                    if ($Pscmdlet.ShouldProcess($server, "Break mirroring for $db")) {
                        try {
                            $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                            $db.Alter()
                            $db.Refresh()
                            Write-Message -Level VeryVerbose -Message "Broke mirroring for $db"
                        } catch {
                            Stop-Function -Message "Could not break mirror for $db. Skipping." -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }

                if ($db.AvailabilityGroupName) {
                    $agname = $db.AvailabilityGroupName
                    if ($Pscmdlet.ShouldProcess($server, "Removing $db from AG [$agname]")) {
                        try {
                            $server.AvailabilityGroups[$db.AvailabilityGroupName].AvailabilityDatabases[$db.Name].Drop()
                            Write-Message -Level VeryVerbose -Message "Successfully removed $db from AG [$agname] on $server"
                        } catch {
                            Stop-Function -Message "Could not remove $db from AG [$agname] on $server" -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }

                # DBA 101 should encourage detaching just OFFLINE databases
                # we can do that here
                if ($Pscmdlet.ShouldProcess($server, "Detaching $db")) {
                    if ($db_status.Status -ne 'OFFLINE') {
                        $null = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $true
                    }
                    try {
                        $sql = "EXEC master.dbo.sp_detach_db N'$($db.Name)'"
                        Write-Message -Level System -Message $sql
                        $null = $server.Query($sql)
                        $db_status.Status = 'DETACHED'
                    } catch {
                        Stop-Function -Message "Failed to detach $db" -ErrorRecord $_ -Target $server -Continue
                        $warn += "Failed to detach"
                    }

                }

            }
            if ($warn) {
                $warn = $warn | Where-Object { $_ } | Get-Unique
                $warn = $warn -Join ';'
            } else {
                $warn = $null
            }
            if ($Detached -eq $true) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $db_status.RW
                    Status       = $db_status.Status
                    Access       = $db_status.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            } else {
                $db.Refresh()
                if ($null -eq $warn) {
                    # we avoid reenumerating properties
                    $newstate = $db_status
                } else {
                    $newstate = Get-DbState -databaseName $db.Name -dbStatuses $dbStatuses[$server]
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $newstate.RW
                    Status       = $newstate.Status
                    Access       = $newstate.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            }
        }

    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUY1+kAyEBcFQ3XVWZOoFS/Mct
# DDOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFP3eOvgpDOGRX7pXxyhu209Vh6FXMA0GCSqGSIb3DQEBAQUABIIBADUcLEiV
# Mu+fWHRVt/oF4Rk7KJt89I096UIUZJSL+fKF0s+pq/AYrxW8RoooovHCvTZUNYP7
# 5Fcl96q6pY5YgfWmq+QP0Etx1dDrZvkvsTvoJ0VQUU2/ldXfSAUSQle2yAguLXo5
# U+6tTce1pLgWrLIkEMTFs1S/E0+GuA161ETPdXYG2T8GZr6LPV6k455aKKNeNkjd
# Y+/3m6Npj+5ap8FeWW1Cnk2KygRT2Q+GHChwGn9V/QA9pJ+CQqSlBM/XPyHCU0AN
# XqSlrKIvHBYpMAH9ivZ/MAs7+Zq3YqwWBz7MTeQwclrhnunePZ4ZMrTz0lsqZXFG
# IfdujWHRSz1PLg6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjU1NVowLwYJKoZIhvcNAQkEMSIEIDcN2DSZod77JB/HjbJdP/wPOI6l
# gbCTFfGNNjBpqpOcMA0GCSqGSIb3DQEBAQUABIIBAKTXK73BbhUzkAaOiHFo+voN
# EjXEt8PQmOsu0ctOI4/vkFAkx0lpi4NVMNWwANlCj+1PcA5Vsf6pdM+/zQ4quagR
# EtnqxiHj/PNL1PWyw9IBXeHadDiQjfiP3/VR2zcOS+Mcxp6q5RZgBeOJblQgNi8s
# V2m89eikidUrdtwOb2Cjty9KzpGpxyzWhGZfJrgTc/lDsJi/qRbStQscc5hVMiI+
# VObKv9ulZFUYU5vDr9a6n+p9Ax6NZ2D9JliZpzPkDVdVroulc+mLIsJTLK5dBNY6
# wa0ht7Xe8qJ9vCmJo4Mexe00S/plwi/9bQYbFBcTpj8oxzFukKrboD36+/H7VbM=
# SIG # End signature block
