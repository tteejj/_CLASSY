# This script finds all .ps1 and .psm1 files in the current directory and its subdirectories.
# For each found file, it creates a copy with a .txt extension in the same location.
# Finally, it concatenates the content of all original .ps1 and .psm1 files into a single file named 'all.txt'
# in the current directory. Each appended file is preceded by a header indicating its relative path.

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get the current working directory, ensuring no trailing backslash for consistent path manipulation
$currentDirectory = (Get-Location).Path.TrimEnd('\')

# Define the name of the output concatenated file
$outputFileName = "all.txt"

Write-Host "Starting script operations in: $currentDirectory"

# --- Step 1: Clear the existing output file if it exists ---
try {
    if (Test-Path $outputFileName) {
        Remove-Item $outputFileName -Force -ErrorAction Stop
        Write-Host "Cleared existing '$outputFileName'."
    }
} catch {
    Write-Warning "Failed to clear '$outputFileName': $($_.Exception.Message)"
    # Continue, as this might not be a fatal error for the rest of the script
}

# --- Step 2: Find all .ps1 and .psm1 files recursively ---
try {
    $scriptFiles = Get-ChildItem -Path $currentDirectory -Recurse -Include *.ps1, *.psm1 -File -ErrorAction Stop
    Write-Host "Found $($scriptFiles.Count) PowerShell script files."
} catch {
    Write-Error "Failed to enumerate script files: $($_.Exception.Message)"
    exit 1 # Exit if we can't even find the files
}

# --- Step 3: Process each file (copy and concatenate) ---
if ($scriptFiles.Count -eq 0) {
    Write-Warning "No .ps1 or .psm1 files found to process."
} else {
    foreach ($file in $scriptFiles) {
        # Create a copy with .txt ending in the same folder
        $txtCopyPath = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + ".txt")
        try {
            Copy-Item -Path $file.FullName -Destination $txtCopyPath -Force -ErrorAction Stop
            Write-Host "  Copied: $($file.Name) to $($txtCopyPath)"
        } catch {
            Write-Warning "  Failed to copy $($file.FullName) to $($txtCopyPath): $($_.Exception.Message)"
        }

        # Prepare header for all.txt using relative path
        # Remove the base directory part from the full path to get the relative path
        $relativePath = $file.FullName.Substring($currentDirectory.Length)
        # Ensure the relative path starts with a single backslash
        if (-not $relativePath.StartsWith('\')) {
            $relativePath = '\' + $relativePath
        }

        $header = "####$relativePath"
        
        # Append the header and file content to all.txt
        try {
            Add-Content -Path $outputFileName -Value $header -Encoding UTF8 -ErrorAction Stop
            # Read the entire file content as a single string
            $fileContent = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            Add-Content -Path $outputFileName -Value $fileContent -Encoding UTF8 -ErrorAction Stop
            Add-Content -Path $outputFileName -Value "`n" -Encoding UTF8 -ErrorAction Stop # Add an extra newline for separation
            Write-Host "  Appended: $($file.Name) to $($outputFileName)"
        } catch {
            Write-Warning "  Failed to append $($file.FullName) to $($outputFileName): $($_.Exception.Message)"
        }
    }
}

Write-Host "All operations complete. Concatenated content saved to '$outputFileName'."