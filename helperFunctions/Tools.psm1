<#
 ###########################################################
 Copyright (C) 2021 Microsoft Corporation

    Disclaimer:
    This is SAMPLE code that is NOT production ready. It is the sole intention of this code to provide a proof of concept as a
    learning tool for Microsoft Customers. Microsoft does not provide warranty for or guarantee any portion of this code
    and is NOT responsible for any affects it may have on any system it is executed on or environment it resides within.
    Please use this code at your own discretion!

    Additional legalese:

    This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED ""AS IS"" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute
    the object code form of the Sample Code, provided that You agree:
    (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded;
    (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and
    (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees,
    that arise or result from the use or distribution of the Sample Code.
 ###########################################################
#>

function CopyFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestPath
    )

    Write-Verbose "Copy files from $SourcePath to $DestPath..."
    try {
        xcopy "$SourcePath" "$DestPath" /s /e /d /f /y > $null
        Write-Verbose "Copy files completed."
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

function GetFileHashes {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $hashes = Get-ChildItem -Path $Path -Recurse -File |
        Get-FileHash -Algorithm SHA256 | Select-Object * -ExcludeProperty Algorithm

        $folderHashes = New-Object System.Collections.ArrayList

        foreach ($x in $hashes) {
            $f = "" | Select-Object "File", "Hash"
            $f.File = $x.Path.Replace($path, "")
            $f.Hash = $x.Hash
            $folderHashes.Add($f) | Out-Null
        }
        return $folderHashes
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

function Get-FolderHash {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $file = New-TemporaryFile
        GetFileHashes($path) | Export-Csv $file
        $hash = (Get-FileHash $file).Hash
        Remove-Item -Path $file
        return $hash
    }
    catch {
        Write-Warning $_.Exception.Message
    }

}