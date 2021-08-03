USE [master] 
GO 

DECLARE @SystemRootPath as nvarchar(500)
DECLARE @ReturnCode as int 
DECLARE @sqlcmd as nvarchar(max) 

select @SystemRootPath = replace(physical_name, '\DATA\Master.mdf', '\Audit\') 
from sys.master_files 
where database_id = 1 and name = 'master' 

select @SystemRootPath 

EXECUTE @ReturnCode = dbo.xp_create_subdir @SystemRootPath IF @ReturnCode <> 0 RAISERROR('Error creating directory.', 16, 1) 

set @sqlcmd = 'CREATE SERVER AUDIT [MSSQLSERVER_PrivledgeUse] TO FILE 
( FILEPATH = N''' + @SystemRootPath + '''
,MAXSIZE = 100 MB 
,MAX_ROLLOVER_FILES = 100 
,RESERVE_DISK_SPACE = ON 
) WITH (QUEUE_DELAY = 1000, ON_FAILURE = SHUTDOWN, AUDIT GUID = ''19671018-446f-6871-7479-4036b61489d8'')' 

exec sp_executesql @sqlcmd 

ALTER SERVER AUDIT [MSSQLSERVER_PrivledgeUse] WITH (STATE = ON) 

-------------------------------------------------------------------------
--PRINT 'ADD A FILTER TO SCREEN OUT UNNECESSARY AUDIT RECORDS' 

ALTER SERVER AUDIT [MSSQLSERVER_PrivledgeUse] WITH (STATE = OFF) 
GO 

USE [master]; 
GO 
ALTER SERVER AUDIT [MSSQLSERVER_PrivledgeUse] 
WHERE 
-- The following line is used solely to ensure that the WHERE statement begins with a clause 
-- that is guaranteed true. This allows us to begin each subsequent line with AND, making 
-- editing easier. If you wish, you may remove this line (and the first AND). 
(Statement <> '19671018-446f-6871-7479-4036b61489d8') 
 
-- The following filters out system-generated statements accessing SQL Server internal tables 
-- that are not directly visible to or accessible by user processes, but which do appear among 
-- log records if not suppressed. 
AND NOT (Schema_Name='sys' AND (Object_Name='syspalnames' 
OR Object_Name = 'objects$' 
OR Object_Name = 'syspalvalues' 
OR Object_Name = 'configurations$' 
OR Object_Name = 'system_columns$' 
OR Object_Name = 'server audits$' 
OR Object_Name = 'parameters$' 
-- If activated, the following filters out system-generated statements, should they occur, accessing 
-- additional SQL Server internal tables,that are not directly visible to or accessible by user processes 
-- (even by administrators). Enable each line, as needed, to add it to the filter. 
OR Object_Name = 'sysschobjs' 
OR Object_Name = 'sysschobjs' 
OR Object_Name = 'sysbinobjs' 
OR Object_Name = 'sysclsobjs' 
OR Object_Name = 'sysnsobjs' 
OR Object_Name = 'syscolpars' 
OR Object_Name = 'systypedsubobjs' 
OR Object_Name = 'sysidxstats' 
OR Object_Name = 'sysiscols' 
OR Object_Name = 'sysscalartypes' 
OR Object_Name = 'sysdbreg' 
OR Object_Name = 'sysxsrvs' 
OR Object_Name = 'sysrmtlgns' 
OR Object_Name = 'syslnklgns' 
OR Object_Name = 'sysxlgns' 
OR Object_Name = 'sysdbfiles' 
OR Object_Name = 'sysusermsg' 
OR Object_Name = 'sysprivs' 
OR Object_Name = 'sysowners' 
OR Object_Name = 'sysobjkeycrypts' 
OR Object_Name = 'syscerts' 
OR Object_Name = 'sysasymkeys' 
OR Object_Name = 'ftinds' 
OR Object_Name = 'sysxprops' 
OR Object_Name = 'sysallocunits' 
OR Object_Name = 'sysrowsets' 
OR Object_Name = 'sysrowsetrefs' 
OR Object_Name = 'syslogshippers' 
OR Object_Name = 'sysremsvcbinds' 
OR Object_Name = 'sysconvgroup' 
OR Object_Name = 'sysxmitqueue' 
OR Object_Name = 'sysdesend' 
OR Object_Name = 'sysdercv'
OR Object_Name = 'sysendpts' 
OR Object_Name = 'syswebmethods' 
OR Object_Name = 'sysqnames' 
OR Object_Name = 'sysxmlcomponent' 
OR Object_Name = 'sysxmlfacet' 
OR Object_Name = 'sysxmlplacement' 
OR Object_Name = 'syssingleobjrefs' 
OR Object_Name = 'sysmultiobjrefs' 
OR Object_Name = 'sysobjvalues' 
OR Object_Name = 'sysguidrefs' 
))

-- The following suppresses audit trail messages about the execution of statements within procedures 
-- and functions. This is done because it is generally not useful to trace internal operations 
-- of a function or procedure, and this is a simple way to detect them. 
-- However, this opens an opportunity for an adversary to obscure actions on the database, 
-- so make sure that the creation and modification of functions and procedures is tracked. 
-- Further, details of your application architecture may be incompatible with this technique. 
-- Use with care. 
AND NOT(Additional_Information LIKE '<tsql.stack>%') 
 
-- The following statements filter out audit records for certain system-generated actions that 
-- frequently occur, and which do not aid in tracking the activities of a user or process. 
AND NOT (Schema_Name='sys' AND Statement LIKE 'SELECT%clmns.name%FROM%sys.all_views%sys.all_columns%sys.indexes%sys.index_columns%sys.computed_columns%sys.identity_columns%sys.objects%sys.types%sys.schemas%sys.types%') 
AND NOT (Schema_Name='sys' AND Object_Name <> 'databases' AND Statement LIKE '%SELECT%clmns.column_id%,%clmns.name%,%clmns.is_nullable%,%CAST%ISNULL%FROM%sys.all_views%AS%v%INNER%JOIN%sys.all_columns%AS%clmns%0N%clmns.object_id%v.object_id%LEFT%0UTER%JOIN%sys.indexes%AS%ik%ON%ik.object_id%clmns.object_id%and%1%ik.is_primary_key%') 
AND NOT (Schema_Name='sys' AND Object_Name <> 'databases' AND Statement LIKE 'SELECT%dtb.name%AS%dtb.state%A%FROM%master.sys.databases%dtb' ) 


-- Numerous log records are generated when the SQL Server Management Studio Log Viewer itself is 
-- populated or refreshed. The following filters out the less useful of these, while not hiding the 
-- fact that metadata about the log was accessed. 
AND NOT(Schema_Name = 'sys' AND Statement LIKE'SELECT%dtb.name AS%,%dtb.database id AS%,%CAST(has dbaccess(dtb.name) AS bit) AS%FROM%master.sys.databases AS dtb%0RDER BY%ASC') 
AND NOT(Schema_Name = 'sys' AND Statement LIKE 'SELECT%dtb.collation name AS%,%dtb.name AS%FROM%master.sys.databases AS dtb%WHERE%') 
GO 
 
 
-- ENABLE THE AUDIT 
 
--PRINT 'ENABLE THE AUDIT' 
ALTER SERVER AUDIT [MSSQLSERVER_PrivledgeUse] WITH (STATE = ON); 
GO 
 
 
USE [master] 
GO 
 
CREATE SERVER AUDIT SPECIFICATION [PrivilegedUse] 
FOR SERVER AUDIT [MSSQLSERVER_PrivledgeUse] 
ADD (DATABASE_CHANGE_GROUP), 
ADD (DATABASE_OBJECT_CHANGE_GROUP), 
ADD (DATABASE_OBJECT_OWNERSHIP_CHANGE_GROUP), 
ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP), 
ADD (DATABASE_OWNERSHIP_CHANGE_GROUP), 
ADD (DATABASE_PERMISSION_CHANGE_GROUP), 
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP), 
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP), 
ADD (DBCC_GROUP),
ADD (FAILED_LOGIN_GROUP),
ADD (LOGIN_CHANGE_PASSWORD_GROUP),
ADD (SCHEMA_OBJECT_CHANGE_GROUP),
ADD (SCHEMA_OBJECT_OWNERSHIP_CHANGE_GROUP),
ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP),
ADD (SERVER_OPERATION_GROUP),
ADD (SERVER_PERMISSION_CHANGE_GROUP),
ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
ADD (TRACE_CHANGE_GROUP),
ADD (DATABASE_OBJECT_ACCESS_GROUP),
ADD (SCHEMA_OBJECT_ACCESS_GROUP),
ADD (BACKUP_RESTORE_GROUP),
ADD (AUDIT_CHANGE_GROUP),
ADD (SERVER_OBJECT_PERMISSION_CHANGE_GROUP),
ADD (DATABASE_PRINCIPAL_IMPERSONATION_GROUP),
ADD (SERVER_PRINCIPAL_IMPERSONATION_GROUP),
ADD (SUCCESSFUL_LOGIN_GROUP),
ADD (LOGOUT_GROUP),
ADD (SERVER_OBJECT_CHANGE_GROUP),
ADD (DATABASE_OPERATION_GROUP),
ADD (APPLICATION_ROLE_CHANGE_PASSWORD_GROUP),
ADD (SERVER_STATE_CHANGE_GROUP),
ADD (SERVER_OBJECT_OWNERSHIP_CHANGE_GROUP),
ADD (USER_CHANGE_PASSWORD_GROUP)
WITH (STATE = ON) 
GO 
 
 
-------------------------------------------------------------------------
--select * from sys.server file audits 
-- 
