1 <# 
2 .SYNOPSIS 
3 
4 SQL Server deployment script. 
5 
6 .DESCRIPTION 
7 
8 Script that was developed by the PESB SQL team to deploy SQL Server in a known 
configuration to targeted servers. 
9 High level tasks performed by this script: 
10 
11 - Copy required PowerShell modules to target computer 
12 - Configure Optical Drive to V:\ 
13 - Configure Non-OS Drive(s) 1 or 5 disk configurations supported 
14 - Configure target computer for high performance power setting 
15 - Ensure .NET 4.5 is installed 
16 - Configure machine to Eastern Time Zone (GMT-4/5 depending on Daylight 
Savings) 
17 - Copy installation media to C:\Software 
18 - Install SQL Engine / Connectivy Tools / Backwards Compatability 
19 - Installed provided SQL Service Packs / Cumulative Updates 
20 - Configure Windows Firewall rule for SQL Server 
21 - Configure Windows Firewall rule for SQL Browser 
22 - Install current version of SQL Server Management Studio 
23 - Disable Client Improvement Experience 
24 - Ensure DBATeam is granted file system permissions to necessary SQL folders 
25 - Restarts target computer 
26 - Execute SQL Server Post Installation Configuration Script 
.\SQLInstanceConfiguration.ps1 
27 
28 For questions or issues please contact 
29 
30 .PARAMETER 
31 
32 -Computer <string> - Defaults to localhost 
33 
34 [-Instance <string>] - If provided will install SQL in an instance, otherwise 
default instance is used. 
35 
36 [-SQLVersion <string>] - Enumeration of supported SQL Version. Defaults to SQL 
2019 
37 
38 [-NumberOfNonOSDrives <string>] - Number of drives to be used for SQL Server. 
Default is 5 (D:\SQLSystem, E:\SQLData, F:\SQLLog, G:\SQLTempDB, 
H:\SQLBackup). Optional config for single drive install. 
39 
40 [-InstallSourcePath <string>] - Path to installation base. Should be a UNC 
Path such as \\server\SQLInstallation 
41 
42 [-DBAOSAdminGroup <string>] - Active directory group used for administration of 
SQL Server host machine. 
43 
44 [-DBASQLAdminGroup <string>] - Active directory group used for administration 
of SQL Server databases and service. 
45 
46 [-SkipDriveConfig <boolean>] - Boolean value (True/False) to use to prevent 
initial drive configuration. Default is False. 
47 
48 -InstallCredential <pscredential> - Credential used to install SQL Server and 
perform all configurations. Account should be a member of the group specified 
in -DBATeamGroup as well as a local administrator of the target server. 
49 
50 .EXAMPLE 
51 
52 .\DeploySQL-Instance.ps1 -Computer computerl -Instance Inst. 1 -SQLVersion 
SQL2017 -NumberOfNonOSDrives 5 -InstallSourcePath '\\computerShare\SQLInstall' 
-DBAOSAdminGroup domain\DBATeamMembers -DBASQLAdminGroup domain\DBATeamMembers 
-SkipDriveConfig False 
53 Would install SQL 2017 to Computerl requiring 5 non-OS drives for installation. 
54 
55 .\DeploySQL-Instance.ps1 -Computer computer2 -NumberOfNonOSDrives 1 
-InstallSourcePaLh '\\computerShare\SQLInstall' -SkipDriveConfig True 
56 Would install SQL 2019 to Computer2 using only the D: for all files. Would not 
try to change any disk configurations during install. 
57 
58 .NOTES 
59 
60 AUTHOR: Steve Carroll - Microsoft - Sr. Customer Engineer 
61 DATE: 7/27/2021 - SC - Version 1.0.0 
62 SOURCE CODE AT: 
63 
64 VERSION HISTORY: 
65 2021/07/21 - 1.0.0 - Initial release of script 
66 2021/07/21 - 1.0.1 - Changed default parameter for DBATeamGroup to use local 
domain instead of hard-coded domain\DBATeamMembers 
67 - Added check to verify DBATeamGroup exists in current domain. 
68 2021/07/28 - 1.1.0 - Revised parameters to separate DBATeamGroup into OS 
administration from SQL administration 
69 
70 This script makes some directory assumptions: 
71 1. There is a sub-folder called InstaLlMedia\SQL[XXXX] where XXXX is the SQL 
Server version to be deployed. 
72 2. All required PowerShell modules required for this script are present in the 
PSModules sub-folder. 
73 3. All post deployment scripts can be found in the SQLScripts sub-folder. 
74 #> 
75 
76 param ( 
77 [Parameter (Mandatory=Strue)] 
78 [string]$Computer='localhost', 
79 
80 [Parameter (Mandatory=$false)] 
81 [string]$Instance, 
82 
83 [Parameter (Mandatory=$false)] 
84 [ValidateSet('SQL2016', 'SQL2017', 'SQL2019')] 
85 [string]$SQLVersion='SQL2019', 
86 
87 [Parameter (Mandatory=$false)] 
88 [ValidateSet('1', '5')] 
89 [string]$NumberOfNonOSDrives='5', 
90 
91 [Parameter (Mandatory=$false)] 
92 [string]$InstallSourcePath='\\server\ServerBuildScripts', 
93 
94 [Parameter (Mandatory=$false)] 
95 [string]$DBAOSAdminGroup="$env:USERDOMAIN\groupl", 
96 
97 [Parameter (Mandatory=$false)] 
98 [string]$DBASQLAdminGroup="$env:USERDOMAIN\group2", 
99 
100 [Parameter (Mandatory=$false)] 
101 [ValidateSet($false,Strue)] 
102 $SkipDriveConfig=$False, 
103 
104 [Parameter (Mandatory=$false)] 
105 [System.Management.Automation.PSCredential] 
106 $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please 
specify the credential used for service installation", $env:username, $env: 
USERDOMAIN) 
107 ) 
108 
109 $scriptVersion = '1.1.0' 
110 $InstallDate = get-date -format "yyyy-mm-dd HH:mm:ss K" 
111 
112 IF($Instance.Length -EQ 0) 
113 { 
114 $SQL1nstance = 'MSSQLSERVER' 
115 $1nstancePath = " 
116 $FirewallSvc = 'MSSQLSERVER' 
117 $SvcName = " 
118 } 
119 else 
120 { 
121 $SQL1nstance = $1nstance 
122 $1nstancePath = "\$1nstance" 
123 $FirewallSvc = "MSSQLs$$Instance" 
124 $SvcName = "'$$Instance" 
125 } 
126 
127 #check DBA OS Admin Group exists 
128 Try 
129 { 
130 $r = get-adgroup -Identity $DBAOSAdminGroup.Replace("$env:USERDOMAIN\", "") 
131 } 
132 catch 
133 { 
134 Write-Warning $_.exception.Message 
135 Break 
136 } 
137 
138 #check DBA SQL Admin Group exists 
139 Try 
140 { 
141 $r = get-adgroup -Identity $DBASQLAdminGroup.Replace("$env:USERDOMAIN\", "") 
142 
143 catch 
144 { 
145 Write-Warning $_.exception.Message 
146 Break 
147 
148 
149 # check install credential is valid 
150 IF($InstallCredential -eq $null) 
151 { 
152 Write-Warning "User clicked cancel at credential prompt." 
153 Break 
154 
155 ELSE 
156 { 
157 Try 
158 
159 $username = $InstallCredential.Username 
160 $root = "LDAP://n + ([ADSI]").distinguishedName 
161 $domain = New-Object System.DirectoryServices.DirectoryEntry($root,$username 
4InstallCredential.GetNetworkCredential().Password) 
162 
163 Catch 
164 
165 $ .Exception.message 
166 continue 
167 
168 
169 If(!$domain) 
170 
171 Write-Warning "Unable to query LDAP domain" 
172 break 
173 
174 Else 
175 
176 if($domain.Name -eq $null) 
177 
178 Write-Warning "Unable to authenticate '$username'" 
179 break 
180 
181 } 
182 ) 
183 
184 
185 IF(!(Test-Connection -ComputerName $Computer -Quiet)) 
186 { 
187 Write-Warning "Unable to connect to $Computer" 
188 Break 
189 } 
190 
191 IF(! (Test-Path $InstallSourcePath)) 
192 { 
193 Write-Warning "Unable to connect to $InstallSourcePath" 
194 Break 
195 
196 
197 #Convert passed parameter to expected boolean value 
198 $SkipDriveconfig = [System.Convert]::ToBoolean($SkipDriveConfig) 
199 
200 #Configure DrivePath Variables 
201 switch($NumberOfNonOSDrives) 
202 { 
203 1 { 
204 $SQLUserDBDir = "D:\SQLData$InstancePath" 
205 $SQLUserDBLogDir = "D:\SQLLogs$InstancePath" 
206 $SQLTempDBDir = "D:\SQLTempDBs$InstancePath" 
207 $SQLTempDBLogDir = "D:\SQLTempDBs$InstancePath" 
208 $SQLBackupDir = "D:\SQLBackups$InstancePath" 
209 } 
210 5 { 
211 $SQLUserDBDir = "E:\SQLData$InstancePath" 
212 $SQLUserDBLogDir = "F:\SQLLogs$InstancePath" 
213 $SQLTempDBDir = "G:\SQLTempDBs$InstancePath" 
214 $SQLTempDBLogDir = "G:\SQLTempDBs$InstancePath" 
215 $SQLBackupDir = "H:\SQLBackups$InstancePath" 
216 1 
217 } 
218 
219 #Set working directory 
220 [string]$Scriptpath = $MyInvocation.MyCommand.Path 
221 [string]$Dir = Split-Path $Scriptpath 
222 
223 #Set dir to script location. 
224 Set-Location $Dir 
225 
226 #create configuration that will copy required ps modules to target machine 
227 Configuration InstallRequiredPSModules 
228 { 
229 Import-DscResource -ModuleName PSDesiredStateConfiguration 
230 Node $A11Nodes.NodeName 
231 
232 File InstallModules 
233 
234 DestinationPath = 'c:\Program Files\WindowsPowerShell\Modules\' 
235 SourcePath = "$InstallSourcePath\PSModules\" 
236 Type = 'Directory' 
237 Ensure = 'Present' 
238 MatchSource = $true 
239 Recurse = $true 
240 Force = $true 
241 Credential = $InstallCredential 
242 
243 
244 } 
245 
246 #create configuration to configure the LCM to reboot during installation 
247 Configuration LCMConfig 
248 { 
249 Import-DscResource -ModuleName PSDesiredStateConfiguration 
250 Node $A11Nodes.NodeName 
251 
252 #Set LCM for Reboot 
253 LocalConfigurationManager 
254 
255 ActionAfterReboot = 'ContinueConfiguration' 
256 ConfigurationMode = 'ApplyOnly' 
257 RebootNodeIfNeeded = $False 
258 } 
259 } 
260 } 
261 
262 #create configure 5 drive scenario 
263 Configuration DriveConfiguration5 
264 { 
265 Import-DscResource -ModuleName PSDesiredStateConfiguration 
266 Import-DscResource -ModuleName StorageDsc 
267 Import-DscResource -ModuleName AccessControlDSC 
268 Node $A11Nodes.NodeName 
269 
270 #Configure optical drive as V:\ 
271 OpticalDiskDriveLetter CDRom 
272 
273 DiskId = 1 
274 DriveLetter = 
275 1 
276 #Configure Drive 1 for SQL System db's and binaries 
277 WaitForDisk Diskl 
278 
279 DiskId = 1 
280 RetryIntervalSec = 60 
281 RetryCount = 60 
282 } 
283 
284 Disk DVolume 
285 
286 DiskId = 1 
287 DriveLetter = 
288 FSLabel = 'SQLSystem' 
289 AllocationUnitSize = 64KB 
290 DependsOn = '[WaitForDisk]Diskl' 
291 } 
292 
293 File SQLSystemFolder 
294 
295 DestinationPath = 'D:\SQLSystem' 
296 Type = 'Directory' 
297 Ensure = 'Present' 
298 DependsOn = '[Disk]DVolume' 
299 } 
300 
301 #Configure Drive 2 for SQL Data 
302 WaitForDisk Disk2 
303 
304 DiskId = 2 
305 RetryIntervalSec = 60 
306 RetryCount = 60 
307 } 
308 
309 Disk EVolume 
310 
311 DiskId = 2 
312 DriveLetter = 'E' 
313 FSLabel = 'SQLData' 
314 AllocationUnitSize = 64KB 
315 DependsOn = '[WaitForDisk]Disk2' 
316 } 
317 
318 File SQLDataFolder 
319 
320 DestinationPath = 'E:\SQLData' 
321 Type = 'Directory' 
322 Ensure = 'Present' 
323 DependsOn = '[Disk]EVolume' 
324 } 
325 
326 #Configure Drive 3 for SQL Log files 
327 WaitForDisk Disk3 
328 
329 DiskId = 3 
330 RetryIntervalSec = 60 
331 RetryCount = 60 
332 } 
333 
334 Disk FVolume 
335 
336 DiskId = 3 
337 DriveLetter = 'F' 
338 FSLabel = 'SQLLogs' 
339 AllocationUnitSize = 64KB 
340 DependsOn = '[WaitForDisk]Disk3' 
341 } 
342 
343 File SQLLogsFolder 
344 
345 DestinationPath = IF:\SQLLogs' 
346 Type = 'Directory' 
347 Ensure = 'Present' 
348 DependsOn = '[Disk]FVolume' 
349 } 
350 
351 #Configure Drive 4 for SQL Temp DB files 
352 WaitForDisk Disk4 
353 
354 DiskId = 4 
355 RetryIntervalSec = 60 
356 RetryCount = 60 
357 1 
358 
359 Disk GVolume 
360 
361 DiskId = 4 
362 DriveLetter = 'G' 
363 FSLabel = 'SQLTempDBs' 
364 AllocationUnitSize = 64KB 
365 DependsOn = '[WaitForDisk]Disk4' 
366 } 
367 
368 File SQLTempDBSFolder 
369 
370 DestinationPath = 'G:\SQLTempDBs' 
371 Type = 'Directory' 
372 Ensure = 'Present' 
373 DependsOn = '[Disk]GVolume' 
374 1 
375 
376 #Configure Drive 5 for SQL Backup files 
377 WaitForDisk Disk5 
378 
379 DiskId = 5 
380 RetryIntervalSec = 60 
381 RetryCount = 60 
382 } 
383 
384 Disk HVolume 
385 
386 DiskId = 5 
387 DriveLetter = 'H' 
388 FSLabel = 'SQLBackups' 
389 AllocationUnitSize = 64KB 
390 DependsOn = '[WaitForDisk]Disk5' 
391 } 
392 
393 File SQLBackupsFolder 
394 
395 DestinationPath = 'H:\SQLBackups' 
396 Type = 'Directory' 
397 Ensure = 'Present' 
398 DependsOn = '[Disk]HVolume' 
399 } 
400 } 
401 } 
402 
403 #create configure 1 drive scenario 
404 Configuration DriveConfigurationl 
405 { 
406 Import-DscResource -ModuleName PSDesiredStateConfiguration 
407 Import-DscResource -ModuleName StorageDsc 
408 Import-DscResource -ModuleName AccessControlDSC 
409 Node $A11Nodes.NodeName 
410 
411 #Configure optical drive as V:\ 
412 OpticalDiskDriveLetter CDRom 
413 
414 DiskId = 1 
415 DriveLetter = 
416 } 
417 #Configure Drive 1 for SQL System db's and binaries 
418 WaitForDisk Diskl 
419 
420 DiskId = 1 
421 RetryIntervalSec = 60 
422 RetryCount = 60 
423 } 
424 
425 Disk DVolume 
426 
427 DiskId = 1 
428 DriveLetter = 
429 FSLabel = 'SQLSystem' 
430 AllocationUnitSize = 64KB 
431 DependsOn = '[WaitForDisk]Diskl' 
432 } 
433 
434 File SQLSystemFolder 
435 
436 DestinationPath = 'D:\SQLSystem' 
437 Type = 'Directory' 
438 Ensure = 'Present' 
439 DependsOn = '[Disk]DVolume' 
440 } 
441 
442 } 
443 1 
444 
445 #create configuration for SQL Server 
446 Configuration InstallSQLEngine 
447 { 
448 Import-DscResource -ModuleName PSDesiredStateConfiguration 
449 Import-DscResource -ModuleName ComputerManagementDsc 
450 Import-DscResource -ModuleName SqlServerDsc 
451 Import-DscResource -ModuleName StorageDsc 
452 Import-DscResource -ModuleName AccessControlDSC 
453 Import-DscResource -ModuleName NetworkingDsc 
454 
455 Node $A11Nodes.NodeName 
456 
457 
458 #Configure power plan for high performance 
459 PowerPlan PwrPlan 
460 
461 IsSingleInstance = 'Yes' 
462 Name = 'High performance' 
463 1 
464 
465 #Configure time zone 
466 TimeZone TimezoneEST 
467 
468 IsSingleInstance = 'Yes' 
469 TimeZone = 'Eastern Standard Time' 
470 } 
471 
472 WindowsFeature NetFramework 
473 
474 Name = 'NET-Framework-45-Core' 
475 Ensure = 'Present' 
476 } 
477 
478 File InstallMediaSQLENG 
479 
480 DestinationPath = "C:\Software\$SQLVersion" 
481 SourcePath = "$InstallSourcePath\InstallMedia\$SQLVersion" 
482 Type = 'Directory' 
483 Ensure = 'Present' 
484 MatchSource = $true 
485 Recurse = $true 
486 Force = $true 
487 Credential = $InstallCredential 
488 } 
489 
490 File InstallMediaSSMS 
491 
492 DestinationPath = 'C:\Software\SSMS' 
493 SourcePath = "$InstallSourcePath\InstallMedia\SQLManagementStudio" 
494 Type = 'Directory' 
495 Ensure = 'Present' 
496 MatchSource = $true 
497 Recurse = $true 
498 Force = $true 
499 Credential = $InstallCredential 
500 } 
501 
502 SQLSetup Instance 
503 
504 InstanceName = $SQL1nstance 
505 SourcePath = "C:\Software\$SQLVersion" 
506 Features = 'SQLENGINE,CONN,BC' 
507 SQLSysAdminAccounts = "$DBASQLAdminGroup" 
508 InstallSQLDataDir = 'D:\SQLSystem' 
509 SQLUserDBDir = "$SQLUserDBDir" 
510 SQLUserDBLogDir = "$SQLUserDBLogDir" 
511 SQLTempDBDir = "$SQLTempDBDir" 
512 SQLTempDBLogDir = "$SQLTempDBLogDir" 
513 SQLBackupDir = "$SQLBackupDir" 
514 UpdateEnabled = $true 
515 UpdateSource = "C:\Software\$SQLVersion\Updates" 
516 AgtSvcStartupType = 'Automatic' 
517 SqlSvcStartupType = 'Automatic' 
518 BrowserSvcStartupType = 'Automatic' 
.519 DependsOn = '[File]InstallMediaSQLENG','[WindowsFeature]NetFramework' 
520 
521 
522 Firewall SQLInstanceFirewall 
523 
524 Name = "SQL Service - $SQLInstance" 
525 DisplayName = "SQL Server - $SQL1nstance Instance" 
526 Ensure = 'Present' 
527 Enabled = 'True' 
528 Profile = ('Domain') 
529 Protocol = 'TCP' 
530 Service = $FirewallSvc 
531 DependsOn = '[SQLSetup]Instance' 
532 1 
533 
534 Firewall SQLBrowserFirewall 
535 
536 Name = 'SQLBrowser' 
537 DisplayName = 'SQL Server Browser Service' 
538 Ensure = 'Present' 
539 Enabled = 'True' 
540 Profile = ('Domain') 
541 Protocol = 'Any' 
542 Service = 'SQLBrowser' 
543 DependsOn = '[SQLSetup]Instance' 
544 
545 
546 #SSMS 
547 Package SSMS 
548 
549 Ensure = 'Present' 
550 Name = 'SSMS-Setup-ENU.exe' 
551 Path = 'c:\Software\SSMS\SSMS-Setup-ENU.exe' 
552 Arguments = '/install /quiet /norestart /DoNotInstallAzureDataStudio=1' 
553 ProductID = '{FFEDA3B1-242E-40C2-BB23-7E3B87DAC3C1}' ## this product id 
is associated to SSMS 18.9.1 
554 DependsOn = '[File]InstallMediaSSMS' 
555 
556 
557 #Ensure CEIP service is disabled 
558 Service DisableCEIP 
559 
560 Name = "SQLTELEMETRY$SvcName" 
561 StartupType = 'disabled' 
562 State = 'Stopped' 
563 DependsOn = '[SQLSetup]Instance' 
564 
565 
566 #Grant DBATeam to file system 
567 NTFSAccessEntry SQLSystemFarmAdmins 
568 
569 Path = 'D:\SQLSystem' 
570 AccessControlList = @( 
571 NTFSAccessControlList 
572 
573 Principal = "$DBAOSAdminGroup" 
574 ForcePrincipal = $true 
575 AccessControlEntry = @( 
576 NTFSAccessControlEntry 
577 
578 AccessControlType = 'Allow' 
579 FileSystemRights = 'FullControl' 
580 Inheritance = 'This folder subfolders and files' 
581 Ensure = 'Present' 
582 
583 
584 
585 
586 Force = $False 
587 DependsOn = '[SQLSetup]Instance' 
588 1 
589 
590 NTFSAccessEntry SQLDataFarmAdmins 
591 
592 Path = "$SQLUserDBDir" 
593 AccessControlList = @( 
594 NTFSAccessControlList 
595 
596 Principal = "$DBAOSAdminGroup" 
597 ForcePrincipal = $true 
598 AccessControlEntry = @( 
599 NTFSAccessControlEntry 
600 
601 AccessControlType = 'Allow' 
602 FileSystemRights = 'FullControl' 
603 Inheritance = 'This folder subfolders and files' 
604 Ensure = 'Present' 
605 1 
606 
607 1 
608 
609 Force = $False 
610 DependsOn = '[SQLSetup]Instance' 
611 
612 
613 NTFSAccessEntry SQLLogsFarmAdmins 
614 
615 Path = "$SQLUserDBLogDir" 
616 AccessControlList = @( 
617 NTFSAccessControlList 
618 
619 Principal = "$DBAOSAdminGroup" 
620 ForcePrincipal = $true 
621 AccessControlEntry = @( 
622 NTFSAccessControlEntry 
623 
624 AccessControlType = 'Allow' 
625 FileSystemRights = 'FullControl' 
626 Inheritance = 'This folder subfolders and files' 
627 Ensure = 'Present' 
628 1 
629 
630 
631 
632 Force = $False 
633 DependsOn = '[SQLSetup]Instance' 
634 
635 
636 NTFSAccessEntry SQLTempDBFarmAdmins 
637 
638 Path = "$SQLTempDBDir" 
639 AccessControlList = @( 
640 NTFSAccessControlList 
641 
642 Principal = "$DBAOSAdminGroup" 
643 ForcePrincipal = $true 
644 AccessControlEntry = @( 
645 NTFSAccessControlEntry 
646 
647 AccessControlType = 'Allow' 
648 FileSystemRights = 'FullControl' 
649 Inheritance = 'This folder subfolders and files' 
650 Ensure = 'Present' 
651 
652 
653 ) 
654 
655 Force = $False 
656 DependsOn = '[SQLSetup]Instance' 
657 1 
658 
659 NTFSAccessEntry SQLBackupsFarmAdmins 
660 
661 Path = "$SQLBackupDir" 
662 AccessControlList = 
663 NTFSAccessControlList 
664 
665 Principal = "$DBAOSAdminGroup" 
666 ForcePrincipal = $true 
667 AccessControlEntry = @( 
668 NTFSAccessControlEntry 
669 
670 AccessControlType = 'Allow' 
671 FileSystemRights = 'FullControl' 
672 Inheritance = 'This folder subfolders and files' 
673 Ensure = 'Present' 
674 
675 
676 
677 
678 Force = $False 
679 DependsOn = 1 [SQLSetup]Instance' 
680 
681 
682 Registry VersionStamp 
683 
684 Ensure = "Present" 
685 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL 
Server\PESB Install\$SQLInstance" 
686 ValueName = "InstallScriptVersion" 
687 ValueData = "$scriptVersion" 
688 
689 Registry InstalledBy 
690 
691 Ensure = "Present" 
692 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL 
Server\PESB Install\$SQLInstance" 
693 ValueName = "InstalledBy" 
694 ValueData = "$env:username" 
695 
696 Registry InstalledDate 
697 
698 Ensure = "Present" 
699 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL 
Server\PESB Install\$SQLInstance" 
700 ValueName = "InstalledDate" 
701 ValueData = $InstallDate 
702 
703 Registry InstallParams 
704 
705 Ensure = "Present" 
706 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL 
Server\PESB_Install\$SQLInstance" 
707 ValueType = "MultiString" 
708 ValueName = "InstallParameters" 
709 ValueData = @("Computer=$Computer","Instance=$Instance", 
"SQLVersion=$SQLVersion","NumberOfNonOSDrives=$NumberOfNonOSDrives", 
"InstallSourcePath=$InstallSourcePath", 
"DBAOSAdminGroup=$DBAOSAdminGrcup","DBASQLAdminGroup=$DBASQLAdminGroup", 
"SkipDriveConfig=$SkipDriveConfig","InstallCredential=$username") 
710 
711 
712 
713 1 
714 
715 # Setup our configuration data object that will be used by our DSC configurations 
716 $config = @( 
717 AllNodes = @( 
718 @{ 
719 NodeName = 
720 PSDscAllowPlainTextPassword = $true 
721 PsDscAllowDomainUser = $true 
722 
723 
724 ) 
725 
726 #create an array of CIM Sessions 
727 $cSessions = New-CimSession -ComputerName $Computer -Credential $InstallCredential 
728 
729 #Add each computer to the data object 
730 foreach($c in $cSessions) 
731 { 
732 $config.A11Nodes += @{NodeName=$c.ComputerName} 
733 } 
734 
735 #Create array of PSSessions that will be used to prep our target nodes 
736 $pSessions = New-PSSession -ComputerName $Computer -Credential $InstallCredential 
737 
738 #Copy dependencies to target nodes 
739 foreach($p in $pSessions)( 
740 
741 #Set the execution policy for all the targets in case it's disabled. User 
rights assignment makes a call to external scripts 
742 Invoke-Command -session $p -ScriptBlock {Set-ExecutionPolicy -ExecutionPolicy 
RemoteSigned -Force) 
743 1 
744 
745 #Install Required PsDSCModules 
746 InstallRequiredPSModules -ConfigurationData $config -OutputPath 
"$Dir\MOF\InstallPSModules" 
747 Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force 
CimSession $cSessions -ErrorAction SilentlyContinue 
748 Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force 
CimSession $cSessions -ErrorAction Stop 
749 
750 #Configure LCM 
751 LCMConfig -ConfigurationData $config -OutputPath "$Dir\MOF\LCMConfig" 
752 Set-DscLocalConfigurationManager -Path "$Dir\MOF\LCMConfig" -CimSession $cSessions 
Verbose -Force 
753 
754 *Configure Drives 
755 IF ($SkipDriveConfig -eq $False) 
756 { 
757 switch($NumberOfNonOSDrives) 
758 
759 
760 DriveConfigurationl -ConfigurationData $config -OutputPath 
"$Dir\MOF\DiskConfig" 
761 
762 5 { 
763 DriveConfiguration5 -ConfigurationData $config -OutputPath 
"$Dir\MOF\DiskConfig" 
764 
765 
766 Start-DscConfiguration -Path "$Dir\MOF\DiskConfig" -Wait -Verbose -CimSession 
$cSessions -ErrorAction Stop 
767 1 
768 
769 *Install SQL 
770 InstallSQLEngine -ConfigurationData $config -OutputPath "$Dir\MOF\SQLConfig" 
771 Start-DscConfiguration -Path "$Dir\MOF\SQLConfig" -Wait -Verbose -CimSession 
$cSessions -ErrorAction Stop 
772 
773 #reboot server on completion (wait for up to 30 minutes for powershell to be 
available 
774 restart-computer -ComputerName $Computer -Wait -for Powershell -Timeout 1800 -Delay 2 
775 
776 #Run SQLInstanceConfiguration.ps1 
777 If($Instance.Length -EQ 0) 
778 
779 .\SQLInstanceConfiguration.ps1 -Computer $Computer -InstallSourcePath 
$InstallSourcePath -InstallCredential $InstallCredential 
780 
781 else 
782 { 
783 .\SQLInstanceConfiguration.ps1 -Computer $Computer -Instance $1nstance - 
InstallSourcePath $InstallSourcePath -InstallCredential $InstallCredential 
784 } 
785 
786 