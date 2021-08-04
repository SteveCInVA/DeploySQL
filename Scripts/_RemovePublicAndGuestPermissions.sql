/* -- Remove public and guest permissions 
Brian.Doherty@microsoft.com 
*/ 

DECLARE @modeScriptOnly bit; 
--set @modeScriptOnly = 0; --execute generated commands 
set @modeScriptOnly = 1; --script commands to be executed later 
 
USE master; 
 
IF @modeScriptOnly = 1
    PRINT 'REVOKE VIEW ANY DATABASE FROM PUBLIC;'; 
ELSE 
    REVOKE VIEW ANY DATABASE FROM PUBLIC; 
 
 DECLARE @database varchar(100) 
 ,@permission varchar(100) 
 ,@schema varchar(100) 
 ,@sql nvarchar(1000) 
 ,@object varchar(100) 
 ,@role varchar(100); 
 
 DECLARE csrDatabases CURSOR FAST_FORWARD FOR 
 SELECT name FROM sys.databases ORDER BY name; 
 
 OPEN csrDatabases; 
 FETCH NEXT FROM csrDatabases INTO @database; 
 
 WHILE (@@FETCH_STATUS = 0) 
 BEGIN 
 SET @sql = 
 'DECLARE csrObjects CURSOR FAST_FORWARD FOR 
 SELECT p.permission_name, [schema] = SCHEMA_NAME(o.schema_id), 
 object_name = o.name, role_name = u.name 
 FROM [' + @database + '].sys.database_permissions p 
 INNER JOIN [' + @database + '].sys.database_principals u ON 
 p.grantee_principal_id = u.principal_id 
 INNER JOIN [' + @database + '].sys.all_objects o ON o.object_id = p.major_id 
 WHERE p.grantee_principal_id IN (0, 2) 
 ORDER BY u.name, o.schema_id, o.name, p.permission_name;'; 
 
 EXECUTE sp_executesql @sql; 
 
 OPEN csrObjects; 
 FETCH NEXT FROM csrObjects INTO @permission, @schema, @object, @role; 
 
 WHILE (@@FETCH_STATUS = 0) 
 BEGIN 
 SELECT @sql = 'USE [' + @database + ']; REVOKE ' + @permission + ' ON [' + @schema + '].[' + @object + '] FROM ' + @role + ';'; 
 
 IF @modeScriptOnly = 1
 PRINT @sql; 
 ELSE 
 EXEC sp_executesql @sql; 
 
 FETCH NEXT FROM csrObjects INTO @permission, @schema, @object, @role; 
 END 
 
 IF @database NOT IN ('master', 'tempdb') 
 BEGIN 
 SELECT @sql = 'USE [' + @database + ']; REVOKE CONNECT FROM GUEST;'; 
 IF @modeScriptOnly = 1
 PRINT @sql; 
 ELSE 
 EXEC sp_executesql @sql; 
 END 
 
 CLOSE csrObjects; 
 DEALLOCATE csrObjects; 
 
 FETCH NEXT FROM csrDatabases INTO @database; 
 
 END 
 CLOSE csrDatabases; 
 DEALLOCATE csrDatabases; 
 