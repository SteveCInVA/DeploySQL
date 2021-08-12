function CopyFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestPath
    )

    write-verbose "Copy files from $SourcePath to $DestPath..."
    
    xcopy "$SourcePath" "$DestPath" /s /e /d /f /y > $null

    Write-Verbose "Copy files completed."

}