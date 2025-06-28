# --- CONFIGURATION ---
# The root folder of your existing structure where the files are located.
# This script will search recursively starting from here.
$sourceFolderStructureRoot = "C:\Users\jhnhe\Documents\GitHub\_HELIOS"

# The separate folder where files will be copied and renamed.
$destDir = "C:\Users\jhnhe\Documents\GitHub\_HELIOS\Copies"

# Path to the text file listing the filenames to process.
$fileListPath = "C:\Users\jhnhe\Documents\GitHub\_HELIOS\file_list.txt"


#
# === KEY RENAMING SETTINGS ===
#


# The NEW file extension for all processed files (e.g., ".log", ".txt"). Include the dot.
$newExtension = ".txt"

# A prefix to add to the renamed files (optional, can be "").
$newPrefix = "_"

# Set to $true to automatically delete all files in the destination
# folder before the script runs. This prevents "already exists" errors on re-runs.
$cleanDestinationBeforeRun = $true

# --- CONCATENATION SETTINGS ---
$doConcatenate = $true
$concatenatedFile = "all_processed_data.txt"

# --- SCRIPT (No need to edit below this line) ---

Write-Host "--- Starting File Processing ---" -ForegroundColor Green

# Resolve paths and perform initial checks
try {
    $sourceFolderStructureRoot = (Resolve-Path $sourceFolderStructureRoot -ErrorAction Stop).Path
    $destDir = (Resolve-Path $destDir -ErrorAction Stop).Path
    $fileListPath = (Resolve-Path $fileListPath -ErrorAction Stop).Path
} catch { Write-Error "Error resolving paths. Check your configuration."; Read-Host "Press Enter to exit"; Exit }

if (-not (Test-Path $fileListPath)) { Write-Error "File list not found: $fileListPath"; Read-Host "Press Enter to exit"; Exit }
$filesToProcess = Get-Content $fileListPath -ErrorAction Stop

# Ensure destination directory exists, create if not
if (-not (Test-Path $destDir -PathType Container)) {
    Write-Host "Destination directory '$destDir' not found. Creating it..." -ForegroundColor Yellow
    New-Item -Path $destDir -ItemType Directory | Out-Null
}

if ($cleanDestinationBeforeRun) {
    Write-Host "Cleaning destination directory: $destDir" -ForegroundColor Yellow
    Get-ChildItem -Path $destDir | Remove-Item -Recurse -Force
}

Write-Host "`n--- Step 1 & 2: Backing up (Copying) and Renaming Specified Files ---" -ForegroundColor Green
$renamedFiles = @()

# === CORE LOGIC CHANGE IS HERE ===
foreach ($filePathInList in $filesToProcess) {
    # Skip empty lines in the file list
    if ([string]::IsNullOrWhiteSpace($filePathInList)) { continue }

    # Construct the full path to the source file.
    # This handles both full paths (C:\...) and relative paths (subfolder\file.txt) in your list.
    $fullSourcePath = Join-Path -Path $sourceFolderStructureRoot -ChildPath $filePathInList
    if ([System.IO.Path]::IsPathRooted($filePathInList)) {
        $fullSourcePath = $filePathInList
    }

    Write-Host "Processing: '$fullSourcePath'" -ForegroundColor Cyan

    # Check if the specified file actually exists before trying to process it
    if (-not (Test-Path $fullSourcePath -PathType Leaf)) {
        Write-Warning "  SKIPPED: File not found at the specified path: '$fullSourcePath'"
        continue # Move to the next file in the list
    }

    # Get the file object for the validated path
    $sourceFile = Get-Item -Path $fullSourcePath

    # Construct a unique new name for the destination file
    $baseFileName = $sourceFile.BaseName
    $newFileName = "$newPrefix$baseFileName$newExtension"
    
    # In case of duplicate filenames from different subfolders, add parent folder to name
    if (($renamedFiles.Name).Contains($newFileName)) {
        $parentFolderName = $sourceFile.Directory.Name
        $newFileName = "$newPrefix${baseFileName}_$parentFolderName$newExtension"
    }

    try {
        # 1. BACKUP: Copy the exact file to the destination
        $copiedFile = Copy-Item -Path $sourceFile.FullName -Destination $destDir -PassThru -ErrorAction Stop
        
        # 2. RENAME: Rename the copy in the destination folder
        $renamedFile = Rename-Item -Path $copiedFile.FullName -NewName $newFileName -PassThru -ErrorAction Stop
        
        Write-Host "  OK: Copied and renamed to '$($renamedFile.Name)'"
        $renamedFiles += $renamedFile
    } catch {
        Write-Error "  FAILED: Error during copy or rename of '$($sourceFile.FullName)'"
        Write-Error "  $($_.Exception.Message)"
    }
}

# --- Step 3: (Optional) Concatenate the Files ---
if ($doConcatenate -and $renamedFiles.Count -gt 0) {
    Write-Host "`n--- Step 3: Concatenating Files ---" -ForegroundColor Green
    $concatenatedFilePath = Join-Path -Path $destDir -ChildPath $concatenatedFile
    if (Test-Path $concatenatedFilePath) { Remove-Item -Path $concatenatedFilePath -Force }
    Write-Host "Creating combined file '$concatenatedFile'..."
    Get-Content -Path $renamedFiles.FullName | Set-Content -Path $concatenatedFilePath
    Write-Host "All processed files have been concatenated into '$concatenatedFilePath'" -ForegroundColor Green
} elseif ($doConcatenate) {
    Write-Warning "`nConcatenation skipped: No files were successfully processed."
}

Write-Host "`n--- Process Complete! ---" -ForegroundColor Green
Read-Host "Press Enter to exit"