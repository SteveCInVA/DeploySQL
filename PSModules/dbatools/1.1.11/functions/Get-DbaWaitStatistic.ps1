function Get-DbaWaitStatistic {
    <#
    .SYNOPSIS
        Displays wait statistics

    .DESCRIPTION
        This command is based off of Paul Randal's post "Wait statistics, or please tell me where it hurts"

        Returns:
        WaitType
        Category
        WaitSeconds
        ResourceSeconds
        SignalSeconds
        WaitCount
        Percentage
        AverageWaitSeconds
        AverageResourceSeconds
        AverageSignalSeconds
        URL

        Reference: https://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Threshold
        Threshold, in percentage of all waits on the system. Default per Paul's post is 95%.

    .PARAMETER IncludeIgnorable
        Some waits are no big deal and can be safely ignored in most circumstances. If you've got weird issues with mirroring or AGs.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WaitStatistic
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWaitStatistic

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008, sqlserver2012

        Check wait statistics for servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008 -Threshold 98 -IncludeIgnorable

        Check wait statistics on server sql2008 for thresholds above 98% and include wait stats that are most often, but not always, ignorable

    .EXAMPLE
        PS C:\> Get-DbaWaitStatistic -SqlInstance sql2008 | Select-Object *

        Shows detailed notes, if available, from Paul's post

    .EXAMPLE
        PS C:\> $output = Get-DbaWaitStatistic -SqlInstance sql2008 -Threshold 100 -IncludeIgnorable | Select-Object * | ConvertTo-DbaDataTable

        Collects all Wait Statistics (including ignorable waits) on server sql2008 into a Data Table.

    .EXAMPLE
        PS C:\> $output = Get-DbaWaitStatistic -SqlInstance sql2008
        PS C:\> foreach ($row in ($output | Sort-Object -Unique Url)) { Start-Process ($row).Url }

        Displays the output then loads the associated sqlskills website for each result. Opens one tab per unique URL.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 95,
        [switch]$IncludeIgnorable,
        [switch]$EnableException
    )

    begin {

        $details = [pscustomobject]@{
            CXPACKET                         = "This indicates parallelism, not necessarily that there's a problem. The coordinator thread in a parallel query always accumulates these waits. If the parallel threads are not given equal amounts of work to do, or one thread blocks, the waiting threads will also accumulate CXPACKET waits, which will make them aggregate a lot faster - this is a problem. One thread may have a lot more to do than the others, and so the whole query is blocked while the long-running thread completes. If this is combined with a high number of PAGEIOLATCH_XX waits, it could be large parallel table scans going on because of incorrect non-clustered indexes, or a bad query plan. If neither of these are the issue, you might want to try setting MAXDOP to 4, 2, or 1 for the offending queries (or possibly the whole instance). Make sure that if you have a NUMA system that you try setting MAXDOP to the number of cores in a single NUMA node first to see if that helps the problem. You also need to consider the MAXDOP effect on a mixed-load system. Play with the cost threshold for parallelism setting (bump it up to, say, 25) before reducing the MAXDOP of the whole instance. And don't forget Resource Governor in Enterprise Edition of  SQL Server 2008 onward that allows DOP governing for a particular group of connections to the server."
            PAGEIOLATCH_XX                   = "This is where SQL Server is waiting for a data page to be read from disk into memory. It may indicate a bottleneck at the IO subsystem level (which is a common knee-jerk response to seeing these), but why is the I/O subsystem having to service so many reads? It could be buffer pool/memory pressure (i.e. not enough memory for the workload), a sudden change in query plans causing a large parallel scan instead of a seek, plan cache bloat, or a number of other things. Don't assume the root cause is the I/O subsystem."
            ASYNC_NETWORK_IO                 = "This is usually where SQL Server is waiting for a client to finish consuming data. It could be that the client has asked for a very large amount of data or just that it's consuming it reeeeeally slowly because of poor programming - I rarely see this being a network issue. Clients often process one row at a time - called RBAR or Row-By-Agonizing-Row - instead of caching the data on the client and acknowledging to SQL Server immediately."
            WRITELOG                         = "This is the log management system waiting for a log flush to disk. It commonly indicates that the I/O subsystem can't keep up with the log flush volume, but on very high-volume systems it could also be caused by internal log flush limits, that may mean you have to split your workload over multiple databases or even make your transactions a little longer to reduce log flushes. To be sure it is the I/O subsystem, use the DMV sys.dm_io_virtual_file_stats to examine the I/O latency for the log file and see if it correlates to the average WRITELOG time. If WRITELOG is longer, you've got internal contention and need to shard. If not, investigate why you're creating so much transaction log."
            BROKER_RECEIVE_WAITFOR           = "This is just Service Broker waiting around for new messages to receive. I would add this to the list of waits to filter out and re-run the wait stats query."
            MSQL_XP                          = "This is SQL Server waiting for an extended stored-proc to finish. This could indicate a problem in your XP code."
            OLEDB                            = "As its name suggests, this is a wait for something communicating using OLEDB - e.g. a linked server. However, OLEDB is also used by all DMVs and by DBCC CHECKDB, so don't assume linked servers are the problem - it could be a third-party monitoring tool making excessive DMV calls. If it *is* a linked server (wait times in the 10s or 100s of milliseconds), go to the linked server and do wait stats analysis there to figure out what the performance issue is there."
            BACKUPIO                         = "This can show up when you're backing up to a slow I/O subsystem, like directly to tape, which is slooooow, or over a network."
            LCK_M_XX                         = "This is simply the thread waiting for a lock to be granted and indicates blocking problems. These could be caused by unwanted lock escalation or bad programming, but could also be from I/Os taking a long time causing locks to be held for longer than usual. Look at the resource associated with the lock using the DMV sys.dm_os_waiting_tasks. Don't assume that locking is the root cause."
            ONDEMAND_TASK_QUEUE              = "This is normal and is part of the background task system (e.g. deferred drop, ghost cleanup).  I would add this to the list of waits to filter out and re-run the wait stats query."
            BACKUPBUFFER                     = "This commonly show up with BACKUPIO and is a backup thread waiting for a buffer to write backup data into."
            IO_COMPLETION                    = "This is SQL Server waiting for non-data page I/Os to complete and could be an indication that the I/O subsystem is overloaded if the latencies look high (see Are I/O latencies killing your performance?)"
            SOS_SCHEDULER_YIELD              = "This is code running that doesn't hit any resource waits."
            DBMIRROR_EVENTS_QUEUE            = "These two are database mirroring just sitting around waiting for something to do. I would add these to the list of waits to filter out and re-run the wait stats query."
            DBMIRRORING_CMD                  = "These two are database mirroring just sitting around waiting for something to do. I would add these to the list of waits to filter out and re-run the wait stats query."
            PAGELATCH_XX                     = "This is contention for access to in-memory copies of pages. The most well-known cases of these are the PFS and SGAM contention that can occur in tempdb under certain workloads. To find out what page the contention is on, you'll need to use the DMV sys.dm_os_waiting_tasks to figure out what page the latch is for. For tempdb issues, Robert Davis (blog | twitter) has a good post showing how to do this. Another common cause I've seen is an index hot-spot with concurrent inserts into an index with an identity value key."
            LATCH_XX                         = "This is contention for some non-page structure inside SQL Server - so not related to I/O or data at all. These can be hard to figure out and you're going to be using the DMV sys.dm_os_latch_stats. More on this in my Latches category."
            PREEMPTIVE_OS_PIPEOPS            = "This is SQL Server switching to preemptive scheduling mode to call out to Windows for something, and this particular wait is usually from using xp_cmdshell. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            THREADPOOL                       = "This says that there aren't enough worker threads on the system to satisfy demand. Commonly this is large numbers of high-DOP queries trying to execute and taking all the threads from the thread pool."
            BROKER_TRANSMITTER               = "This is just Service Broker waiting around for new messages to send. I would add this to the list of waits to filter out and re-run the wait stats query."
            SQLTRACE_WAIT_ENTRIES            = "Part of SQL Trace. I would add this to the list of waits to filter out and re-run the wait stats query."
            DBMIRROR_DBM_MUTEX               = "This one is undocumented and is contention for the send buffer that database mirroring shares between all the mirroring sessions on a server. It could indicate that you've got too many mirroring sessions."
            RESOURCE_SEMAPHORE               = "This is queries waiting for execution memory (the memory used to process the query operators - like a sort). This could be memory pressure or a very high concurrent workload."
            PREEMPTIVE_OS_AUTHENTICATIONOPS  = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_GENERICOPS         = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            SLEEP_BPOOL_FLUSH                = "This is normal to see and indicates that checkpoint is throttling itself to avoid overloading the IO subsystem. I would add this to the list of waits to filter out and re-run the wait stats query."
            MSQL_DQ                          = "This is SQL Server waiting for a distributed query to finish. This could indicate a problem with the distributed query, or it could just be normal."
            RESOURCE_SEMAPHORE_QUERY_COMPILE = "When there are too many concurrent query compilations going on, SQL Server will throttle them. I don't remember the threshold, but this can indicate excessive recompilation, or maybe single-use plans."
            DAC_INIT                         = "This is the Dedicated Admin Connection initializing."
            MSSEARCH                         = "This is normal to see for full-text operations.  If this is the highest wait, it could mean your system is spending most of its time doing full-text queries. You might want to consider adding this to the filter list."
            PREEMPTIVE_OS_FILEOPS            = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_LIBRARYOPS         = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_LOOKUPACCOUNTSID   = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            PREEMPTIVE_OS_QUERYREGISTRY      = "These are SQL Server switching to preemptive scheduling mode to call out to Windows for something. These were added for 2008 and aren't documented anywhere except through the links to my waits library."
            SQLTRACE_LOCK                    = "Part of SQL Trace. I would add this to the list of waits to filter out and re-run the wait stats query."
        }

        # Thanks Brent Ozar via https://gist.github.com/BrentOzar/42e82ee0603a1917c17d74c3fca26d34
        # Thanks Marcin Gminski via https://www.dropbox.com/s/x3zr7u18tc1ojey/WaitStats.sql?dl=0

        $category = [pscustomobject]@{
            ASYNC_IO_COMPLETION                             = 'Other Disk IO'
            ASYNC_NETWORK_IO                                = 'Network IO'
            BACKUPIO                                        = 'Other Disk IO'
            BROKER_CONNECTION_RECEIVE_TASK                  = 'Service Broker'
            BROKER_DISPATCHER                               = 'Service Broker'
            BROKER_ENDPOINT_STATE_MUTEX                     = 'Service Broker'
            BROKER_EVENTHANDLER                             = 'Service Broker'
            BROKER_FORWARDER                                = 'Service Broker'
            BROKER_INIT                                     = 'Service Broker'
            BROKER_MASTERSTART                              = 'Service Broker'
            BROKER_RECEIVE_WAITFOR                          = 'User Wait'
            BROKER_REGISTERALLENDPOINTS                     = 'Service Broker'
            BROKER_SERVICE                                  = 'Service Broker'
            BROKER_SHUTDOWN                                 = 'Service Broker'
            BROKER_START                                    = 'Service Broker'
            BROKER_TASK_SHUTDOWN                            = 'Service Broker'
            BROKER_TASK_STOP                                = 'Service Broker'
            BROKER_TASK_SUBMIT                              = 'Service Broker'
            BROKER_TO_FLUSH                                 = 'Service Broker'
            BROKER_TRANSMISSION_OBJECT                      = 'Service Broker'
            BROKER_TRANSMISSION_TABLE                       = 'Service Broker'
            BROKER_TRANSMISSION_WORK                        = 'Service Broker'
            BROKER_TRANSMITTER                              = 'Service Broker'
            CHECKPOINT_QUEUE                                = 'Idle'
            CHKPT                                           = 'Tran Log IO'
            CLR_AUTO_EVENT                                  = 'SQL CLR'
            CLR_CRST                                        = 'SQL CLR'
            CLR_JOIN                                        = 'SQL CLR'
            CLR_MANUAL_EVENT                                = 'SQL CLR'
            CLR_MEMORY_SPY                                  = 'SQL CLR'
            CLR_MONITOR                                     = 'SQL CLR'
            CLR_RWLOCK_READER                               = 'SQL CLR'
            CLR_RWLOCK_WRITER                               = 'SQL CLR'
            CLR_SEMAPHORE                                   = 'SQL CLR'
            CLR_TASK_START                                  = 'SQL CLR'
            CLRHOST_STATE_ACCESS                            = 'SQL CLR'
            CMEMPARTITIONED                                 = 'Memory'
            CMEMTHREAD                                      = 'Memory'
            CXPACKET                                        = 'Parallelism'
            DBMIRROR_DBM_EVENT                              = 'Mirroring'
            DBMIRROR_DBM_MUTEX                              = 'Mirroring'
            DBMIRROR_EVENTS_QUEUE                           = 'Mirroring'
            DBMIRROR_SEND                                   = 'Mirroring'
            DBMIRROR_WORKER_QUEUE                           = 'Mirroring'
            DBMIRRORING_CMD                                 = 'Mirroring'
            DTC                                             = 'Transaction'
            DTC_ABORT_REQUEST                               = 'Transaction'
            DTC_RESOLVE                                     = 'Transaction'
            DTC_STATE                                       = 'Transaction'
            DTC_TMDOWN_REQUEST                              = 'Transaction'
            DTC_WAITFOR_OUTCOME                             = 'Transaction'
            DTCNEW_ENLIST                                   = 'Transaction'
            DTCNEW_PREPARE                                  = 'Transaction'
            DTCNEW_RECOVERY                                 = 'Transaction'
            DTCNEW_TM                                       = 'Transaction'
            DTCNEW_TRANSACTION_ENLISTMENT                   = 'Transaction'
            DTCPNTSYNC                                      = 'Transaction'
            EE_PMOLOCK                                      = 'Memory'
            EXCHANGE                                        = 'Parallelism'
            EXTERNAL_SCRIPT_NETWORK_IOF                     = 'Network IO'
            FCB_REPLICA_READ                                = 'Replication'
            FCB_REPLICA_WRITE                               = 'Replication'
            FT_COMPROWSET_RWLOCK                            = 'Full Text Search'
            FT_IFTS_RWLOCK                                  = 'Full Text Search'
            FT_IFTS_SCHEDULER_IDLE_WAIT                     = 'Idle'
            FT_IFTSHC_MUTEX                                 = 'Full Text Search'
            FT_IFTSISM_MUTEX                                = 'Full Text Search'
            FT_MASTER_MERGE                                 = 'Full Text Search'
            FT_MASTER_MERGE_COORDINATOR                     = 'Full Text Search'
            FT_METADATA_MUTEX                               = 'Full Text Search'
            FT_PROPERTYLIST_CACHE                           = 'Full Text Search'
            FT_RESTART_CRAWL                                = 'Full Text Search'
            'FULLTEXT GATHERER'                             = 'Full Text Search'
            HADR_AG_MUTEX                                   = 'Replication'
            HADR_AR_CRITICAL_SECTION_ENTRY                  = 'Replication'
            HADR_AR_MANAGER_MUTEX                           = 'Replication'
            HADR_AR_UNLOAD_COMPLETED                        = 'Replication'
            HADR_ARCONTROLLER_NOTIFICATIONS_SUBSCRIBER_LIST = 'Replication'
            HADR_BACKUP_BULK_LOCK                           = 'Replication'
            HADR_BACKUP_QUEUE                               = 'Replication'
            HADR_CLUSAPI_CALL                               = 'Replication'
            HADR_COMPRESSED_CACHE_SYNC                      = 'Replication'
            HADR_CONNECTIVITY_INFO                          = 'Replication'
            HADR_DATABASE_FLOW_CONTROL                      = 'Replication'
            HADR_DATABASE_VERSIONING_STATE                  = 'Replication'
            HADR_DATABASE_WAIT_FOR_RECOVERY                 = 'Replication'
            HADR_DATABASE_WAIT_FOR_RESTART                  = 'Replication'
            HADR_DATABASE_WAIT_FOR_TRANSITION_TO_VERSIONING = 'Replication'
            HADR_DB_COMMAND                                 = 'Replication'
            HADR_DB_OP_COMPLETION_SYNC                      = 'Replication'
            HADR_DB_OP_START_SYNC                           = 'Replication'
            HADR_DBR_SUBSCRIBER                             = 'Replication'
            HADR_DBR_SUBSCRIBER_FILTER_LIST                 = 'Replication'
            HADR_DBSEEDING                                  = 'Replication'
            HADR_DBSEEDING_LIST                             = 'Replication'
            HADR_DBSTATECHANGE_SYNC                         = 'Replication'
            HADR_FABRIC_CALLBACK                            = 'Replication'
            HADR_FILESTREAM_BLOCK_FLUSH                     = 'Replication'
            HADR_FILESTREAM_FILE_CLOSE                      = 'Replication'
            HADR_FILESTREAM_FILE_REQUEST                    = 'Replication'
            HADR_FILESTREAM_IOMGR                           = 'Replication'
            HADR_FILESTREAM_IOMGR_IOCOMPLETION              = 'Replication'
            HADR_FILESTREAM_MANAGER                         = 'Replication'
            HADR_FILESTREAM_PREPROC                         = 'Replication'
            HADR_GROUP_COMMIT                               = 'Replication'
            HADR_LOGCAPTURE_SYNC                            = 'Replication'
            HADR_LOGCAPTURE_WAIT                            = 'Replication'
            HADR_LOGPROGRESS_SYNC                           = 'Replication'
            HADR_NOTIFICATION_DEQUEUE                       = 'Replication'
            HADR_NOTIFICATION_WORKER_EXCLUSIVE_ACCESS       = 'Replication'
            HADR_NOTIFICATION_WORKER_STARTUP_SYNC           = 'Replication'
            HADR_NOTIFICATION_WORKER_TERMINATION_SYNC       = 'Replication'
            HADR_PARTNER_SYNC                               = 'Replication'
            HADR_READ_ALL_NETWORKS                          = 'Replication'
            HADR_RECOVERY_WAIT_FOR_CONNECTION               = 'Replication'
            HADR_RECOVERY_WAIT_FOR_UNDO                     = 'Replication'
            HADR_REPLICAINFO_SYNC                           = 'Replication'
            HADR_SEEDING_CANCELLATION                       = 'Replication'
            HADR_SEEDING_FILE_LIST                          = 'Replication'
            HADR_SEEDING_LIMIT_BACKUPS                      = 'Replication'
            HADR_SEEDING_SYNC_COMPLETION                    = 'Replication'
            HADR_SEEDING_TIMEOUT_TASK                       = 'Replication'
            HADR_SEEDING_WAIT_FOR_COMPLETION                = 'Replication'
            HADR_SYNC_COMMIT                                = 'Replication'
            HADR_SYNCHRONIZING_THROTTLE                     = 'Replication'
            HADR_TDS_LISTENER_SYNC                          = 'Replication'
            HADR_TDS_LISTENER_SYNC_PROCESSING               = 'Replication'
            HADR_THROTTLE_LOG_RATE_GOVERNOR                 = 'Log Rate Governor'
            HADR_TIMER_TASK                                 = 'Replication'
            HADR_TRANSPORT_DBRLIST                          = 'Replication'
            HADR_TRANSPORT_FLOW_CONTROL                     = 'Replication'
            HADR_TRANSPORT_SESSION                          = 'Replication'
            HADR_WORK_POOL                                  = 'Replication'
            HADR_WORK_QUEUE                                 = 'Replication'
            HADR_XRF_STACK_ACCESS                           = 'Replication'
            INSTANCE_LOG_RATE_GOVERNOR                      = 'Log Rate Governor'
            IO_COMPLETION                                   = 'Other Disk IO'
            IO_QUEUE_LIMIT                                  = 'Other Disk IO'
            IO_RETRY                                        = 'Other Disk IO'
            LATCH_DT                                        = 'Latch'
            LATCH_EX                                        = 'Latch'
            LATCH_KP                                        = 'Latch'
            LATCH_NL                                        = 'Latch'
            LATCH_SH                                        = 'Latch'
            LATCH_UP                                        = 'Latch'
            LAZYWRITER_SLEEP                                = 'Idle'
            LCK_M_BU                                        = 'Lock'
            LCK_M_BU_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_BU_LOW_PRIORITY                           = 'Lock'
            LCK_M_IS                                        = 'Lock'
            LCK_M_IS_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IS_LOW_PRIORITY                           = 'Lock'
            LCK_M_IU                                        = 'Lock'
            LCK_M_IU_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IU_LOW_PRIORITY                           = 'Lock'
            LCK_M_IX                                        = 'Lock'
            LCK_M_IX_ABORT_BLOCKERS                         = 'Lock'
            LCK_M_IX_LOW_PRIORITY                           = 'Lock'
            LCK_M_RIn_NL                                    = 'Lock'
            LCK_M_RIn_NL_ABORT_BLOCKERS                     = 'Lock'
            LCK_M_RIn_NL_LOW_PRIORITY                       = 'Lock'
            LCK_M_RIn_S                                     = 'Lock'
            LCK_M_RIn_S_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_S_LOW_PRIORITY                        = 'Lock'
            LCK_M_RIn_U                                     = 'Lock'
            LCK_M_RIn_U_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_U_LOW_PRIORITY                        = 'Lock'
            LCK_M_RIn_X                                     = 'Lock'
            LCK_M_RIn_X_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_RIn_X_LOW_PRIORITY                        = 'Lock'
            LCK_M_RS_S                                      = 'Lock'
            LCK_M_RS_S_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RS_S_LOW_PRIORITY                         = 'Lock'
            LCK_M_RS_U                                      = 'Lock'
            LCK_M_RS_U_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RS_U_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_S                                      = 'Lock'
            LCK_M_RX_S_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_S_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_U                                      = 'Lock'
            LCK_M_RX_U_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_U_LOW_PRIORITY                         = 'Lock'
            LCK_M_RX_X                                      = 'Lock'
            LCK_M_RX_X_ABORT_BLOCKERS                       = 'Lock'
            LCK_M_RX_X_LOW_PRIORITY                         = 'Lock'
            LCK_M_S                                         = 'Lock'
            LCK_M_S_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_S_LOW_PRIORITY                            = 'Lock'
            LCK_M_SCH_M                                     = 'Lock'
            LCK_M_SCH_M_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_SCH_M_LOW_PRIORITY                        = 'Lock'
            LCK_M_SCH_S                                     = 'Lock'
            LCK_M_SCH_S_ABORT_BLOCKERS                      = 'Lock'
            LCK_M_SCH_S_LOW_PRIORITY                        = 'Lock'
            LCK_M_SIU                                       = 'Lock'
            LCK_M_SIU_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_SIU_LOW_PRIORITY                          = 'Lock'
            LCK_M_SIX                                       = 'Lock'
            LCK_M_SIX_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_SIX_LOW_PRIORITY                          = 'Lock'
            LCK_M_U                                         = 'Lock'
            LCK_M_U_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_U_LOW_PRIORITY                            = 'Lock'
            LCK_M_UIX                                       = 'Lock'
            LCK_M_UIX_ABORT_BLOCKERS                        = 'Lock'
            LCK_M_UIX_LOW_PRIORITY                          = 'Lock'
            LCK_M_X                                         = 'Lock'
            LCK_M_X_ABORT_BLOCKERS                          = 'Lock'
            LCK_M_X_LOW_PRIORITY                            = 'Lock'
            LOGBUFFER                                       = 'Tran Log IO'
            LOGMGR                                          = 'Tran Log IO'
            LOGMGR_FLUSH                                    = 'Tran Log IO'
            LOGMGR_PMM_LOG                                  = 'Tran Log IO'
            LOGMGR_QUEUE                                    = 'Idle'
            LOGMGR_RESERVE_APPEND                           = 'Tran Log IO'
            MEMORY_ALLOCATION_EXT                           = 'Memory'
            MEMORY_GRANT_UPDATE                             = 'Memory'
            MSQL_XACT_MGR_MUTEX                             = 'Transaction'
            MSQL_XACT_MUTEX                                 = 'Transaction'
            MSSEARCH                                        = 'Full Text Search'
            NET_WAITFOR_PACKET                              = 'Network IO'
            ONDEMAND_TASK_QUEUE                             = 'Idle'
            PAGEIOLATCH_DT                                  = 'Buffer IO'
            PAGEIOLATCH_EX                                  = 'Buffer IO'
            PAGEIOLATCH_KP                                  = 'Buffer IO'
            PAGEIOLATCH_NL                                  = 'Buffer IO'
            PAGEIOLATCH_SH                                  = 'Buffer IO'
            PAGEIOLATCH_UP                                  = 'Buffer IO'
            PAGELATCH_DT                                    = 'Buffer Latch'
            PAGELATCH_EX                                    = 'Buffer Latch'
            PAGELATCH_KP                                    = 'Buffer Latch'
            PAGELATCH_NL                                    = 'Buffer Latch'
            PAGELATCH_SH                                    = 'Buffer Latch'
            PAGELATCH_UP                                    = 'Buffer Latch'
            POOL_LOG_RATE_GOVERNOR                          = 'Log Rate Governor'
            PREEMPTIVE_ABR                                  = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPMEDIA                     = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPTAPE                      = 'Preemptive'
            PREEMPTIVE_CLOSEBACKUPVDIDEVICE                 = 'Preemptive'
            PREEMPTIVE_CLUSAPI_CLUSTERRESOURCECONTROL       = 'Preemptive'
            PREEMPTIVE_COM_COCREATEINSTANCE                 = 'Preemptive'
            PREEMPTIVE_COM_COGETCLASSOBJECT                 = 'Preemptive'
            PREEMPTIVE_COM_CREATEACCESSOR                   = 'Preemptive'
            PREEMPTIVE_COM_DELETEROWS                       = 'Preemptive'
            PREEMPTIVE_COM_GETCOMMANDTEXT                   = 'Preemptive'
            PREEMPTIVE_COM_GETDATA                          = 'Preemptive'
            PREEMPTIVE_COM_GETNEXTROWS                      = 'Preemptive'
            PREEMPTIVE_COM_GETRESULT                        = 'Preemptive'
            PREEMPTIVE_COM_GETROWSBYBOOKMARK                = 'Preemptive'
            PREEMPTIVE_COM_LBFLUSH                          = 'Preemptive'
            PREEMPTIVE_COM_LBLOCKREGION                     = 'Preemptive'
            PREEMPTIVE_COM_LBREADAT                         = 'Preemptive'
            PREEMPTIVE_COM_LBSETSIZE                        = 'Preemptive'
            PREEMPTIVE_COM_LBSTAT                           = 'Preemptive'
            PREEMPTIVE_COM_LBUNLOCKREGION                   = 'Preemptive'
            PREEMPTIVE_COM_LBWRITEAT                        = 'Preemptive'
            PREEMPTIVE_COM_QUERYINTERFACE                   = 'Preemptive'
            PREEMPTIVE_COM_RELEASE                          = 'Preemptive'
            PREEMPTIVE_COM_RELEASEACCESSOR                  = 'Preemptive'
            PREEMPTIVE_COM_RELEASEROWS                      = 'Preemptive'
            PREEMPTIVE_COM_RELEASESESSION                   = 'Preemptive'
            PREEMPTIVE_COM_RESTARTPOSITION                  = 'Preemptive'
            PREEMPTIVE_COM_SEQSTRMREAD                      = 'Preemptive'
            PREEMPTIVE_COM_SEQSTRMREADANDWRITE              = 'Preemptive'
            PREEMPTIVE_COM_SETDATAFAILURE                   = 'Preemptive'
            PREEMPTIVE_COM_SETPARAMETERINFO                 = 'Preemptive'
            PREEMPTIVE_COM_SETPARAMETERPROPERTIES           = 'Preemptive'
            PREEMPTIVE_COM_STRMLOCKREGION                   = 'Preemptive'
            PREEMPTIVE_COM_STRMSEEKANDREAD                  = 'Preemptive'
            PREEMPTIVE_COM_STRMSEEKANDWRITE                 = 'Preemptive'
            PREEMPTIVE_COM_STRMSETSIZE                      = 'Preemptive'
            PREEMPTIVE_COM_STRMSTAT                         = 'Preemptive'
            PREEMPTIVE_COM_STRMUNLOCKREGION                 = 'Preemptive'
            PREEMPTIVE_CONSOLEWRITE                         = 'Preemptive'
            PREEMPTIVE_CREATEPARAM                          = 'Preemptive'
            PREEMPTIVE_DEBUG                                = 'Preemptive'
            PREEMPTIVE_DFSADDLINK                           = 'Preemptive'
            PREEMPTIVE_DFSLINKEXISTCHECK                    = 'Preemptive'
            PREEMPTIVE_DFSLINKHEALTHCHECK                   = 'Preemptive'
            PREEMPTIVE_DFSREMOVELINK                        = 'Preemptive'
            PREEMPTIVE_DFSREMOVEROOT                        = 'Preemptive'
            PREEMPTIVE_DFSROOTFOLDERCHECK                   = 'Preemptive'
            PREEMPTIVE_DFSROOTINIT                          = 'Preemptive'
            PREEMPTIVE_DFSROOTSHARECHECK                    = 'Preemptive'
            PREEMPTIVE_DTC_ABORT                            = 'Preemptive'
            PREEMPTIVE_DTC_ABORTREQUESTDONE                 = 'Preemptive'
            PREEMPTIVE_DTC_BEGINTRANSACTION                 = 'Preemptive'
            PREEMPTIVE_DTC_COMMITREQUESTDONE                = 'Preemptive'
            PREEMPTIVE_DTC_ENLIST                           = 'Preemptive'
            PREEMPTIVE_DTC_PREPAREREQUESTDONE               = 'Preemptive'
            PREEMPTIVE_FILESIZEGET                          = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_ABORTTRANSACTION            = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_COMMITTRANSACTION           = 'Preemptive'
            PREEMPTIVE_FSAOLEDB_STARTTRANSACTION            = 'Preemptive'
            PREEMPTIVE_FSRECOVER_UNCONDITIONALUNDO          = 'Preemptive'
            PREEMPTIVE_GETRMINFO                            = 'Preemptive'
            PREEMPTIVE_HADR_LEASE_MECHANISM                 = 'Preemptive'
            PREEMPTIVE_HTTP_EVENT_WAIT                      = 'Preemptive'
            PREEMPTIVE_HTTP_REQUEST                         = 'Preemptive'
            PREEMPTIVE_LOCKMONITOR                          = 'Preemptive'
            PREEMPTIVE_MSS_RELEASE                          = 'Preemptive'
            PREEMPTIVE_ODBCOPS                              = 'Preemptive'
            PREEMPTIVE_OLE_UNINIT                           = 'Preemptive'
            PREEMPTIVE_OLEDB_ABORTORCOMMITTRAN              = 'Preemptive'
            PREEMPTIVE_OLEDB_ABORTTRAN                      = 'Preemptive'
            PREEMPTIVE_OLEDB_GETDATASOURCE                  = 'Preemptive'
            PREEMPTIVE_OLEDB_GETLITERALINFO                 = 'Preemptive'
            PREEMPTIVE_OLEDB_GETPROPERTIES                  = 'Preemptive'
            PREEMPTIVE_OLEDB_GETPROPERTYINFO                = 'Preemptive'
            PREEMPTIVE_OLEDB_GETSCHEMALOCK                  = 'Preemptive'
            PREEMPTIVE_OLEDB_JOINTRANSACTION                = 'Preemptive'
            PREEMPTIVE_OLEDB_RELEASE                        = 'Preemptive'
            PREEMPTIVE_OLEDB_SETPROPERTIES                  = 'Preemptive'
            PREEMPTIVE_OLEDBOPS                             = 'Preemptive'
            PREEMPTIVE_OS_ACCEPTSECURITYCONTEXT             = 'Preemptive'
            PREEMPTIVE_OS_ACQUIRECREDENTIALSHANDLE          = 'Preemptive'
            PREEMPTIVE_OS_AUTHENTICATIONOPS                 = 'Preemptive'
            PREEMPTIVE_OS_AUTHORIZATIONOPS                  = 'Preemptive'
            PREEMPTIVE_OS_AUTHZGETINFORMATIONFROMCONTEXT    = 'Preemptive'
            PREEMPTIVE_OS_AUTHZINITIALIZECONTEXTFROMSID     = 'Preemptive'
            PREEMPTIVE_OS_AUTHZINITIALIZERESOURCEMANAGER    = 'Preemptive'
            PREEMPTIVE_OS_BACKUPREAD                        = 'Preemptive'
            PREEMPTIVE_OS_CLOSEHANDLE                       = 'Preemptive'
            PREEMPTIVE_OS_CLUSTEROPS                        = 'Preemptive'
            PREEMPTIVE_OS_COMOPS                            = 'Preemptive'
            PREEMPTIVE_OS_COMPLETEAUTHTOKEN                 = 'Preemptive'
            PREEMPTIVE_OS_COPYFILE                          = 'Preemptive'
            PREEMPTIVE_OS_CREATEDIRECTORY                   = 'Preemptive'
            PREEMPTIVE_OS_CREATEFILE                        = 'Preemptive'
            PREEMPTIVE_OS_CRYPTACQUIRECONTEXT               = 'Preemptive'
            PREEMPTIVE_OS_CRYPTIMPORTKEY                    = 'Preemptive'
            PREEMPTIVE_OS_CRYPTOPS                          = 'Preemptive'
            PREEMPTIVE_OS_DECRYPTMESSAGE                    = 'Preemptive'
            PREEMPTIVE_OS_DELETEFILE                        = 'Preemptive'
            PREEMPTIVE_OS_DELETESECURITYCONTEXT             = 'Preemptive'
            PREEMPTIVE_OS_DEVICEIOCONTROL                   = 'Preemptive'
            PREEMPTIVE_OS_DEVICEOPS                         = 'Preemptive'
            PREEMPTIVE_OS_DIRSVC_NETWORKOPS                 = 'Preemptive'
            PREEMPTIVE_OS_DISCONNECTNAMEDPIPE               = 'Preemptive'
            PREEMPTIVE_OS_DOMAINSERVICESOPS                 = 'Preemptive'
            PREEMPTIVE_OS_DSGETDCNAME                       = 'Preemptive'
            PREEMPTIVE_OS_DTCOPS                            = 'Preemptive'
            PREEMPTIVE_OS_ENCRYPTMESSAGE                    = 'Preemptive'
            PREEMPTIVE_OS_FILEOPS                           = 'Preemptive'
            PREEMPTIVE_OS_FINDFILE                          = 'Preemptive'
            PREEMPTIVE_OS_FLUSHFILEBUFFERS                  = 'Preemptive'
            PREEMPTIVE_OS_FORMATMESSAGE                     = 'Preemptive'
            PREEMPTIVE_OS_FREECREDENTIALSHANDLE             = 'Preemptive'
            PREEMPTIVE_OS_FREELIBRARY                       = 'Preemptive'
            PREEMPTIVE_OS_GENERICOPS                        = 'Preemptive'
            PREEMPTIVE_OS_GETADDRINFO                       = 'Preemptive'
            PREEMPTIVE_OS_GETCOMPRESSEDFILESIZE             = 'Preemptive'
            PREEMPTIVE_OS_GETDISKFREESPACE                  = 'Preemptive'
            PREEMPTIVE_OS_GETFILEATTRIBUTES                 = 'Preemptive'
            PREEMPTIVE_OS_GETFILESIZE                       = 'Preemptive'
            PREEMPTIVE_OS_GETFINALFILEPATHBYHANDLE          = 'Preemptive'
            PREEMPTIVE_OS_GETLONGPATHNAME                   = 'Preemptive'
            PREEMPTIVE_OS_GETPROCADDRESS                    = 'Preemptive'
            PREEMPTIVE_OS_GETVOLUMENAMEFORVOLUMEMOUNTPOINT  = 'Preemptive'
            PREEMPTIVE_OS_GETVOLUMEPATHNAME                 = 'Preemptive'
            PREEMPTIVE_OS_INITIALIZESECURITYCONTEXT         = 'Preemptive'
            PREEMPTIVE_OS_LIBRARYOPS                        = 'Preemptive'
            PREEMPTIVE_OS_LOADLIBRARY                       = 'Preemptive'
            PREEMPTIVE_OS_LOGONUSER                         = 'Preemptive'
            PREEMPTIVE_OS_LOOKUPACCOUNTSID                  = 'Preemptive'
            PREEMPTIVE_OS_MESSAGEQUEUEOPS                   = 'Preemptive'
            PREEMPTIVE_OS_MOVEFILE                          = 'Preemptive'
            PREEMPTIVE_OS_NETGROUPGETUSERS                  = 'Preemptive'
            PREEMPTIVE_OS_NETLOCALGROUPGETMEMBERS           = 'Preemptive'
            PREEMPTIVE_OS_NETUSERGETGROUPS                  = 'Preemptive'
            PREEMPTIVE_OS_NETUSERGETLOCALGROUPS             = 'Preemptive'
            PREEMPTIVE_OS_NETUSERMODALSGET                  = 'Preemptive'
            PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICY         = 'Preemptive'
            PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICYFREE     = 'Preemptive'
            PREEMPTIVE_OS_OPENDIRECTORY                     = 'Preemptive'
            PREEMPTIVE_OS_PDH_WMI_INIT                      = 'Preemptive'
            PREEMPTIVE_OS_PIPEOPS                           = 'Preemptive'
            PREEMPTIVE_OS_PROCESSOPS                        = 'Preemptive'
            PREEMPTIVE_OS_QUERYCONTEXTATTRIBUTES            = 'Preemptive'
            PREEMPTIVE_OS_QUERYREGISTRY                     = 'Preemptive'
            PREEMPTIVE_OS_QUERYSECURITYCONTEXTTOKEN         = 'Preemptive'
            PREEMPTIVE_OS_REMOVEDIRECTORY                   = 'Preemptive'
            PREEMPTIVE_OS_REPORTEVENT                       = 'Preemptive'
            PREEMPTIVE_OS_REVERTTOSELF                      = 'Preemptive'
            PREEMPTIVE_OS_RSFXDEVICEOPS                     = 'Preemptive'
            PREEMPTIVE_OS_SECURITYOPS                       = 'Preemptive'
            PREEMPTIVE_OS_SERVICEOPS                        = 'Preemptive'
            PREEMPTIVE_OS_SETENDOFFILE                      = 'Preemptive'
            PREEMPTIVE_OS_SETFILEPOINTER                    = 'Preemptive'
            PREEMPTIVE_OS_SETFILEVALIDDATA                  = 'Preemptive'
            PREEMPTIVE_OS_SETNAMEDSECURITYINFO              = 'Preemptive'
            PREEMPTIVE_OS_SQLCLROPS                         = 'Preemptive'
            PREEMPTIVE_OS_SQMLAUNCH                         = 'Preemptive'
            PREEMPTIVE_OS_VERIFYSIGNATURE                   = 'Preemptive'
            PREEMPTIVE_OS_VERIFYTRUST                       = 'Preemptive'
            PREEMPTIVE_OS_VSSOPS                            = 'Preemptive'
            PREEMPTIVE_OS_WAITFORSINGLEOBJECT               = 'Preemptive'
            PREEMPTIVE_OS_WINSOCKOPS                        = 'Preemptive'
            PREEMPTIVE_OS_WRITEFILE                         = 'Preemptive'
            PREEMPTIVE_OS_WRITEFILEGATHER                   = 'Preemptive'
            PREEMPTIVE_OS_WSASETLASTERROR                   = 'Preemptive'
            PREEMPTIVE_REENLIST                             = 'Preemptive'
            PREEMPTIVE_RESIZELOG                            = 'Preemptive'
            PREEMPTIVE_ROLLFORWARDREDO                      = 'Preemptive'
            PREEMPTIVE_ROLLFORWARDUNDO                      = 'Preemptive'
            PREEMPTIVE_SB_STOPENDPOINT                      = 'Preemptive'
            PREEMPTIVE_SERVER_STARTUP                       = 'Preemptive'
            PREEMPTIVE_SETRMINFO                            = 'Preemptive'
            PREEMPTIVE_SHAREDMEM_GETDATA                    = 'Preemptive'
            PREEMPTIVE_SNIOPEN                              = 'Preemptive'
            PREEMPTIVE_SOSHOST                              = 'Preemptive'
            PREEMPTIVE_SOSTESTING                           = 'Preemptive'
            PREEMPTIVE_SP_SERVER_DIAGNOSTICS                = 'Preemptive'
            PREEMPTIVE_STARTRM                              = 'Preemptive'
            PREEMPTIVE_STREAMFCB_CHECKPOINT                 = 'Preemptive'
            PREEMPTIVE_STREAMFCB_RECOVER                    = 'Preemptive'
            PREEMPTIVE_STRESSDRIVER                         = 'Preemptive'
            PREEMPTIVE_TESTING                              = 'Preemptive'
            PREEMPTIVE_TRANSIMPORT                          = 'Preemptive'
            PREEMPTIVE_UNMARSHALPROPAGATIONTOKEN            = 'Preemptive'
            PREEMPTIVE_VSS_CREATESNAPSHOT                   = 'Preemptive'
            PREEMPTIVE_VSS_CREATEVOLUMESNAPSHOT             = 'Preemptive'
            PREEMPTIVE_XE_CALLBACKEXECUTE                   = 'Preemptive'
            PREEMPTIVE_XE_CX_FILE_OPEN                      = 'Preemptive'
            PREEMPTIVE_XE_CX_HTTP_CALL                      = 'Preemptive'
            PREEMPTIVE_XE_DISPATCHER                        = 'Preemptive'
            PREEMPTIVE_XE_ENGINEINIT                        = 'Preemptive'
            PREEMPTIVE_XE_GETTARGETSTATE                    = 'Preemptive'
            PREEMPTIVE_XE_SESSIONCOMMIT                     = 'Preemptive'
            PREEMPTIVE_XE_TARGETFINALIZE                    = 'Preemptive'
            PREEMPTIVE_XE_TARGETINIT                        = 'Preemptive'
            PREEMPTIVE_XE_TIMERRUN                          = 'Preemptive'
            PREEMPTIVE_XETESTING                            = 'Preemptive'
            PWAIT_HADR_ACTION_COMPLETED                     = 'Replication'
            PWAIT_HADR_CHANGE_NOTIFIER_TERMINATION_SYNC     = 'Replication'
            PWAIT_HADR_CLUSTER_INTEGRATION                  = 'Replication'
            PWAIT_HADR_FAILOVER_COMPLETED                   = 'Replication'
            PWAIT_HADR_JOIN                                 = 'Replication'
            PWAIT_HADR_OFFLINE_COMPLETED                    = 'Replication'
            PWAIT_HADR_ONLINE_COMPLETED                     = 'Replication'
            PWAIT_HADR_POST_ONLINE_COMPLETED                = 'Replication'
            PWAIT_HADR_SERVER_READY_CONNECTIONS             = 'Replication'
            PWAIT_HADR_WORKITEM_COMPLETED                   = 'Replication'
            PWAIT_HADRSIM                                   = 'Replication'
            PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC = 'Full Text Search'
            QUERY_TRACEOUT                                  = 'Tracing'
            REPL_CACHE_ACCESS                               = 'Replication'
            REPL_HISTORYCACHE_ACCESS                        = 'Replication'
            REPL_SCHEMA_ACCESS                              = 'Replication'
            REPL_TRANFSINFO_ACCESS                          = 'Replication'
            REPL_TRANHASHTABLE_ACCESS                       = 'Replication'
            REPL_TRANTEXTINFO_ACCESS                        = 'Replication'
            REPLICA_WRITES                                  = 'Replication'
            REQUEST_FOR_DEADLOCK_SEARCH                     = 'Idle'
            RESERVED_MEMORY_ALLOCATION_EXT                  = 'Memory'
            RESOURCE_SEMAPHORE                              = 'Memory'
            RESOURCE_SEMAPHORE_QUERY_COMPILE                = 'Compilation'
            SLEEP_BPOOL_FLUSH                               = 'Idle'
            SLEEP_BUFFERPOOL_HELPLW                         = 'Idle'
            SLEEP_DBSTARTUP                                 = 'Idle'
            SLEEP_DCOMSTARTUP                               = 'Idle'
            SLEEP_MASTERDBREADY                             = 'Idle'
            SLEEP_MASTERMDREADY                             = 'Idle'
            SLEEP_MASTERUPGRADED                            = 'Idle'
            SLEEP_MEMORYPOOL_ALLOCATEPAGES                  = 'Idle'
            SLEEP_MSDBSTARTUP                               = 'Idle'
            SLEEP_RETRY_VIRTUALALLOC                        = 'Idle'
            SLEEP_SYSTEMTASK                                = 'Idle'
            SLEEP_TASK                                      = 'Idle'
            SLEEP_TEMPDBSTARTUP                             = 'Idle'
            SLEEP_WORKSPACE_ALLOCATEPAGE                    = 'Idle'
            SOS_SCHEDULER_YIELD                             = 'CPU'
            SQLCLR_APPDOMAIN                                = 'SQL CLR'
            SQLCLR_ASSEMBLY                                 = 'SQL CLR'
            SQLCLR_DEADLOCK_DETECTION                       = 'SQL CLR'
            SQLCLR_QUANTUM_PUNISHMENT                       = 'SQL CLR'
            SQLTRACE_BUFFER_FLUSH                           = 'Idle'
            SQLTRACE_FILE_BUFFER                            = 'Tracing'
            SQLTRACE_FILE_READ_IO_COMPLETION                = 'Tracing'
            SQLTRACE_FILE_WRITE_IO_COMPLETION               = 'Tracing'
            SQLTRACE_INCREMENTAL_FLUSH_SLEEP                = 'Idle'
            SQLTRACE_PENDING_BUFFER_WRITERS                 = 'Tracing'
            SQLTRACE_SHUTDOWN                               = 'Tracing'
            SQLTRACE_WAIT_ENTRIES                           = 'Idle'
            THREADPOOL                                      = 'Worker Thread'
            TRACE_EVTNOTIF                                  = 'Tracing'
            TRACEWRITE                                      = 'Tracing'
            TRAN_MARKLATCH_DT                               = 'Transaction'
            TRAN_MARKLATCH_EX                               = 'Transaction'
            TRAN_MARKLATCH_KP                               = 'Transaction'
            TRAN_MARKLATCH_NL                               = 'Transaction'
            TRAN_MARKLATCH_SH                               = 'Transaction'
            TRAN_MARKLATCH_UP                               = 'Transaction'
            TRANSACTION_MUTEX                               = 'Transaction'
            WAIT_FOR_RESULTS                                = 'User Wait'
            WAITFOR                                         = 'User Wait'
            WRITE_COMPLETION                                = 'Other Disk IO'
            WRITELOG                                        = 'Tran Log IO'
            XACT_OWN_TRANSACTION                            = 'Transaction'
            XACT_RECLAIM_SESSION                            = 'Transaction'
            XACTLOCKINFO                                    = 'Transaction'
            XACTWORKSPACE_MUTEX                             = 'Transaction'
            XE_DISPATCHER_WAIT                              = 'Idle'
            XE_TIMER_EVENT                                  = 'Idle'
            ABR                                             = 'Other'
            ASSEMBLY_LOAD                                   = 'SQLCLR'
            ASYNC_DISKPOOL_LOCK                             = 'Buffer I/O'
            BACKUP                                          = 'Backup'
            BACKUP_CLIENTLOCK                               = 'Backup'
            BACKUP_OPERATOR                                 = 'Backup'
            BACKUPBUFFER                                    = 'Backup'
            BACKUPTHREAD                                    = 'Backup'
            BAD_PAGE_PROCESS                                = 'Other'
            BUILTIN_HASHKEY_MUTEX                           = 'Other'
            CHECK_PRINT_RECORD                              = 'Other'
            CPU                                             = 'CPU'
            CURSOR                                          = 'Other'
            CURSOR_ASYNC                                    = 'Other'
            DAC_INIT                                        = 'Other'
            DBCC_COLUMN_TRANSLATION_CACHE                   = 'Other'
            DBTABLE                                         = 'Other'
            DEADLOCK_ENUM_MUTEX                             = 'Latch'
            DEADLOCK_TASK_SEARCH                            = 'Other'
            DEBUG                                           = 'Other'
            DISABLE_VERSIONING                              = 'Other'
            DISKIO_SUSPEND                                  = 'Backup'
            DLL_LOADING_MUTEX                               = 'Other'
            DROPTEMP                                        = 'Other'
            DUMP_LOG_COORDINATOR                            = 'Other'
            DUMP_LOG_COORDINATOR_QUEUE                      = 'Other'
            DUMPTRIGGER                                     = 'Other'
            EC                                              = 'Other'
            EE_SPECPROC_MAP_INIT                            = 'Other'
            ENABLE_VERSIONING                               = 'Other'
            ERROR_REPORTING_MANAGER                         = 'Other'
            EXECSYNC                                        = 'Parallelism'
            EXECUTION_PIPE_EVENT_INTERNAL                   = 'Other'
            FAILPOINT                                       = 'Other'
            FS_GARBAGE_COLLECTOR_SHUTDOWN                   = 'SQLCLR'
            FSAGENT                                         = 'Idle'
            FT_RESUME_CRAWL                                 = 'Other'
            GUARDIAN                                        = 'Other'
            HTTP_ENDPOINT_COLLCREATE                        = 'Other'
            HTTP_ENUMERATION                                = 'Other'
            HTTP_START                                      = 'Other'
            IMP_IMPORT_MUTEX                                = 'Other'
            IMPPROV_IOWAIT                                  = 'Other'
            INDEX_USAGE_STATS_MUTEX                         = 'Latch'
            INTERNAL_TESTING                                = 'Other'
            IO_AUDIT_MUTEX                                  = 'Other'
            KSOURCE_WAKEUP                                  = 'Idle'
            KTM_ENLISTMENT                                  = 'Other'
            KTM_RECOVERY_MANAGER                            = 'Other'
            KTM_RECOVERY_RESOLUTION                         = 'Other'
            LOWFAIL_MEMMGR_QUEUE                            = 'Memory'
            MIRROR_SEND_MESSAGE                             = 'Other'
            MISCELLANEOUS                                   = 'Other'
            MSQL_DQ                                         = 'Network I/O'
            MSQL_SYNC_PIPE                                  = 'Other'
            MSQL_XP                                         = 'Other'
            OLEDB                                           = 'Network I/O'
            PARALLEL_BACKUP_QUEUE                           = 'Other'
            PRINT_ROLLBACK_PROGRESS                         = 'Other'
            QNMANAGER_ACQUIRE                               = 'Other'
            QPJOB_KILL                                      = 'Other'
            QPJOB_WAITFOR_ABORT                             = 'Other'
            QRY_MEM_GRANT_INFO_MUTEX                        = 'Other'
            QUERY_ERRHDL_SERVICE_DONE                       = 'Other'
            QUERY_EXECUTION_INDEX_SORT_EVENT_OPEN           = 'Other'
            QUERY_NOTIFICATION_MGR_MUTEX                    = 'Other'
            QUERY_NOTIFICATION_SUBSCRIPTION_MUTEX           = 'Other'
            QUERY_NOTIFICATION_TABLE_MGR_MUTEX              = 'Other'
            QUERY_NOTIFICATION_UNITTEST_MUTEX               = 'Other'
            QUERY_OPTIMIZER_PRINT_MUTEX                     = 'Other'
            QUERY_REMOTE_BRICKS_DONE                        = 'Other'
            RECOVER_CHANGEDB                                = 'Other'
            REQUEST_DISPENSER_PAUSE                         = 'Other'
            RESOURCE_QUEUE                                  = 'Idle'
            RESOURCE_SEMAPHORE_MUTEX                        = 'Compilation'
            RESOURCE_SEMAPHORE_SMALL_QUERY                  = 'Compilation'
            SEC_DROP_TEMP_KEY                               = 'Other'
            SEQUENTIAL_GUID                                 = 'Other'
            SERVER_IDLE_CHECK                               = 'Idle'
            SHUTDOWN                                        = 'Other'
            SNI_CRITICAL_SECTION                            = 'Other'
            SNI_HTTP_ACCEPT                                 = 'Idle'
            SNI_HTTP_WAITFOR_0_DISCON                       = 'Other'
            SNI_LISTENER_ACCESS                             = 'Other'
            SNI_TASK_COMPLETION                             = 'Other'
            SOAP_READ                                       = 'Full Text Search'
            SOAP_WRITE                                      = 'Full Text Search'
            SOS_CALLBACK_REMOVAL                            = 'Other'
            SOS_DISPATCHER_MUTEX                            = 'Other'
            SOS_LOCALALLOCATORLIST                          = 'Other'
            SOS_OBJECT_STORE_DESTROY_MUTEX                  = 'Other'
            SOS_PROCESS_AFFINITY_MUTEX                      = 'Other'
            SOS_RESERVEDMEMBLOCKLIST                        = 'Memory'
            SOS_STACKSTORE_INIT_MUTEX                       = 'Other'
            SOS_SYNC_TASK_ENQUEUE_EVENT                     = 'Other'
            SOS_VIRTUALMEMORY_LOW                           = 'Memory'
            SOSHOST_EVENT                                   = 'Other'
            SOSHOST_INTERNAL                                = 'Other'
            SOSHOST_MUTEX                                   = 'Other'
            SOSHOST_RWLOCK                                  = 'Other'
            SOSHOST_SEMAPHORE                               = 'Other'
            SOSHOST_SLEEP                                   = 'Other'
            SOSHOST_TRACELOCK                               = 'Other'
            SOSHOST_WAITFORDONE                             = 'Other'
            SQLSORT_NORMMUTEX                               = 'Other'
            SQLSORT_SORTMUTEX                               = 'Other'
            SQLTRACE_LOCK                                   = 'Other'
            SRVPROC_SHUTDOWN                                = 'Other'
            TEMPOBJ                                         = 'Other'
            TIMEPRIV_TIMEPERIOD                             = 'Other'
            UTIL_PAGE_ALLOC                                 = 'Memory'
            VIA_ACCEPT                                      = 'Other'
            VIEW_DEFINITION_MUTEX                           = 'Latch'
            WAITFOR_TASKSHUTDOWN                            = 'Idle'
            WAITSTAT_MUTEX                                  = 'Other'
            WCC                                             = 'Other'
            WORKTBL_DROP                                    = 'Other'
            XE_BUFFERMGR_ALLPROCECESSED_EVENT               = 'Other'
            XE_BUFFERMGR_FREEBUF_EVENT                      = 'Other'
            XE_DISPATCHER_JOIN                              = 'Other'
            XE_MODULEMGR_SYNC                               = 'Other'
            XE_OLS_LOCK                                     = 'Other'
            XE_SERVICES_MUTEX                               = 'Other'
            XE_SESSION_CREATE_SYNC                          = 'Other'
            XE_SESSION_SYNC                                 = 'Other'
            XE_STM_CREATE                                   = 'Other'
            XE_TIMER_MUTEX                                  = 'Other'
            XE_TIMER_TASK_DONE                              = 'Other'
        }

        $ignorable = 'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
        'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
        'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE', 'CXCONSUMER',
        'DBMIRROR_DBM_EVENT', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE',
        'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
        'EXECSYNC', 'FSAGENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX',
        'HADR_CLUSAPI_CALL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
        'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
        'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
        'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE',
        'PARALLEL_REDO_DRAIN_WORKER', 'PARALLEL_REDO_LOG_CACHE', 'PARALLEL_REDO_TRAN_LIST', 'PARALLEL_REDO_WORKER_SYNC',
        'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',
        'PARALLEL_REDO_WORKER_WAIT_WORK', 'PREEMPTIVE_HADR_LEASE_MECHANISM',
        'PREEMPTIVE_OS_LIBRARYOPS', 'PREEMPTIVE_OS_COMOPS', 'PREEMPTIVE_OS_CRYPTOPS',
        'PREEMPTIVE_OS_PIPEOPS', 'PREEMPTIVE_OS_AUTHENTICATIONOPS',
        'PREEMPTIVE_OS_GENERICOPS', 'PREEMPTIVE_OS_VERIFYTRUST',
        'PREEMPTIVE_OS_FILEOPS', 'PREEMPTIVE_OS_DEVICEOPS', 'PREEMPTIVE_OS_QUERYREGISTRY',
        'PREEMPTIVE_OS_WRITEFILE', 'PREEMPTIVE_XE_CALLBACKEXECUTE', 'PREEMPTIVE_XE_DISPATCHER',
        'PREEMPTIVE_XE_GETTARGETSTATE', 'PREEMPTIVE_XE_SESSIONCOMMIT',
        'PREEMPTIVE_XE_TARGETINIT', 'PREEMPTIVE_XE_TARGETFINALIZE',
        'PWAIT_ALL_COMPONENTS_INITIALIZED', 'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_ASYNC_QUEUE',
        'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'REDO_THREAD_PENDING_WORK',
        'QDS_SHUTDOWN_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH',
        'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
        'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
        'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
        'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
        'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'SQLTRACE_WAIT_ENTRIES',
        'WAIT_FOR_RESULTS', 'WAITFOR', 'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_HOST_WAIT',
        'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'WAIT_XTP_CKPT_CLOSE', 'WAIT_XTP_RECOVERY',
        'XE_BUFFERMGR_ALLPROCESSED_EVENT', 'XE_DISPATCHER_JOIN',
        'XE_DISPATCHER_WAIT', 'XE_LIVE_TARGET_TVF', 'XE_TIMER_EVENT'

        if ($IncludeIgnorable) {
            $sql = "WITH [Waits] AS
                (SELECT
                    [wait_type],
                    [wait_time_ms] / 1000.0 AS [WaitS],
                    ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
                    [signal_wait_time_ms] / 1000.0 AS [SignalS],
                    [waiting_tasks_count] AS [WaitCount],
                    Case WHEN SUM ([wait_time_ms]) OVER() = 0 THEN NULL ELSE 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() END AS [Percentage],
                    ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                FROM sys.dm_os_wait_stats
                WHERE [waiting_tasks_count] > 0
                )
                SELECT
                    MAX ([W1].[wait_type]) AS [WaitType],
                    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [WaitSeconds],
                    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [ResourceSeconds],
                    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [SignalSeconds],
                    MAX ([W1].[WaitCount]) AS [WaitCount],
                    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
                    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWaitSeconds],
                    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgResSeconds],
                    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSigSeconds],
                    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [URL]
                FROM [Waits] AS [W1]
                INNER JOIN [Waits] AS [W2]
                    ON [W2].[RowNum] <= [W1].[RowNum]
                GROUP BY [W1].[RowNum] HAVING SUM ([W2].[Percentage]) - MAX([W1].[Percentage]) < $Threshold"
        } else {
            $IgnorableList = "'$($ignorable -join "','")'"
            $sql = "WITH [Waits] AS
                (SELECT
                    [wait_type],
                    [wait_time_ms] / 1000.0 AS [WaitS],
                    ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
                    [signal_wait_time_ms] / 1000.0 AS [SignalS],
                    [waiting_tasks_count] AS [WaitCount],
                    Case WHEN SUM ([wait_time_ms]) OVER() = 0 THEN NULL ELSE 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() END AS [Percentage],
                    ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                FROM sys.dm_os_wait_stats
                WHERE [waiting_tasks_count] > 0
                AND Cast([wait_type] as VARCHAR(60)) NOT IN ($IgnorableList)
                )
                SELECT
                    MAX ([W1].[wait_type]) AS [WaitType],
                    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [WaitSeconds],
                    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [ResourceSeconds],
                    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [SignalSeconds],
                    MAX ([W1].[WaitCount]) AS [WaitCount],
                    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
                    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWaitSeconds],
                    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgResSeconds],
                    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSigSeconds],
                    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [URL]
                FROM [Waits] AS [W1]
                INNER JOIN [Waits] AS [W2]
                    ON [W2].[RowNum] <= [W1].[RowNum]
                GROUP BY [W1].[RowNum] HAVING SUM ([W2].[Percentage]) - MAX([W1].[Percentage]) < $Threshold"

        }
        Write-Message -Level Debug -Message $sql
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($IncludeIgnorable) {
                $excludeColumns = 'Notes'
            } else {
                $excludeColumns = 'Notes', 'Ignorable'
            }

            foreach ($row in $server.Query($sql)) {
                $waitType = $row.WaitType
                if (-not $IncludeIgnorable) {
                    if ($ignorable -contains $waitType) { continue }
                }

                [PSCustomObject]@{
                    ComputerName           = $server.ComputerName
                    InstanceName           = $server.ServiceName
                    SqlInstance            = $server.DomainInstanceName
                    WaitType               = $waitType
                    Category               = ($category).$waitType
                    WaitSeconds            = $row.WaitSeconds
                    ResourceSeconds        = $row.ResourceSeconds
                    SignalSeconds          = $row.SignalSeconds
                    WaitCount              = $row.WaitCount
                    Percentage             = $row.Percentage
                    AverageWaitSeconds     = $row.AvgWaitSeconds
                    AverageResourceSeconds = $row.AvgResSeconds
                    AverageSignalSeconds   = $row.AvgSigSeconds
                    Ignorable              = ($ignorable -contains $waitType)
                    URL                    = $row.URL
                    Notes                  = ($details).$waitType
                } | Select-DefaultView -ExcludeProperty $excludeColumns
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUquvwS4Suhh5anBMq6lbgUCzh
# 56WgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFA2aq/ewnCRtWNbA/ISnIzmbE0gEMA0GCSqGSIb3DQEBAQUABIIBAEccBvjQ
# jHiOMeMYBUVH2PQEhjM0HlY9z3ntZc5NjjuEu4pNanmQ5F5QyFazVCSu/yKpYonu
# TMaKkW3RuGOZNgK2ET2M5QPmbSnHUBRaweXJuk7Y3s7bTBxrOMmRMQRQYKANvhBW
# Te1fK+usTzndxAHt831kNmZdb1b2Glvbvsk0SEUrgvv1v5rHgfCimSH5Tur9upSl
# bcwnEta6eVF80zdTZhPvAzolJX57w2o9o927AKUpM31on6dcnyXIi9VstN1tvBDw
# TNTffRILb7Q0Tefc9zxw8rY0OY8xSyzw8Lky5Oe97sU/pBWJ0UIP9jkSrvJ6E8Hs
# IwRVs6eowGivzGyhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzMFowLwYJKoZIhvcNAQkEMSIEICYvHN0/Ip1mzmRRKIv8W4aaGrJw
# UuE5vyeB+XoKEQ/7MA0GCSqGSIb3DQEBAQUABIIBAAWa0GyIzaj9w7ECQD08eqU7
# 4AAc++U2/CD2clsADkurUmHbBknK2WA7QuhCaH4r9hXprQBfMWeB1tmXOkhMYJKj
# AOSIY3/6KxahtKWCB3f7wVrJBBXJ+lVa+XVH3cZQ1hXpGdepGUmAutRxyE7q6aZS
# jgocwCNZ7pH4180xUkrMCdK8z4gjfK5V1wfvuFU08fGRCjid7MHpzedBjTgLr/LE
# PQvJW/PKOnbyYmPREWSIby2Lifr6eNLFanImeQdk+vaZkwY+cygxdtwq7/3VSHvh
# /bzw7HHpTYDed5OI5mrIToKT6Ib8Lnj9GPv1N8pDXv6NDiaHjC9HBxa3R9fR87Y=
# SIG # End signature block
