# Description

The `SqlAGDatabase` DSC resource is used to add databases or remove
databases from a specified availability group.
When a replica has Automatic seeding on Automatic, no restore is use for that replica.
When all replicas are on automatic seeding, no backup is made, unless the database has never been backuped.

## Requirements

* Target machine must be running Windows Server 2012 or later.
* Target machine must be running SQL Server Database Engine 2012 or later.
* Target machine must be running Windows Management Framework (WMF) 5 or later.

## Known issues

All issues are not listed here, see [here for all open issues](https://github.com/dsccommunity/SqlServerDsc/issues?q=is%3Aissue+is%3Aopen+in%3Atitle+SqlAGDatabase).
