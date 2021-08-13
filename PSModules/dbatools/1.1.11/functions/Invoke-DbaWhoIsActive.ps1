function Invoke-DbaWhoIsActive {
    <#
    .SYNOPSIS
        Outputs results of Adam Machanic's sp_WhoIsActive DataTable

    .DESCRIPTION
        Output results of Adam Machanic's sp_WhoIsActive

        This command was built with Adam's permission. To read more about sp_WhoIsActive, please visit:

        Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

        Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER Database
        The database where sp_WhoIsActive is installed. Defaults to master. If the sp_WhoIsActive is not installed, the command will warn and exit.

    .PARAMETER Filter
        FiltersBoth inclusive and exclusive
        Set either filter to '' to disable
        Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
        All other filter types support % or _ as wildcards

    .PARAMETER FilterType
        Valid filter types are: session, program, database, login, and host

    .PARAMETER NotFilter
        FiltersBoth inclusive and exclusive
        Set either filter to '' to disable
        Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
        All other filter types support % or _ as wildcards

    .PARAMETER NotFilterType
        Valid filter types are: session, program, database, login, and host

    .PARAMETER ShowOwnSpid
        Retrieve data about the calling session?

    .PARAMETER ShowSystemSpids
        Retrieve data about system sessions?

    .PARAMETER ShowSleepingSpids
        Controls how sleeping SPIDs are handled, based on the idea of levels of interest
        0 does not pull any sleeping SPIDs
        1 pulls only those sleeping SPIDs that also have an open transaction
        2 pulls all sleeping SPIDs

    .PARAMETER GetFullInnerText
        If 1, gets the full stored procedure or running batch, when available
        If 0, gets only the actual statement that is currently running in the batch or procedure

    .PARAMETER GetPlans
        Get associated query plans for running tasks, if available
        If 1, gets the plan based on the request's statement offset
        If 2, gets the entire plan based on the request's plan_handle

    .PARAMETER GetOuterCommand
        Get the associated outer ad hoc query or stored procedure call, if available

    .PARAMETER GetTransactionInfo
        Enables pulling transaction log write info and transaction duration

    .PARAMETER GetTaskInfo
        Get information on active tasks, based on three interest levels
        Level 0 does not pull any task-related information
        Level 1 is a lightweight mode that pulls the top non-CXPACKET wait, giving preference to blockers
        Level 2 pulls all available task-based metrics, including:
        number of active tasks, current wait stats, physical I/O, context switches, and blocker information

    .PARAMETER GetLocks
        Gets associated locks for each request, aggregated in an XML format

    .PARAMETER GetAverageTime
        Get average time for past runs of an active query
        (based on the combination of plan handle, sql handle, and offset)

    .PARAMETER GetAdditonalInfo
        Get additional non-performance-related information about the session or request text_size, language, date_format, date_first, quoted_identifier, arithabort, ansi_null_dflt_on, ansi_defaults, ansi_warnings, ansi_padding, ansi_nulls, concat_null_yields_null, transaction_isolation_level, lock_timeout, deadlock_priority, row_count, command_type

        If a SQL Agent job is running, an subnode called agent_info will be populated with some or all of the following: job_id, job_name, step_id, step_name, msdb_query_error (in the event of an error)

        If @get_task_info is set to 2 and a lock wait is detected, a subnode called block_info will be populated with some or all of the following: lock_type, database_name, object_id, file_id, hobt_id, applock_hash, metadata_resource, metadata_class_id, object_name, schema_name

    .PARAMETER FindBlockLeaders
        Walk the blocking chain and count the number of
        total SPIDs blocked all the way down by a given session
        Also enables task_info Level 1, if @get_task_info is set to 0

    .PARAMETER DeltaInterval
        Pull deltas on various metrics
        Interval in seconds to wait before doing the second data pull

    .PARAMETER OutputColumnList
        List of desired output columns, in desired order
        Note that the final output will be the intersection of all enabled features and all columns in the list. Therefore, only columns associated with enabled features will actually appear in the output. Likewise, removing columns from this list may effectively disable features, even if they are turned on

        Each element in this list must be one of the valid output column names. Names must be delimited by square brackets. White space, formatting, and additional characters are allowed, as long as the list contains exact matches of delimited valid column names.

    .PARAMETER SortOrder
        Column(s) by which to sort output, optionally with sort directions.
        Valid column choices:
        session_id, physical_io, reads, physical_reads, writes, tempdb_allocations,
        tempdb_current, CPU, context_switches, used_memory, physical_io_delta,
        reads_delta, physical_reads_delta, writes_delta, tempdb_allocations_delta,
        tempdb_current_delta, CPU_delta, context_switches_delta, used_memory_delta,
        tasks, tran_start_time, open_tran_count, blocking_session_id, blocked_session_count,
        percent_complete, host_name, login_name, database_name, start_time, login_time

        Note that column names in the list must be bracket-delimited. Commas and/or white space are not required.

    .PARAMETER FormatOutput
        Formats some of the output columns in a more "human readable" form
        0 disables output format
        1 formats the output for variable-width fonts
        2 formats the output for fixed-width fonts

    .PARAMETER DestinationTable
        If set to a non-blank value, the script will attempt to insert into the specified destination table. Please note that the script will not verify that the table exists, or that it has the correct schema, before doing the insert. Table can be specified in one, two, or three-part format

    .PARAMETER ReturnSchema
        If set to 1, no data collection will happen and no result set will be returned; instead, a CREATE TABLE statement will be returned via the @schema parameter, which will match the schema of the result set that would be returned by using the same collection of the rest of the parameters. The CREATE TABLE statement will have a placeholder token of <table_name> in place of an actual table name.

    .PARAMETER Schema
        If set to 1, no data collection will happen and no result set will be returned; instead, a CREATE TABLE statement will be returned via the @schema parameter, which will match the schema of the result set that would be returned by using the same collection of the rest of the parameters. The CREATE TABLE statement will have a placeholder token of <table_name> in place of an actual table name.

    .PARAMETER Help
        Help! What do I do?

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, WhoIsActive
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        http://whoisactive.com

    .LINK
        https://dbatools.io/Invoke-DbaWhoIsActive

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the master database. Logs into the SQL Server with Windows credentials.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $credential -Database dbatools

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the dbatools database. Logs into the SQL Server with SQL Authentication.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetAverageTime

        Similar to running sp_WhoIsActive @get_avg_time

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetOuterCommand -FindBlockLeaders

        Similar to running sp_WhoIsActive @get_outer_command = 1, @find_block_leaders = 1
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object]$Database,
        [Alias('As')]
        [ValidateLength(0, 128)]
        [string]$Filter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$FilterType = 'Session',
        [ValidateLength(0, 128)]
        [string]$NotFilter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$NotFilterType = 'Session',
        [switch]$ShowOwnSpid,
        [switch]$ShowSystemSpids,
        [ValidateRange(0, 255)]
        [int]$ShowSleepingSpids,
        [switch]$GetFullInnerText,
        [ValidateRange(0, 255)]
        [int]$GetPlans,
        [switch]$GetOuterCommand,
        [switch]$GetTransactionInfo,
        [ValidateRange(0, 2)]
        [int]$GetTaskInfo,
        [switch]$GetLocks,
        [switch]$GetAverageTime,
        [switch]$GetAdditonalInfo,
        [switch]$FindBlockLeaders,
        [ValidateRange(0, 255)]
        [int]$DeltaInterval,
        [ValidateLength(0, 8000)]
        [string]$OutputColumnList = '[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]',
        [ValidateLength(0, 500)]
        [string]$SortOrder = '[start_time] ASC',
        [ValidateRange(0, 255)]
        [int]$FormatOutput = 1,
        [ValidateLength(0, 4000)]
        [string]$DestinationTable = '',
        [switch]$ReturnSchema,
        [string]$Schema,
        [switch]$Help,
        [switch]$EnableException
    )
    begin {
        $passedParams = $psboundparameters.Keys | Where-Object { 'Silent', 'SqlServer', 'SqlCredential', 'OutputAs', 'ServerInstance', 'SqlInstance', 'Database' -notcontains $_ }
        $localParams = $psboundparameters
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -lt 9) {
                throw "sp_WhoIsActive is only supported in SQL Server 2005 and above"
            }

            $paramDictionary = @{
                Filter             = '@filter'
                FilterType         = '@filter_type'
                NotFilter          = 'not_filter'
                NotFilterType      = '@not_filter_type'
                ShowOwnSpid        = '@show_own_spid'
                ShowSystemSpids    = '@show_system_spids'
                ShowSleepingSpids  = '@show_sleeping_spids'
                GetFullInnerText   = '@get_full_inner_text'
                GetPlans           = '@get_plans'
                GetOuterCommand    = '@get_outer_command'
                GetTransactionInfo = '@get_transaction_info'
                GetTaskInfo        = '@get_task_info'
                GetLocks           = '@get_locks '
                GetAverageTime     = '@get_avg_time'
                GetAdditonalInfo   = '@get_additional_info'
                FindBlockLeaders   = '@find_block_leaders'
                DeltaInterval      = '@delta_interval'
                OutputColumnList   = '@output_column_list'
                SortOrder          = '@sort_order'
                FormatOutput       = '@format_output '
                DestinationTable   = '@destination_table '
                ReturnSchema       = '@return_schema'
                Schema             = '@schema'
                Help               = '@help'
            }

            Write-Message -Level Verbose -Message "Collecting sp_whoisactive data from server: $instance"
            try {
                $sqlConnection = New-Object Microsoft.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = $server.ConnectionContext.ConnectionString
                $sqlConnection.Open()

                if ($Database) {
                    # database is being returned as something weird. change it to string without using a method then trim.
                    $Database = "$Database"
                    $Database = $Database.Trim()
                    $sqlConnection.ChangeDatabase($Database)
                }

                $sqlCommand = New-Object Microsoft.Data.SqlClient.SqlCommand
                $sqlCommand.CommandType = "StoredProcedure"
                $sqlCommand.CommandText = "dbo.sp_WhoIsActive"
                $sqlCommand.Connection = $sqlConnection

                foreach ($param in $passedParams) {
                    Write-Message -Level Verbose -Message "Check parameter '$param'"

                    $sqlParam = $paramDictionary[$param]

                    if ($sqlParam) {

                        $value = $localParams[$param]

                        switch ($value) {
                            $true { $value = 1 }
                            $false { $value = 0 }
                        }
                        Write-Message -Level Verbose -Message "Adding parameter '$sqlParam' with value '$value'"
                        [Void]$sqlCommand.Parameters.AddWithValue($sqlParam, $value)
                    }
                }

                $dataTable = New-Object System.Data.DataSet
                $dataAdapter = New-Object Microsoft.Data.SqlClient.SqlDataAdapter($sqlCommand)
                $dataAdapter.fill($dataTable) | Out-Null
                $dataTable.Tables.Rows
            } catch {
                if ($_.Exception.InnerException -Like "*Could not find*") {
                    Stop-Function -Message "sp_whoisactive not found, please install using Install-DbaWhoIsActive." -Continue
                } else {
                    Stop-Function -Message "Invalid query." -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULwOjhK4kqppGj1a39gnQXoB3
# sMmgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFL/fVoC7UJp4Px8B/yxpv+n2rMdkMA0GCSqGSIb3DQEBAQUABIIBACg9eK2f
# pQ1C3w9b0zNb2OSsWTnEXGFHElsXO2u3CETUqxfMBTrogjamUvzqMtGlusciUVpr
# S2RuPnKNo3vWSOMYDNMWwTneDZf+y4I7AoiGzcT77DT7IpVCxqbvvkbgeYAcbLO1
# DGWe/xoY3BgGYs6T+IuE1KY7rCdN/0OnlY/eKL/23P0NJbn4Sz4WCtL55dUn1SyQ
# vtbb8IE1N9OC8tRrxnMUi/diG0U7s0206yxcrZEI3Tna9N7KOJtEqtno37Rkr+tA
# A8QQ825Eo4ODiGug9br0/+p3aiccYHQEMRXvuB/ay3c6qH4dQMZ0Zm0mldNo0vOG
# kkBntv565LBXOzChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzN1owLwYJKoZIhvcNAQkEMSIEIFtULX7UB0j2bYlPLIibrw+0Vy+z
# +pVZ2LnWews/KeahMA0GCSqGSIb3DQEBAQUABIIBAFNFBlTweG6KGlO7Oado/uux
# ZPvJzNxngnEwmaCjgLcS5leCqxDf8RVmzkLBgvlA9PMF3rUwBUcMKnYdXQzOOeN4
# yVedYz5MUpMDMZ3hBsfhTh5MCVmLMdR0gcUXiAUQ0ChctUQN+oO1+VSo4eu1twyD
# leH5lkv/AP7I29WOhxXAVhbD5LcHdmuPbjY/1T1x8RQac4NyyKiffGNrnpUe3VV4
# MCByDFqps/WWUUYJA+zD85pWEpkBRdKVBUVQQcb512Wo8o7B3eEilwSCCt+p6K5L
# nlyX4oW/eQMut8nO1rNx37zSt7pTaZxoKrQq1TGwvM6QiQLmoToCQjtpGPzquGs=
# SIG # End signature block
