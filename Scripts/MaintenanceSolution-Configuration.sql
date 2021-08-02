/* 
Configuration of MaintenanceSolution.SQL 
*** Must be run after MaintenanceSolution.SQL *** 
*/ 

DECLARE @ErrorMessage nvarchar(max) 

IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE name = 'commandlog' AND type_desc = 'user_table') 
BEGIN 
SET @ErrorMessage = 'This configuration script must be executed after installation of SQL Server Maintenance Solution.' 
RAISERROR(@ErrorMessage,16,1) WITH NOWAIT 
END 

IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN 
SET @ErrorMessage = 'You need to be a member of the SysAdmin server role to configure the SQL Server Maintenance Solution.' 
RAISERROR(@ErrorMessage,16,1) WITH NOWAIT 
END 
 
USE [msdb] 
-------------------------------------------
-- ensure backup compression is enabled for instance 
-------------------------------------------
 
if exists (select value from sys.configurations where name = 'backup compression default' and value = 0) 
begin 
    exec sp_configure 'backup compression default', 1
    reconfigure 
end 

-------------------------------------------
--Update System-Database full backups - keep for 7 days 
-- backup will be deleted prior to next backup being taken to save space 
-------------------------------------------

EXEC msdb.dbo.sp_update_jobstp 
@job_name=N'DatabaseBackup - SYSTEM DATABASES - FULL' 
,@step_id=1
,@step_name=N'DatabaseBackup - SYSTEM DATABASES - FULL' 
,@command='EXECUTE [dbo].[DatabaseBackup] 
@Databases = ''SYSTEM DATABASES'', 
@Directory = NULL, 
@BackupType - ''FULL'', 
@Verify = ''N'', 
@CleanupTime = 168, 
@CleanupMode = ''BEFORE BACKUP'', 
@CheckSum = ''N'', 
@LogToTable ''Y'''

-------------------------------------------
--Update User-Database full backups - keep for 7 days 
-- backup will be deleted . prior to next backup being taken to save space 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstp 
@job_name=N'DatabaseBackup - USER DATABASES - FULL' 
,@step_id=1
,@step_name=N'DatabaseBackup - USER DATABASES - FULL' 
,@command=N'EXECUTE [dbo].[DatabaseBackup] 
@Databases = ''USER DATABASES'', 
@Directory = NULL, 
@BackupType = ''FULL'', 
@Verify = ''N'', 
@CleanupTime = 168, 
@CleanupMode = ''BEFORE BACKUP'', 
@CheckSum = ''N'', 
@LogToTable ''Y''' 

-------------------------------------------
--Update User-Database cliff backups - keep for 7 days 
-- backup will be deleted prior to next backup being taken to save space 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstep 
@job_name=N'DatabaseBackup - USER DATABASES - DIFF' 
,@step_id=1 
,@step_name=N'DatabaseBackup - USER DATABASES - DIFF' 
,@command=N'EXECUTE [dbo].[DatabaseBackup] 
@Databases = ''USER DATABASES'', 
@Directory = NULL, 
@BackupType = ''DIFF'', 
@Verify = ''N'', 
@CleanupTime = 168, 
@CleanupMode = ''BEFORE_BACKUP'', 
@CheckSum = ''N'', 
@LogToTable = ''Y''' 

-------------------------------------------
--Update User-Database tlog backups - keep for 7 days 
-- backup will be deleted prior to next backup being taken to save space 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstp 
@job_name=N'DatabaseBackup - USER DATABASES - LOG' 
,@step_id=1 
,@step_name=N'DatabaseBackup - USER DATABASES LOG' 
,@command=N'EXECUTE [dbo].[DatabaseBackup] 
@Databases = ''USER DATABASES'', 
@Directory = NULL, 
@BackupType = ''LOG'', 
@Verify = ''N'', 
@CleanupTime = 168, 
@CleanupMode = ''BEFORE BACKUP'', 
@CheckSum = ''N'', 
@LogToTable = ''Y''' 

-------------------------------------------
--Update fragmented user databases & update statistics 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstep 
@job_name=N'IndexOptimize - USER DATABASES' 
,@step_id=1 
,@step_name=N'IndexOptimize - USER DATABASES' 
,@command=N'EXECUTE [dbo].[IndexOptimize] 
@Databases = ''USER_DATABASES'', 
@LogToTable = ''Y'', 
@FragmentationLow = NULL, 
@FragmentationMedium = ''INDEX_REORGANIZE,INDEX REBUILD ONLINE,INDEX_REBUILD_OFFLINE'', 
@FragmentationHigh = ''INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'' 
@FragmentationLevell = 5, 
@FragmentationLevel2 = 30, 
@MinNumber0fPages = 500, 
@UpdateStatistics = ''ALL'', 
@OnlyModifiedStatistics = ''Y''' 

-------------------------------------------
-- Configure System Database integrity check 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstep 
@job_name=N'DatabaseIntegrityCheck - SYSTEM DATABASES', 
@step_id=1, 
@step_name=N'DatabaseIntegrityCheck - SYSTEM DATABASES', 
@command=N'EXECUTE [dbo].[DatabaseIntegrityCheck] 
@Databases = ''SYSTEM DATABASES'', 
@CheckCommands = ''CHECKDB'', 
@LogToTable = ''Y''' 

-------------------------------------------
-- Configure User Database integrity check 
-------------------------------------------
EXEC msdb.dbo.sp_update_jobstep 
@job_name=N'DatabaseIntegrityCheck - USER DATABASES', 
@step_id=1, 
@step_name=N'DatabaseIntegrityCheck - USER DATABASES', 
@command=N'EXECUTE [dbo].[DatabaseIntegrityCheck] 
@Databases = ''USER DATABASES'', 
@CheckCommands = ''CHECKDB'', 
@LogToTable = ''Y''' 

-------------------------------------------
-- Disable - USER DATABASES - DIRE Job 
-------------------------------------------
EXEC msdb.dbo.sp_update_job 
@job_name=N'DatabaseBackup - USER DATABASES - DIFF' 
,@enabled= 0
