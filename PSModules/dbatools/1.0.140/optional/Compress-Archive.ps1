if ($PSVersionTable.PSVersion.Major -lt 5) {

    <#
Copied from the Microsoft Module: Microsoft.PowerShell.Archive
Which ships with PowerShell Version 5 but will run under v3.
    #>



    function Compress-Archive {
        <#
            .SYNOPSIS
                Creates an archive, or zipped file, from specified files and folders.

            .DESCRIPTION
                The Compress-Archive cmdlet creates a zipped (or compressed) archive file from one or more specified files or folders. An archive file allows multiple files to be packaged, and optionally compressed, into a single zipped file for easier distribution and storage. An archive file can be compressed by using the compression algorithm specified by the CompressionLevel parameter.

                Because Compress-Archive relies upon the Microsoft .NET Framework API System.IO.Compression.ZipArchive to compress files, the maximum file size that you can compress by using Compress-Archive is currently 2 GB. This is a limitation of the underlying API.

            .PARAMETER Path
                Specifies the path or paths to the files that you want to add to the archive zipped file. This parameter can accept wildcard characters. Wildcard characters allow you to add all files in a folder to your zipped archive file. To specify multiple paths, and include files in multiple locations in your output zipped file, use commas to separate the paths.

            .PARAMETER LiteralPath
                Specifies the path or paths to the files that you want to add to the archive zipped file. Unlike the Path parameter, the value of LiteralPath is used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters, enclose each escape character in single quotation marks, to instruct Windows PowerShell not to interpret any characters as escape sequences. To specify multiple paths, and include files in multiple locations in your output zipped file, use commas to separate the paths.

            .PARAMETER DestinationPath
                Specifies the path to the archive output file. This parameter is required. The specified DestinationPath value should include the desired name of the output zipped file; it specifies either the absolute or relative path to the zipped file. If the file name specified in DestinationPath does not have a .zip file name extension, the cmdlet adds a .zip file name extension.

            .PARAMETER CompressionLevel
                Specifies how much compression to apply when you are creating the archive file. Faster compression requires less time to create the file, but can result in larger file sizes. The acceptable values for this parameter are:

                - Fastest. Use the fastest compression method available to decrease processing time; this can result in larger file sizes.
                - NoCompression. Do not compress the source files.
                - Optimal. Processing time is dependent on file size.

                If this parameter is not specified, the command uses the default value, Optimal.

            .PARAMETER Update
                Updates the specified archive by replacing older versions of files in the archive with newer versions of files that have the same names. You can also add this parameter to add files to an existing archive.

            .PARAMETER Force
                @{Text=}

            .PARAMETER Confirm
                Prompts you for confirmation before running the cmdlet.

            .PARAMETER WhatIf
                Shows what would happen if the cmdlet runs. The cmdlet is not run.

            .EXAMPLE
                Example 1: Create an archive file

                PS C:\>Compress-Archive -LiteralPath C:\Reference\Draftdoc.docx, C:\Reference\Images\diagram2.vsd -CompressionLevel Optimal -DestinationPath C:\Archives\Draft.Zip

                This command creates a new archive file, Draft.zip, by compressing two files, Draftdoc.docx and diagram2.vsd, specified by the LiteralPath parameter. The compression level specified for this operation is Optimal.

            .EXAMPLE
                Example 2: Create an archive with wildcard characters

                PS C:\>Compress-Archive -Path C:\Reference\* -CompressionLevel Fastest -DestinationPath C:\Archives\Draft

                This command creates a new archive file, Draft.zip, in the C:\Archives folder. Note that though the file name extension .zip was not added to the value of the DestinationPath parameter, Windows PowerShell appends this to the specified archive file name automatically. The new archive file contains every file in the C:\Reference folder, because a wildcard character was used in place of specific file names in the Path parameter. The specified compression level is Fastest, which might result in a larger output file, but compresses a large number of files faster.

            .EXAMPLE
                Example 3: Update an existing archive file

                PS C:\>Compress-Archive -Path C:\Reference\* -Update -DestinationPath C:\Archives\Draft.Zip

                This command updates an existing archive file, Draft.Zip, in the C:\Archives folder. The command is run to update Draft.Zip with newer versions of existing files that came from the C:\Reference folder, and also to add new files that have been added to C:\Reference since Draft.Zip was initially created.

            .EXAMPLE
                Example 4: Create an archive from an entire folder

                PS C:\>Compress-Archive -Path C:\Reference -DestinationPath C:\Archives\Draft

                This command creates an archive from an entire folder, C:\Reference. Note that though the file name extension .zip was not added to the value of the DestinationPath parameter, Windows PowerShell appends this to the specified archive file name automatically.
        #>
        [CmdletBinding(DefaultParameterSetName = "Path", SupportsShouldProcess, HelpUri = "http://go.microsoft.com/fwlink/?LinkID=393252")]
        param
        (
            [parameter (Mandatory, ParameterSetName = "Path", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "PathWithForce", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "PathWithUpdate", ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            $Path,

            [parameter (Mandatory, ParameterSetName = "LiteralPath", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "LiteralPathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [parameter (Mandatory, ParameterSetName = "LiteralPathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName)]
            [ValidateNotNullOrEmpty()]
            [Alias("PSPath")]
            [string[]]
            $LiteralPath,

            [parameter (Mandatory,
                Position = 1,
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [ValidateNotNullOrEmpty()]
            [string]
            $DestinationPath,

            [parameter (
                mandatory = $false,
                ValueFromPipeline = $false,
                ValueFromPipelineByPropertyName = $false)]
            [ValidateSet("Optimal", "NoCompression", "Fastest")]
            [string]
            $CompressionLevel = "Optimal",

            [parameter(Mandatory, ParameterSetName = "PathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [parameter(Mandatory, ParameterSetName = "LiteralPathWithUpdate", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [switch]
            $Update = $false,

            [parameter(Mandatory, ParameterSetName = "PathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [parameter(Mandatory, ParameterSetName = "LiteralPathWithForce", ValueFromPipeline = $false, ValueFromPipelineByPropertyName = $false)]
            [switch]
            $Force = $false
        )

        BEGIN {
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Ignore
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Ignore

            $zipFileExtension = ".zip"

            $LocalizedData = ConvertFrom-StringData @'
    PathNotFoundError=The path '{0}' either does not exist or is not a valid file system path.
    ExpandArchiveInValidDestinationPath=The path '{0}' is not a valid file system directory path.
    InvalidZipFileExtensionError={0} is not a supported archive file format. {1} is the only supported archive file format.
    ArchiveFileIsReadOnly=The attributes of the archive file {0} is set to 'ReadOnly' hence it cannot be updated. If you intend to update the existing archive file, remove the 'ReadOnly' attribute on the archive file else use -Force parameter to override and create a new archive file.
    ZipFileExistError=The archive file {0} already exists. Use the -Update parameter to update the existing archive file or use the -Force parameter to overwrite the existing archive file.
    DuplicatePathFoundError=The input to {0} parameter contains a duplicate path '{1}'. Provide a unique set of paths as input to {2} parameter.
    ArchiveFileIsEmpty=The archive file {0} is empty.
    CompressProgressBarText=The archive file '{0}' creation is in progress...
    ExpandProgressBarText=The archive file '{0}' expansion is in progress...
    AppendArchiveFileExtensionMessage=The archive file path '{0}' supplied to the DestinationPath patameter does not include .zip extension. Hence .zip is appended to the supplied DestinationPath path and the archive file would be created at '{1}'.
    AddItemtoArchiveFile=Adding '{0}'.
    CreateFileAtExpandedPath=Created '{0}'.
    InvalidArchiveFilePathError=The archive file path '{0}' specified as input to the {1} parameter is resolving to multiple file system paths. Provide a unique path to the {2} parameter where the archive file has to be created.
    InvalidExpandedDirPathError=The directory path '{0}' specified as input to the DestinationPath parameter is resolving to multiple file system paths. Provide a unique path to the Destination parameter where the archive file contents have to be expanded.
    FileExistsError=Failed to create file '{0}' while expanding the archive file '{1}' contents as the file '{2}' already exists. Use the -Force parameter if you want to overwrite the existing directory '{3}' contents when expanding the archive file.
    DeleteArchiveFile=The partially created archive file '{0}' is deleted as it is not usable.
    InvalidDestinationPath=The destination path '{0}' does not contain a valid archive file name.
    PreparingToCompressVerboseMessage=Preparing to compress...
    PreparingToExpandVerboseMessage=Preparing to expand...
'@

            #region Utility Functions
            function GetResolvedPathHelper {
                param
                (
                    [string[]]
                    $path,

                    [boolean]
                    $isLiteralPath,

                    [System.Management.Automation.PSCmdlet]
                    $callerPSCmdlet
                )

                $resolvedPaths = @()

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    try {
                        if ($isLiteralPath) {
                            $currentResolvedPaths = Resolve-Path -LiteralPath $currentPath -ErrorAction Stop
                        } else {
                            $currentResolvedPaths = Resolve-Path -Path $currentPath -ErrorAction Stop
                        }
                    } catch {
                        $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
                        $exception = New-Object System.InvalidOperationException $errorMessage, $_.Exception
                        $errorRecord = CreateErrorRecordHelper "ArchiveCmdletPathNotFound" $null ([System.Management.Automation.ErrorCategory]::InvalidArgument) $exception $currentPath
                        $callerPSCmdlet.ThrowTerminatingError($errorRecord)
                    }

                    foreach ($currentResolvedPath in $currentResolvedPaths) {
                        $resolvedPaths += $currentResolvedPath.ProviderPath
                    }
                }

                $resolvedPaths
            }

            function Add-CompressionAssemblies {

                if ($PSEdition -eq "Desktop") {
                    Add-Type -AssemblyName System.IO.Compression
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                }
            }

            function IsValidFileSystemPath {
                param
                (
                    [string[]]
                    $path
                )

                $result = $true;

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    if (!([System.IO.File]::Exists($currentPath) -or [System.IO.Directory]::Exists($currentPath))) {
                        $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
                        ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
                    }
                }

                return $result;
            }


            function ValidateDuplicateFileSystemPath {
                param
                (
                    [string]
                    $inputParameter,

                    [string[]]
                    $path
                )

                $uniqueInputPaths = @()

                # null and empty check are are already done on Path parameter at the cmdlet layer.
                foreach ($currentPath in $path) {
                    $currentInputPath = $currentPath.ToUpper()
                    if ($uniqueInputPaths.Contains($currentInputPath)) {
                        $errorMessage = ($LocalizedData.DuplicatePathFoundError -f $inputParameter, $currentPath, $inputParameter)
                        ThrowTerminatingErrorHelper "DuplicatePathFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
                    } else {
                        $uniqueInputPaths += $currentInputPath
                    }
                }
            }

            function CompressionLevelMapper {
                param
                (
                    [string]
                    $compressionLevel
                )

                $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Optimal

                # CompressionLevel format is already validated at the cmdlet layer.
                switch ($compressionLevel.ToString()) {
                    "Fastest" {
                        $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Fastest
                    }
                    "NoCompression" {
                        $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::NoCompression
                    }
                }

                return $compressionLevelFormat
            }

            function CompressArchiveHelper {
                param
                (
                    [string[]]
                    $sourcePath,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode
                )

                $numberOfItemsArchived = 0
                $sourceFilePaths = @()
                $sourceDirPaths = @()

                foreach ($currentPath in $sourcePath) {
                    $result = Test-Path -LiteralPath $currentPath -PathType Leaf
                    if ($result -eq $true) {
                        $sourceFilePaths += $currentPath
                    } else {
                        $sourceDirPaths += $currentPath
                    }
                }

                # The Soure Path contains one or more directory (this directory can have files under it) and no files to be compressed.
                if ($sourceFilePaths.Count -eq 0 -and $sourceDirPaths.Count -gt 0) {
                    $currentSegmentWeight = 100 / [double]$sourceDirPaths.Count
                    $previousSegmentWeight = 0
                    foreach ($currentSourceDirPath in $sourceDirPaths) {
                        $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                        $numberOfItemsArchived += $count
                        $previousSegmentWeight += $currentSegmentWeight
                    }
                }

                # The Soure Path contains only files to be compressed.
                elseIf ($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -eq 0) {
                    # $previousSegmentWeight is equal to 0 as there are no prior segments.
                    # $currentSegmentWeight is set to 100 as all files have equal weightage.
                    $previousSegmentWeight = 0
                    $currentSegmentWeight = 100

                    $numberOfItemsArchived = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                }
                # The Soure Path contains one or more files and one or more directories (this directory can have files under it) to be compressed.
                elseif ($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -gt 0) {
                    # each directory is considered as an individual segments & all the individual files are clubed in to a separate sgemnet.
                    $currentSegmentWeight = 100 / [double]($sourceDirPaths.Count + 1)
                    $previousSegmentWeight = 0

                    foreach ($currentSourceDirPath in $sourceDirPaths) {
                        $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                        $numberOfItemsArchived += $count
                        $previousSegmentWeight += $currentSegmentWeight
                    }

                    $count = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
                    $numberOfItemsArchived += $count
                }

                return $numberOfItemsArchived
            }

            function CompressFilesHelper {
                param
                (
                    [string[]]
                    $sourceFilePaths,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                $numberOfItemsArchived = ZipArchiveHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $null $previousSegmentWeight $currentSegmentWeight

                return $numberOfItemsArchived
            }

            function CompressSingleDirHelper {
                param
                (
                    [string]
                    $sourceDirPath,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $useParentDirAsRoot,

                    [bool]
                    $isUpdateMode,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                [System.Collections.Generic.List[System.String]]$subDirFiles = @()

                if ($useParentDirAsRoot) {
                    $sourceDirInfo = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $sourceDirPath
                    $sourceDirFullName = $sourceDirInfo.Parent.FullName

                    # If the directory is present at the drive level the DirectoryInfo.Parent include '\' example: C:\
                    # On the other hand if the directory exists at a deper level then DirectoryInfo.Parent
                    # has just the path (without an ending '\'). example C:\source
                    if ($sourceDirFullName.Length -eq 3) {
                        $modifiedSourceDirFullName = $sourceDirFullName
                    } else {
                        $modifiedSourceDirFullName = $sourceDirFullName + "\"
                    }
                } else {
                    $sourceDirFullName = $sourceDirPath
                    $modifiedSourceDirFullName = $sourceDirFullName + "\"
                }

                $dirContents = Get-ChildItem -LiteralPath $sourceDirPath -Recurse
                foreach ($currentContent in $dirContents) {
                    $isContainer = $currentContent -is [System.IO.DirectoryInfo]
                    if (!$isContainer) {
                        $subDirFiles.Add($currentContent.FullName)
                    } else {
                        # The currentContent points to a directory.
                        # We need to check if the directory is an empty directory, if so such a
                        # directory has to be explictly added to the archive file.
                        # if there are no files in the directory the GetFiles() API returns an empty array.
                        $files = $currentContent.GetFiles()
                        if ($files.Count -eq 0) {
                            $subDirFiles.Add($currentContent.FullName + "\")
                        }
                    }
                }

                $numberOfItemsArchived = ZipArchiveHelper $subDirFiles.ToArray() $destinationPath $compressionLevel $isUpdateMode $modifiedSourceDirFullName $previousSegmentWeight $currentSegmentWeight

                return $numberOfItemsArchived
            }

            function ZipArchiveHelper {
                param
                (
                    [System.Collections.Generic.List[System.String]]
                    $sourcePaths,

                    [string]
                    $destinationPath,

                    [string]
                    $compressionLevel,

                    [bool]
                    $isUpdateMode,

                    [string]
                    $modifiedSourceDirFullName,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight
                )

                $numberOfItemsArchived = 0
                $fileMode = [System.IO.FileMode]::Create
                $result = Test-Path -LiteralPath $DestinationPath -PathType Leaf
                if ($result -eq $true) {
                    $fileMode = [System.IO.FileMode]::Open
                }

                Add-CompressionAssemblies

                try {
                    # At this point we are sure that the archive file has write access.
                    $archiveFileStreamArgs = @($destinationPath, $fileMode)
                    $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

                    $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
                    $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs

                    $currentEntryCount = 0
                    $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $destinationPath)
                    $bufferSize = 4kb
                    $buffer = New-Object Byte[] $bufferSize

                    foreach ($currentFilePath in $sourcePaths) {
                        if ($modifiedSourceDirFullName -ne $null -and $modifiedSourceDirFullName.Length -gt 0) {
                            $index = $currentFilePath.IndexOf($modifiedSourceDirFullName, [System.StringComparison]::OrdinalIgnoreCase)
                            $currentFilePathSubString = $currentFilePath.Substring($index, $modifiedSourceDirFullName.Length)
                            $relativeFilePath = $currentFilePath.Replace($currentFilePathSubString, "").Trim()
                        } else {
                            $relativeFilePath = [System.IO.Path]::GetFileName($currentFilePath)
                        }

                        # Update mode is selected.
                        # Check to see if archive file already contains one or more zip files in it.
                        if ($isUpdateMode -eq $true -and $zipArchive.Entries.Count -gt 0) {
                            $entryToBeUpdated = $null

                            # Check if the file already exists in the archive file.
                            # If so replace it with new file from the input source.
                            # If the file does not exist in the archive file then default to
                            # create mode and create the entry in the archive file.

                            foreach ($currentArchiveEntry in $zipArchive.Entries) {
                                if ($currentArchiveEntry.FullName -eq $relativeFilePath) {
                                    $entryToBeUpdated = $currentArchiveEntry
                                    break
                                }
                            }

                            if ($entryToBeUpdated -ne $null) {
                                $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                                $entryToBeUpdated.Delete()
                            }
                        }

                        $compression = CompressionLevelMapper $compressionLevel

                        # If a directory needs to be added to an archive file,
                        # by convention the .Net API's expect the path of the diretcory
                        # to end with '\' to detect the path as an directory.
                        if (!$relativeFilePath.EndsWith("\", [StringComparison]::OrdinalIgnoreCase)) {
                            try {
                                try {
                                    $currentFileStream = [System.IO.File]::Open($currentFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                                } catch {
                                    # Failed to access the file. Write a non terminating error to the pipeline
                                    # and move on with the remaining files.
                                    $exception = $_.Exception
                                    if ($null -ne $_.Exception -and
                                        $null -ne $_.Exception.InnerException) {
                                        $exception = $_.Exception.InnerException
                                    }
                                    $errorRecord = CreateErrorRecordHelper "CompressArchiveUnauthorizedAccessError" $null ([System.Management.Automation.ErrorCategory]::PermissionDenied) $exception $currentFilePath
                                    Write-Error -ErrorRecord $errorRecord
                                }

                                if ($null -ne $currentFileStream) {
                                    $srcStream = New-Object System.IO.BinaryReader $currentFileStream

                                    $currentArchiveEntry = $zipArchive.CreateEntry($relativeFilePath, $compression)

                                    # Updating  the File Creation time so that the same timestamp would be retained after expanding the compressed file.
                                    # At this point we are sure that Get-ChildItem would succeed.
                                    $currentArchiveEntry.LastWriteTime = (Get-Item -LiteralPath $currentFilePath).LastWriteTime

                                    $destStream = New-Object System.IO.BinaryWriter $currentArchiveEntry.Open()

                                    while ($numberOfBytesRead = $srcStream.Read($buffer, 0, $bufferSize)) {
                                        $destStream.Write($buffer, 0, $numberOfBytesRead)
                                        $destStream.Flush()
                                    }

                                    $numberOfItemsArchived += 1
                                    $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                                }
                            } finally {
                                If ($null -ne $currentFileStream) {
                                    $currentFileStream.Dispose()
                                }
                                If ($null -ne $srcStream) {
                                    $srcStream.Dispose()
                                }
                                If ($null -ne $destStream) {
                                    $destStream.Dispose()
                                }
                            }
                        } else {
                            $currentArchiveEntry = $zipArchive.CreateEntry("$relativeFilePath", $compression)
                            $numberOfItemsArchived += 1
                            $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                        }

                        if ($null -ne $addItemtoArchiveFileMessage) {
                            Write-Verbose $addItemtoArchiveFileMessage
                        }

                        $currentEntryCount += 1
                        ProgressBarHelper "Compress-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $sourcePaths.Count  $currentEntryCount
                    }
                } finally {
                    If ($null -ne $zipArchive) {
                        $zipArchive.Dispose()
                    }

                    If ($null -ne $archiveFileStream) {
                        $archiveFileStream.Dispose()
                    }

                    # Complete writing progress.
                    Write-Progress -Activity "Compress-Archive" -Completed
                }

                return $numberOfItemsArchived
            }

            <############################################################################################
# ValidateArchivePathHelper: This is a helper function used to validate the archive file
# path & its file format. The only supported archive file format is .zip
############################################################################################>
            function ValidateArchivePathHelper {
                param
                (
                    [string]
                    $archiveFile
                )

                if ([System.IO.File]::Exists($archiveFile)) {
                    $extension = [system.IO.Path]::GetExtension($archiveFile)

                    # Invalid file extension is specifed for the zip file.
                    if ($extension -ne $zipFileExtension) {
                        $errorMessage = ($LocalizedData.InvalidZipFileExtensionError -f $extension, $zipFileExtension)
                        ThrowTerminatingErrorHelper "NotSupportedArchiveFileExtension" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $extension
                    }
                } else {
                    $errorMessage = ($LocalizedData.PathNotFoundError -f $archiveFile)
                    ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $archiveFile
                }
            }

            <############################################################################################
# ExpandArchiveHelper: This is a helper function used to expand the archive file contents
# to the specified directory.
############################################################################################>
            function ExpandArchiveHelper {
                param
                (
                    [string]
                    $archiveFile,

                    [string]
                    $expandedDir,

                    [ref]
                    $expandedItems,

                    [boolean]
                    $force,

                    [boolean]
                    $isVerbose,

                    [boolean]
                    $isConfirm
                )

                Add-CompressionAssemblies

                try {
                    # The existance of archive file has already been validated by ValidateArchivePathHelper
                    # before calling this helper function.
                    $archiveFileStreamArgs = @($archiveFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                    $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

                    $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
                    $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs

                    if ($zipArchive.Entries.Count -eq 0) {
                        $archiveFileIsEmpty = ($LocalizedData.ArchiveFileIsEmpty -f $archiveFile)
                        Write-Verbose $archiveFileIsEmpty
                        return
                    }

                    $currentEntryCount = 0
                    $progressBarStatus = ($LocalizedData.ExpandProgressBarText -f $archiveFile)

                    # The archive entries can either be empty directories or files.
                    foreach ($currentArchiveEntry in $zipArchive.Entries) {
                        $currentArchiveEntryPath = Join-Path -Path $expandedDir -ChildPath $currentArchiveEntry.FullName
                        $extension = [system.IO.Path]::GetExtension($currentArchiveEntryPath)

                        # The current archive entry is an empty directory
                        # The FullName of the Archive Entry representing a directory would end with a trailing '\'.
                        if ($extension -eq [string]::Empty -and
                            $currentArchiveEntryPath.EndsWith("\", [StringComparison]::OrdinalIgnoreCase)) {
                            $pathExists = Test-Path -LiteralPath $currentArchiveEntryPath

                            # The current archive entry expects an empty directory.
                            # Check if the existing directory is empty. If its not empty
                            # then it means that user has added this directory by other means.
                            if ($pathExists -eq $false) {
                                New-Item $currentArchiveEntryPath -ItemType Directory -Confirm:$isConfirm | Out-Null

                                if (Test-Path -LiteralPath $currentArchiveEntryPath -PathType Container) {
                                    $addEmptyDirectorytoExpandedPathMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentArchiveEntryPath)
                                    Write-Verbose $addEmptyDirectorytoExpandedPathMessage

                                    $expandedItems.Value += $currentArchiveEntryPath
                                }
                            }
                        } else {
                            try {
                                $currentArchiveEntryFileInfo = New-Object -TypeName System.IO.FileInfo -ArgumentList $currentArchiveEntryPath
                                $parentDirExists = Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container

                                # If the Parent directory of the current entry in the archive file does not exist, then create it.
                                if ($parentDirExists -eq $false) {
                                    New-Item $currentArchiveEntryFileInfo.DirectoryName -ItemType Directory -Confirm:$isConfirm | Out-Null

                                    if (!(Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container)) {
                                        # The directory referred by $currentArchiveEntryFileInfo.DirectoryName was not successfully created.
                                        # This could be because the user has specified -Confirm paramter when Expand-Archive was invoked
                                        # and authorization was not provided when confirmation was prompted. In such a scenario,
                                        # we skip the current file in the archive and continue with the remaining archive file contents.
                                        Continue
                                    }

                                    $expandedItems.Value += $currentArchiveEntryFileInfo.DirectoryName
                                }

                                $hasNonTerminatingError = $false

                                # Check if the file in to which the current archive entry contents
                                # would be expanded already exists.
                                if ($currentArchiveEntryFileInfo.Exists) {
                                    if ($force) {
                                        Remove-Item -LiteralPath $currentArchiveEntryFileInfo.FullName -Force -ErrorVariable ev -Verbose:$isVerbose -Confirm:$isConfirm
                                        if ($ev -ne $null) {
                                            $hasNonTerminatingError = $true
                                        }

                                        if (Test-Path -LiteralPath $currentArchiveEntryFileInfo.FullName -PathType Leaf) {
                                            # The file referred by $currentArchiveEntryFileInfo.FullName was not successfully removed.
                                            # This could be because the user has specified -Confirm paramter when Expand-Archive was invoked
                                            # and authorization was not provided when confirmation was prompted. In such a scenario,
                                            # we skip the current file in the archive and continue with the remaining archive file contents.
                                            Continue
                                        }
                                    } else {
                                        # Write non-terminating error to the pipeline.
                                        $errorMessage = ($LocalizedData.FileExistsError -f $currentArchiveEntryFileInfo.FullName, $archiveFile, $currentArchiveEntryFileInfo.FullName, $currentArchiveEntryFileInfo.FullName)
                                        $errorRecord = CreateErrorRecordHelper "ExpandArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $null $currentArchiveEntryFileInfo.FullName
                                        Write-Error -ErrorRecord $errorRecord
                                        $hasNonTerminatingError = $true
                                    }
                                }

                                if (!$hasNonTerminatingError) {
                                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($currentArchiveEntry, $currentArchiveEntryPath, $false)

                                    # Add the expanded file path to the $expandedItems array,
                                    # to keep track of all the expanded files created while expanding the archive file.
                                    # If user enters CTRL + C then at that point of time, all these expanded files
                                    # would be deleted as part of the clean up process.
                                    $expandedItems.Value += $currentArchiveEntryPath

                                    $addFiletoExpandedPathMessage = ($LocalizedData.CreateFileAtExpandedPath -f $currentArchiveEntryPath)
                                    Write-Verbose $addFiletoExpandedPathMessage
                                }
                            } finally {
                                If ($null -ne $destStream) {
                                    $destStream.Dispose()
                                }

                                If ($null -ne $srcStream) {
                                    $srcStream.Dispose()
                                }
                            }
                        }

                        $currentEntryCount += 1
                        # $currentSegmentWeight is Set to 100 giving equal weightage to each file that is getting expanded.
                        # $previousSegmentWeight is set to 0 as there are no prior segments.
                        $previousSegmentWeight = 0
                        $currentSegmentWeight = 100
                        ProgressBarHelper "Expand-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $zipArchive.Entries.Count  $currentEntryCount
                    }
                } finally {
                    If ($null -ne $zipArchive) {
                        $zipArchive.Dispose()
                    }

                    If ($null -ne $archiveFileStream) {
                        $archiveFileStream.Dispose()
                    }

                    # Complete writing progress.
                    Write-Progress -Activity "Expand-Archive" -Completed
                }
            }

            <############################################################################################
# ProgressBarHelper: This is a helper function used to display progress message.
# This function is used by both Compress-Archive & Expand-Archive to display archive file
# creation/expansion progress.
############################################################################################>
            function ProgressBarHelper {
                param
                (
                    [string]
                    $cmdletName,

                    [string]
                    $status,

                    [double]
                    $previousSegmentWeight,

                    [double]
                    $currentSegmentWeight,

                    [int]
                    $totalNumberofEntries,

                    [int]
                    $currentEntryCount
                )

                if ($currentEntryCount -gt 0 -and
                    $totalNumberofEntries -gt 0 -and
                    $previousSegmentWeight -ge 0 -and
                    $currentSegmentWeight -gt 0) {
                    $entryDefaultWeight = $currentSegmentWeight / [double]$totalNumberofEntries

                    $percentComplete = $previousSegmentWeight + ($entryDefaultWeight * $currentEntryCount)
                    Write-Progress -Activity $cmdletName -Status $status -PercentComplete $percentComplete
                }
            }

            <############################################################################################
# CSVHelper: This is a helper function used to append comma after each path specifid by
# the SourcePath array. This helper function is used to display all the user supplied paths
# in the WhatIf message.
############################################################################################>
            function CSVHelper {
                param
                (
                    [string[]]
                    $sourcePath
                )

                # SourcePath has already been validated by the calling funcation.
                if ($sourcePath.Count -gt 1) {
                    $sourcePathInCsvFormat = "`n"
                    for ($currentIndex = 0; $currentIndex -lt $sourcePath.Count; $currentIndex++) {
                        if ($currentIndex -eq $sourcePath.Count - 1) {
                            $sourcePathInCsvFormat += $sourcePath[$currentIndex]
                        } else {
                            $sourcePathInCsvFormat += $sourcePath[$currentIndex] + "`n"
                        }
                    }
                } else {
                    $sourcePathInCsvFormat = $sourcePath
                }

                return $sourcePathInCsvFormat
            }

            <############################################################################################
# ThrowTerminatingErrorHelper: This is a helper function used to throw terminating error.
############################################################################################>
            function ThrowTerminatingErrorHelper {
                param
                (
                    [string]
                    $errorId,

                    [string]
                    $errorMessage,

                    [System.Management.Automation.ErrorCategory]
                    $errorCategory,

                    [object]
                    $targetObject,

                    [Exception]
                    $innerException
                )

                if ($innerException -eq $null) {
                    $exception = New-object System.IO.IOException $errorMessage
                } else {
                    $exception = New-Object System.IO.IOException $errorMessage, $innerException
                }

                $exception = New-Object System.IO.IOException $errorMessage
                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            <############################################################################################
# CreateErrorRecordHelper: This is a helper function used to create an ErrorRecord
############################################################################################>
            function CreateErrorRecordHelper {
                param
                (
                    [string]
                    $errorId,

                    [string]
                    $errorMessage,

                    [System.Management.Automation.ErrorCategory]
                    $errorCategory,

                    [Exception]
                    $exception,

                    [object]
                    $targetObject
                )

                if ($null -eq $exception) {
                    $exception = New-Object System.IO.IOException $errorMessage
                }

                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
                return $errorRecord
            }
            #endregion Utility Functions

            $inputPaths = @()
            $destinationParentDir = [system.IO.Path]::GetDirectoryName($DestinationPath)
            if ($null -eq $destinationParentDir) {
                $errorMessage = ($LocalizedData.InvalidDestinationPath -f $DestinationPath)
                ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            if ($destinationParentDir -eq [string]::Empty) {
                $destinationParentDir = '.'
            }

            $achiveFileName = [system.IO.Path]::GetFileName($DestinationPath)
            $destinationParentDir = GetResolvedPathHelper $destinationParentDir $false $PSCmdlet

            if ($destinationParentDir.Count -gt 1) {
                $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $DestinationPath, "DestinationPath", "DestinationPath")
                ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            IsValidFileSystemPath $destinationParentDir | Out-Null
            $DestinationPath = Join-Path -Path $destinationParentDir -ChildPath $achiveFileName

            # GetExtension API does not validate for the actual existance of the path.
            $extension = [system.IO.Path]::GetExtension($DestinationPath)

            # If user does not specify .Zip extension, we append it.
            If ($extension -eq [string]::Empty) {
                $DestinationPathWithOutExtension = $DestinationPath
                $DestinationPath = $DestinationPathWithOutExtension + $zipFileExtension
                $appendArchiveFileExtensionMessage = ($LocalizedData.AppendArchiveFileExtensionMessage -f $DestinationPathWithOutExtension, $DestinationPath)
                Write-Verbose $appendArchiveFileExtensionMessage
            } else {
                # Invalid file extension is specified for the zip file to be created.
                if ($extension -ne $zipFileExtension) {
                    $errorMessage = ($LocalizedData.InvalidZipFileExtensionError -f $extension, $zipFileExtension)
                    ThrowTerminatingErrorHelper "NotSupportedArchiveFileExtension" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $extension
                }
            }

            $archiveFileExist = Test-Path -LiteralPath $DestinationPath -PathType Leaf

            if ($archiveFileExist -and ($Update -eq $false -and $Force -eq $false)) {
                $errorMessage = ($LocalizedData.ZipFileExistError -f $DestinationPath)
                ThrowTerminatingErrorHelper "ArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
            }

            # If archive file already exists and if -Update is specified, then we check to see
            # if we have write access permission to update the existing archive file.
            if ($archiveFileExist -and $Update -eq $true) {
                $item = Get-Item -Path $DestinationPath
                if ($item.Attributes.ToString().Contains("ReadOnly")) {
                    $errorMessage = ($LocalizedData.ArchiveFileIsReadOnly -f $DestinationPath)
                    ThrowTerminatingErrorHelper "ArchiveFileIsReadOnly" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $DestinationPath
                }
            }

            $isWhatIf = $psboundparameters.ContainsKey("WhatIf")
            if (!$isWhatIf) {
                $preparingToCompressVerboseMessage = ($LocalizedData.PreparingToCompressVerboseMessage)
                Write-Verbose $preparingToCompressVerboseMessage

                $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $DestinationPath)
                ProgressBarHelper "Compress-Archive" $progressBarStatus 0 100 100 1
            }
        }
        PROCESS {
            if ($PsCmdlet.ParameterSetName -eq "Path" -or
                $PsCmdlet.ParameterSetName -eq "PathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "PathWithUpdate") {
                $inputPaths += $Path
            }

            if ($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate") {
                $inputPaths += $LiteralPath
            }
        }
        END {
            # If archive file already exists and if -Force is specified, we delete the
            # existing artchive file and create a brand new one.
            if (($PsCmdlet.ParameterSetName -eq "PathWithForce" -or
                    $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce") -and $archiveFileExist) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction Stop
            }

            # Validate Source Path depeding on parameter set being used.
            # The specified source path conatins one or more files or directories that needs
            # to be compressed.
            $isLiteralPathUsed = $false
            if ($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
                $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate") {
                $isLiteralPathUsed = $true
            }

            ValidateDuplicateFileSystemPath $PsCmdlet.ParameterSetName $inputPaths
            $resolvedPaths = GetResolvedPathHelper $inputPaths $isLiteralPathUsed $PSCmdlet
            IsValidFileSystemPath $resolvedPaths | Out-Null

            $sourcePath = $resolvedPaths;

            # CSVHelper: This is a helper function used to append comma after each path specifid by
            # the $sourcePath array. The comma saperated paths are displayed in the -WhatIf message.
            $sourcePathInCsvFormat = CSVHelper $sourcePath
            if ($pscmdlet.ShouldProcess($sourcePathInCsvFormat)) {
                try {
                    # StopProcessing is not avaliable in Script cmdlets. However the pipleline execution
                    # is terminated when ever 'CTRL + C' is entered by user to terminate the cmdlet execution.
                    # The finally block is executed whenever pipleline is terminated.
                    # $isArchiveFileProcessingComplete variable is used to track if 'CTRL + C' is entered by the
                    # user.
                    $isArchiveFileProcessingComplete = $false

                    $numberOfItemsArchived = CompressArchiveHelper $sourcePath $DestinationPath $CompressionLevel $Update

                    $isArchiveFileProcessingComplete = $true
                } finally {
                    # The $isArchiveFileProcessingComplete would be set to $false if user has typed 'CTRL + C' to
                    # terminate the cmdlet execution or if an unhandled exception is thrown.
                    # $numberOfItemsArchived contains the count of number of files or directories add to the archive file.
                    # If the newly created archive file is empty then we delete it as its not usable.
                    if (($isArchiveFileProcessingComplete -eq $false) -or
                        ($numberOfItemsArchived -eq 0)) {
                        $DeleteArchiveFileMessage = ($LocalizedData.DeleteArchiveFile -f $DestinationPath)
                        Write-Verbose $DeleteArchiveFileMessage

                        # delete the partial archive file created.
                        if (Test-Path $DestinationPath) {
                            Remove-Item -LiteralPath $DestinationPath -Force -Recurse -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZawYJKoZIhvcNAQcCoIIZXDCCGVgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU15pU+7Qx8kXADN8lJSi26USR
# 88ugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBEwwggRIAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFI5z6PGMR8l+nd0y8f03HydIJ5krMA0GCSqGSIb3DQEBAQUABIIBAKuAMjOh
# PPCqkOCTCS3h1xhzxKJ4rzmVlOD5L3eTLixpktBS3N6qQ74LElPY50JcIofieCpU
# cRo5wwP7lZh9JY9M56QQY/9UKSkTpO6T+7HZ7M01UFOdHXJIja5yGu7rXx4VJ3Ji
# PbVbjv1hRdtmGv6AGpSqnbWPssPDFA9zCbY12WGk+nMwauJCY9KnAPzHwWh0Y3JM
# x/QDe0MCRSbI/kvjiXeLnb1OTfEg3bOmUOcWZA9AU4Blb0njcT+NGv4rZquEilte
# GlXHXhAbOYN/1/AiXjOITVWVu9ax808KpJCFHUpJe9QShPG7fsH+s9iR4tzoJem7
# /rEcMKhHAwdRZDKhggIgMIICHAYJKoZIhvcNAQkGMYICDTCCAgkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TAJBgUrDgMCGgUAoF0w
# GAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjEwMjIz
# MTcyMTQxWjAjBgkqhkiG9w0BCQQxFgQU3Hn+rQWkDmUkd9gc8mZM2stYfxQwDQYJ
# KoZIhvcNAQEBBQAEggEAayLgWV9+4hVbqTvfUyGIPdJ9pSAz1Be9uDQQ9FHWXu1r
# 3ufbmBfkpISj7Q8NV9eygQwdxPow1+e87R8OsngyML+PwAcJivNryFeerjse/XKq
# T+fyE8HDm+dmMNQ4KQUjtMeup96y8vJ4iuHJGraI43hPWbPtyQZugXBJzKdhQOEe
# AaGJFkVk1lr7wYuVVGnfKWCppJBnLUftFTbIF6OhdIHRxq/aOPSMj3as/+dM/mWg
# MuR2KDJreEuI3fzF7tmU7lLUvnoPpBqTyZIx156t2Hy6q1K4Jl/7poZxjR4i/7u9
# t4EBbW69qHBx8rSGwIb3MkHXaIativsRt7r7r5E5bQ==
# SIG # End signature block
