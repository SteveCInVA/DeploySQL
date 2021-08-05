/* 
-----------------------------------------------------------
Scheduling of MaintenanceSolution.SQL 
*** Must be run after MaintenanceSolution.SQL *** 
-----------------------------------------------------------
-- Daily System database backups - Daily at 12:05AM 
-- Weekly System database ingegrity checks - Saturday at 01:05AM 

-- Weekly full user database backups - Sunday at 12:05AM 
-- USER_DATABASES - Differential backups Mon-Sat @ 12:05AM 
-- USER_DATABASES - Transaction log backups - Daily - Every hour 
-- USER_DATABASES - Index Optimize - Daily @ 1:30AM 
-- Weekly User database ingegrity checks - Saturday at 2:00AM 

-- Command Log Cleanup - Daily @ 12:00AM 
-- Output file cleanup - use the same schedule as CommandLog. Cleanup 
-- sp_delete_backuphistory - use the same schedule as CommandLog Cleanup 
-- sp_purge_jobhistory - use the same schedule as CommandLog Cleanup 
*/ 
 
DECLARE @ErrorMessage nvarchar(max) 
 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE name = 'commandlog' AND type_desc = 'user_table') 
BEGIN 
SET @ErrorMessage = 'This configuration script must be executed after installation of SQL Server Maintenance Solution.' 
RAISERROR(@ErrorMessage, 16, 1) WITH NOWAIT 
END 
 
IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN 
SET @ErrorMessage = 'You need to be a member of the SysAdmin server role to configure the SQL Server Maintenance Solution.' 
RAISERROR(@ErrorMessage,16,1) WITH NOWAIT 
END 

USE [msdb] 
GO 
-- Daily System database backups - Daily at 12:05AM 
IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules
    WHERE name = 'SYSTEM_DATABASES - Backup') 
BEGIN 
DECLARE @schedule_id int 
EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DatabaseBackup - SYSTEM_DATABASES - FULL', @name=N'SYSTEM_DATABASES - Backup', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=500, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- Weekly full user database backups - Daily at 12:05AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'User Database - Full Backup') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DatabaseBackup - USER_DATABASES - FULL', @name=N'User Database - Full Backup', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=500, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- USER_DATABASES - Differential backups Mon-Sat @ 12:05AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
     WHERE name = 'User Database - Diff Backup') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name='DatabaseBackup - USER_DATABASES - DIFF', @name=N'User Database - Diff Backup', 
 @enabled=1, 
 @freq_type=8, 
 @freq_interval=126, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=500, 
 @active_end_time= 235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- USER_DATABASES - Transaction log backups - Daily - Every hour 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'User Database - Transaction Logs') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DatabaseBackup - USER_DATABASES - LOG', @name=N'User Database - Transaction Logs', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=8, 
 @freq_subday_interval=1, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=0, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- USER_DATABASES - Index Optimize - Daily @ 1:30AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'USER_DATABASES - Index Optimize') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'IndexOptimize - USER_DATABASES', @name=N'USER_DATABASES - Index Optimize', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=13000, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- Weekly User database ingegrity checks - Saturday at 2:00AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'USER_DATABASES - IntegrityCheck') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DatabaseIntegrityCheck - USER_DATABASES', @name=N'USER_DATABASES - IntegrityCheck', 
 @enabled=1, 
 @freq_type=8, 
 @freq_interval=64, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=20000, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- Weekly System database ingegrity checks - Saturday at 01:05AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'SYSTEM_DATABASES - IntegrityCheck') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DatabaseIntegrityCheck - SYSTEM_DATABASES', @name=N'SYSTEM_DATABASES - IntegrityCheck', 
 @enabled=1, 
 @freq_type=8, 
 @freq_interval=64, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=10500, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 
 END 
 GO 
 -- Command Log Cleanup - Daily @ 12:00AM 
 IF NOT EXISTS(SELECT * FROM msdb.dbo.sysschedules 
 WHERE name = 'Maintainence Log Cleanup') 
 BEGIN 
 DECLARE @schedule_id int 
 EXEC msdb.dbo.sp_add_jobschedule @job_name=N'CommandLog Cleanup', @name=N'Maintainence Log Cleanup', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=1, 
 @freq_subday_interval=0, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=1, 
 @active_start_date=20210308, 
 @active_end_date=99991231, 
 @active_start_time=0, 
 @active_end_time=235959, @schedule_id = @schedule_id OUTPUT 

 -- Output file cleanup - use the same schedule as CommandLog Cleanup
 EXEC msdb.dbo.sp_attach_schedule @job_name=N'Output File Cleanup',@schedule_id=@schedule_id

 --sp_delete backuphistory - use the same schedule as CommandLog Cleanup
 EXEC msdb.dbo.sp_attach_schedule @job_name=N'sp_delete_backuphistory',@schedule_id=@schedule_id

 --sp purge jobhistory - use the same schedule as CommandLog Cleanup
 EXEC msdb.dbo.sp_attach_schedule @job_name=N'sp_purge_jobhistory',@schedule_id=@schedule_id 
 END 
 