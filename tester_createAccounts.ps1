clear-host

set-location (Join-Path -Path (join-path -path $env:HomeDrive -ChildPath $env:HOMEPATH) -ChildPath "\documents\source\deploysql")

.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -Action create -Verbose 

<#
.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -Action delete -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01c', 'sql01d' -ClusterName 'SQLCluster2' -Action delete -Verbose
#>