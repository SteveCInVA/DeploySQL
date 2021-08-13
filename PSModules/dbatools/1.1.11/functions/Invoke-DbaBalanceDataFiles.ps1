function Invoke-DbaBalanceDataFiles {
    <#
    .SYNOPSIS
        Re-balance data between data files

    .DESCRIPTION
        When you have a large database with a single data file and add another file, SQL Server will only use the new file until it's about the same size.
        You may want to balance the data between all the data files.

        The function will check the server version and edition to see if the it allows for online index rebuilds.
        If the server does support it, it will try to rebuild the index online.
        If the server doesn't support it, it will rebuild the index offline. Be carefull though, this can cause downtime

        The tables must have a clustered index to be able to balance out the data.
        The function does NOT yet support heaps.

        The function will also check if the file groups are subject to balance out.
        A file group whould have at least have 2 data files and should be writable.
        If a table is within such a file group it will be subject for processing. If not the table will be skipped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER Table
        The tables(s) of the database to process. If unspecified, all tables will be processed.

    .PARAMETER RebuildOffline
        Will set all the indexes to rebuild offline.
        This option is also needed when the server version is below 2005.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        The server does not support online rebuilds of indexes.
        Do you want to rebuild the indexes offline?
        [Y] Yes  [N] No   [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        This will disable the check for enough disk space for the action to be successful.
        Use this with caution!!

    .NOTES
        Tags: Database, FileManagement, File, Space
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaBalanceDataFiles

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 | Select-Object -ExpandProperty DataFilesEnd

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -Table table1,table2,table5

        This command will distribute the data for only the tables table1,table2 and table5

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -RebuildOffline

        This command will consider the fact that there might be a SQL Server edition that does not support online rebuilds of indexes.
        By supplying this parameter you give permission to do the rebuilds offline if the edition does not support it.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Singular Noun doesn't make sense")]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [Alias("Tables")]
        [object[]]$Table,
        [switch]$RebuildOffline,
        [switch]$EnableException,
        [switch]$Force
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        Write-Message -Message "Starting balancing out data files" -Level Verbose

        # Set the initial success flag
        [bool]$success = $true

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check the database parameter
            if ($Database) {
                if ($Database -notin $server.Databases.Name) {
                    Stop-Function -Message "One or more databases cannot be found on instance on instance $instance" -Target $instance -Continue
                }

                $DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
            } else {
                Stop-Function -Message "Please supply a database to balance out" -Target $instance -Continue
            }

            # Get the server version
            $serverVersion = $server.Version.Major

            # Check edition of the sql instance
            if ($RebuildOffline) {
                Write-Message -Message "Continuing with offline rebuild." -Level Verbose
            } elseif (-not $RebuildOffline -and ($serverVersion -lt 9 -or (([string]$Server.Edition -notmatch "Developer") -and ($Server.Edition -notmatch "Enterprise")))) {
                # Set up the confirm part
                $message = "The server does not support online rebuilds of indexes. `nDo you want to rebuild the indexes offline?"
                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                # Check the result from the confirm
                switch ($result) {
                    # If yes
                    0 {
                        # Set the option to generate a full backup
                        Write-Message -Message "Continuing with offline rebuild." -Level Verbose

                        [bool]$supportOnlineRebuild = $false
                    }
                    1 {
                        Stop-Function -Message "You chose to not allow offline rebuilds of indexes. Use -RebuildOffline" -Target $instance
                        return
                    }
                } # switch
            } elseif ($serverVersion -ge 9 -and (([string]$Server.Edition -like "Developer*") -or ($Server.Edition -like "Enterprise*"))) {
                [bool]$supportOnlineRebuild = $true
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {
                $dataFilesStarting = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                if (-not $Force) {
                    # Check the amount of disk space available
                    $query = "SELECT SUBSTRING(physical_name, 0, 4) AS 'Drive' ,
                                        SUM(( size * 8 ) / 1024) AS 'SizeMB'
                                FROM	sys.master_files
                                WHERE	DB_NAME(database_id) = '$($db.Name)'
                                GROUP BY SUBSTRING(physical_name, 0, 4)"
                    # Execute the query
                    try {
                        $dbDiskUsage = $Server.Query($query)
                    } catch {
                        $errormsg = Get-ErrorMessage -Record $PSItem
                        Stop-Function -Message "$errormsg" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # Get the free space for each drive
                    try {
                        $result = $Server.Query("xp_fixeddrives")
                    } catch {
                        Stop-Function -Message "Error occurred while finding free space on drives" -ErrorRecord $_ -Target $instance -Continue
                    }
                    $MbFreeColName = $result[0].psobject.Properties.Name[1]
                    $diskFreeSpace = $result | Select-Object Drive, @{ Name = 'FreeMB'; Expression = { $_.$MbFreeColName } }

                    # Loop through each of the drives to see if the size of files on that
                    # particular disk do not exceed the free space of that disk
                    foreach ($d in $dbDiskUsage) {
                        $freeSpace = $diskFreeSpace | Where-Object { $_.Drive -eq $d.Drive.Trim(':\') } | Select-Object FreeMB
                        if ($d.SizeMB -gt $freeSpace.FreeMB) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "The available space may not be sufficient to continue the process. Please use -Force to try anyway." -Target $instance -Continue
                            return
                        }
                    }
                }

                # Create the start time
                $start = Get-Date

                # Check if the function needs to continue
                if ($success) {

                    # Get the database files before all the alterations
                    Write-Message -Message "Retrieving data files before data move" -Level Verbose
                    Write-Message -Message "Processing database $db" -Level Verbose

                    # Check the datafiles of the database
                    $dataFiles = Get-DbaDbFile -SqlInstance $server -Database $db | Where-Object { $_.TypeDescription -eq 'ROWS' }
                    if ($dataFiles.Count -eq 1) {
                        # Set the success flag
                        $success = $false

                        Stop-Function -Message "Database $db only has one data file. Please add a data file to balance out the data" -Target $instance -Continue
                    }

                    # Check the tables parameter
                    if ($Table) {
                        if ($Table -notin $db.Table) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "One or more tables cannot be found in database $db on instance $instance" -Target $instance -Continue
                        }

                        $tableCollection = $db.Tables | Where-Object { $_.Name -in $Table }
                    } else {
                        $tableCollection = $db.Tables
                    }

                    # Get the database file groups and check the aount of data files
                    Write-Message -Message "Retrieving file groups" -Level Verbose
                    $fileGroups = $Server.Databases[$db.Name].FileGroups

                    # ARray to hold the file groups with properties
                    $balanceableTables = @()

                    # Loop through each of the file groups

                    foreach ($fg in $fileGroups) {

                        # If there is less than 2 files balancing out data is not possible
                        if (($fg.Files.Count -ge 2) -and ($fg.Readonly -eq $false)) {
                            $balanceableTables += $fg.EnumObjects() | Where-Object { $_.GetType().Name -eq 'Table' }
                        }
                    }

                    $unsuccessfulTables = @()

                    # Loop through each of the tables
                    foreach ($tbl in $tableCollection) {

                        # Chck if the table balanceable
                        if ($tbl.Name -in $balanceableTables.Name) {

                            Write-Message -Message "Processing table $tbl" -Level Verbose

                            # Chck the tables and get the clustered indexes
                            if ($tableCollection.Indexes.Count -lt 1) {
                                # Set the success flag
                                $success = $false

                                Stop-Function -Message "Table $tbl does not contain any indexes" -Target $instance -Continue
                            } else {

                                # Get all the clustered indexes for the table
                                $clusteredIndexes = $tableCollection.Indexes | Where-Object { $_.IndexType -eq 'ClusteredIndex' }

                                if ($clusteredIndexes.Count -lt 1) {
                                    # Set the success flag
                                    $success = $false

                                    Stop-Function -Message "No clustered indexes found in table $tbl" -Target $instance -Continue
                                }
                            }

                            # Loop through each of the clustered indexes and rebuild them
                            Write-Message -Message "$($clusteredIndexes.Count) clustered index(es) found for table $tbl" -Level Verbose
                            if ($PSCmdlet.ShouldProcess("Rebuilding indexes to balance data")) {
                                foreach ($ci in $clusteredIndexes) {

                                    Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose

                                    # Get the original index operation
                                    [bool]$originalIndexOperation = $ci.OnlineIndexOperation

                                    # Set the rebuild option to be either offline or online
                                    if ($RebuildOffline) {
                                        $ci.OnlineIndexOperation = $false
                                    } elseif ($serverVersion -ge 9 -and $supportOnlineRebuild -and -not $RebuildOffline) {
                                        Write-Message -Message "Setting the index operation for index $($ci.Name) to online" -Level Verbose
                                        $ci.OnlineIndexOperation = $true
                                    }

                                    # Rebuild the index
                                    try {
                                        Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose
                                        $ci.Rebuild()

                                        # Set the success flag
                                        $success = $true
                                    } catch {
                                        # Set the original index operation back for the index
                                        $ci.OnlineIndexOperation = $originalIndexOperation

                                        # Set the success flag
                                        $success = $false

                                        Stop-Function -Message "Something went wrong rebuilding index $($ci.Name). `n$($_.Exception.Message)" -ErrorRecord $_ -Target $instance -Continue
                                    }

                                    # Set the original index operation back for the index
                                    Write-Message -Message "Setting the index operation for index $($ci.Name) back to the original value" -Level Verbose
                                    $ci.OnlineIndexOperation = $originalIndexOperation

                                } # foreach index

                            } # if process

                        } # if table is balanceable
                        else {
                            # Add the table to the unsuccessful array
                            $unsuccessfulTables += $tbl.Name

                            # Set the success flag
                            $success = $false

                            Write-Message -Message "Table $tbl cannot be balanced out" -Level Verbose
                        }

                    } #foreach table
                }

                # Create the end time
                $end = Get-Date

                # Create the time span
                $timespan = New-TimeSpan -Start $start -End $end
                $ts = [timespan]::fromseconds($timespan.TotalSeconds)
                $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                # Get the database files after all the alterations
                Write-Message -Message "Retrieving data files after data move" -Level Verbose
                $dataFilesEnding = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                [pscustomobject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Database       = $db.Name
                    Start          = $start
                    End            = $end
                    Elapsed        = $elapsed
                    Success        = $success
                    Unsuccessful   = $unsuccessfulTables -join ","
                    DataFilesStart = $dataFilesStarting
                    DataFilesEnd   = $dataFilesEnding
                }

            } # foreach database

        } # end process
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUvgOyeMlA1xQNg01M9o+qy4Kr
# ExGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFDHVlF3wdwSk36bi8qP4fCkLHTEMA0GCSqGSIb3DQEBAQUABIIBAE15fl5f
# 3jGdDmlkxD8BxJO9BMHda3DBv5uEndBw6QltdmieMD3+VtaMhQaY//qWIXGwnhrD
# LF5uhhwro05JmpUcKsFzc+1bmjCkacNdR2PVJD3tXKrO036Q7vZqkGJxg5HW2Uum
# YZwpSYUJ0oAXilk6WDvI/noXUANzSEj40YKjIGpCaRdvDyw+gQkGhwMu9kPZKSIK
# ksmF4TRXbEg2RfOvSwgKMXX5u/irvAtdWwGd5jwNVqh7ev4/z9YCyVUcCDaHOG7o
# e0krz9OGF9oVADJiwWOdkcdsBriuYeS0uvJTX6Q0pySUpE4ql3CpD71BKkM3QxVl
# cXHczTEY/U+efFyhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzNFowLwYJKoZIhvcNAQkEMSIEIFlRBlm0M1OVt4AljE77h8W4330C
# DiUC1+OraJjp7ZZHMA0GCSqGSIb3DQEBAQUABIIBAHDtQAqozkdA+6YHxhZa9pjW
# GN3cpFNf8QVihFj8UwozCOmo1jRTG2nqIUSvy2a7YUXePT+4Ia7tjswNeZzvuZY5
# WNd8hHCMvc1+Sd7Otmbwf4p/Y0oWS8HryNg34wVr4ZMtJ00Ejc38f9aI3rDfTocC
# wFRGlEfu+fx36/M23CuTLnKCp/Uq4rx70f2i/ZvgvE0bYJ89ywhaxqXgaALvs6sp
# 1JmTZoz+3op7Cifpk+3OR0pQIvVJ0UBwubpRJnTEz2qUxDr4hjMU9vwiX6NcGrlT
# RL8LtIcGhAUvdW29EYsL/hG7ww4BJ8TOCLYjL1tWz/Ir9gyt/yGNCh4ndGYupls=
# SIG # End signature block
