# Fixed Error Handling Utilities Module for PMC Terminal v5
# Provides centralized error handling with consistent parameter patterns
# AI: Simplified and robust error handling to prevent parameter binding conflicts

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Initialize log file path
$script:LogFilePath = Join-Path -Path $env:TEMP -ChildPath "PMCTerminal_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:MaxLogSizeMB = 10
$script:LogLevel = "Info"

# Log levels enumeration
enum LogLevel {
    Debug = 0
    Info = 1
    Warning = 2
    Error = 3
    Critical = 4
}

# AI: Simplified Invoke-WithErrorHandling with consistent parameter pattern
function Invoke-WithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Component,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Context,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData = @{}
    )
    
    # Validate parameters
    if ([string]::IsNullOrWhiteSpace($Component)) {
        $Component = "Unknown"
    }
    if ([string]::IsNullOrWhiteSpace($Context)) {
        $Context = "Unknown"
    }
    
    $startTime = [DateTime]::Now
    
    try {
        Write-Log -Level Debug -Message "Starting operation" -Component $Component -Context $Context
        
        # Execute the script block
        $result = & $ScriptBlock
        
        Write-Log -Level Debug -Message "Operation completed successfully" -Component $Component -Context $Context
        return $result
    }
    catch {
        # Create enriched error data
        $errorData = @{
            Component = $Component
            Context = $Context
            Error = $_.Exception.Message
            Exception = $_.Exception
            ScriptStackTrace = $_.ScriptStackTrace
            Duration = ([DateTime]::Now - $startTime).TotalMilliseconds
            Timestamp = Get-Date
        }
        
        # Merge additional data
        foreach ($key in $AdditionalData.Keys) {
            $errorData[$key] = $AdditionalData[$key]
        }
        
        # Log the error
        Write-Log -Level Error -Message "Error in '$Component' during '$Context': $($_.Exception.Message)" -ErrorDetails $errorData
        
        # Publish error event for global handling
        if (Get-Command -Name "Publish-Event" -ErrorAction SilentlyContinue) {
            Publish-Event -EventName "Application.Error" -Data $errorData
        }
        
        # Re-throw the original exception
        throw
    }
    finally {
        $duration = ([DateTime]::Now - $startTime).TotalMilliseconds
        Write-Log -Level Debug -Message "Operation duration: $duration ms" -Component $Component -Context $Context
    }
}

# AI: Simplified version for use in classes
function Invoke-ClassMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        
        [Parameter(Mandatory = $true)]
        [string]$MethodName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [hashtable]$Data = @{}
    )
    
    # Ensure parameters are valid
    $component = if ([string]::IsNullOrWhiteSpace($ClassName)) { "UnknownClass" } else { $ClassName }
    $context = if ([string]::IsNullOrWhiteSpace($MethodName)) { "UnknownMethod" } else { $MethodName }
    
    try {
        & $ScriptBlock
    }
    catch {
        $errorInfo = @{
            ClassName = $component
            MethodName = $context
            ErrorMessage = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
            Timestamp = Get-Date
        }
        
        # Add any additional data
        foreach ($key in $Data.Keys) {
            if (-not $errorInfo.ContainsKey($key)) {
                $errorInfo[$key] = $Data[$key]
            }
        }
        
        Write-Log -Level Error -Message "[$component.$context] $($_.Exception.Message)" -ErrorDetails $errorInfo
        throw
    }
}

# Write-Log - Centralized logging function
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = "Unknown",
        
        [Parameter(Mandatory = $false)]
        [string]$Context = "",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ErrorDetails = @{}
    )
    
    # Check if we should log based on current log level
    $currentLevel = [LogLevel]::$script:LogLevel
    $messageLevel = [LogLevel]::$Level
    
    if ($messageLevel -lt $currentLevel) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    
    # Format log entry
    $logEntry = "$timestamp [$Level] [$Component"
    if (-not [string]::IsNullOrWhiteSpace($Context)) {
        $logEntry += "::$Context"
    }
    $logEntry += "] [Thread:$threadId] $Message"
    
    # Add error details if provided
    if ($ErrorDetails.Count -gt 0) {
        try {
            # AI: Safely serialize error details to avoid issues with non-string keys or complex objects
            $serializedDetails = $ErrorDetails | ConvertTo-Json -Compress -Depth 2 -ErrorAction Stop
            $logEntry += " | Details: " + $serializedDetails
        }
        catch {
            # AI: If serialization fails, create a simple string representation
            $simpleDetails = @()
            foreach ($key in $ErrorDetails.Keys) {
                $value = $ErrorDetails[$key]
                if ($null -eq $value) {
                    $simpleDetails += "$key=null"
                }
                elseif ($value -is [string] -or $value -is [int] -or $value -is [bool] -or $value -is [datetime]) {
                    $simpleDetails += "$key=$value"
                }
                else {
                    # AI: Fixed string interpolation issue
                    $typeName = try { $value.GetType().Name } catch { "Unknown" }
                    $simpleDetails += "$key=[$typeName]"
                }
            }
            $logEntry += " | Details: {" + ($simpleDetails -join "; ") + "}"
        }
    }
    
    # Write to console with color coding
    $consoleColor = switch ($Level) {
        "Debug" { "DarkGray" }
        "Info" { "White" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Critical" { "Magenta" }
    }
    
    if ($Level -in @("Error", "Critical")) {
        Write-Host $logEntry -ForegroundColor $consoleColor -ErrorAction SilentlyContinue
    }
    elseif ($Level -eq "Warning") {
        Write-Warning $logEntry -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose $logEntry -ErrorAction SilentlyContinue
    }
    
    # Write to log file
    try {
        # Check log file size and rotate if needed
        if (Test-Path $script:LogFilePath) {
            $logFile = Get-Item $script:LogFilePath
            if ($logFile.Length -gt ($script:MaxLogSizeMB * 1MB)) {
                $archivePath = $script:LogFilePath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                Move-Item -Path $script:LogFilePath -Destination $archivePath -Force
            }
        }
        
        # Append to log file
        Add-Content -Path $script:LogFilePath -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        # Silently fail if unable to write to log file
    }
}

# Set-LogLevel - Configure the minimum log level
function Set-LogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
        [string]$Level
    )
    
    $script:LogLevel = $Level
    Write-Log -Level Info -Message "Log level set to: $Level" -Component "Logging"
}

# Get-LogLevel - Get the current log level
function Get-LogLevel {
    return $script:LogLevel
}

# Export all functions
Export-ModuleMember -Function @(
    'Invoke-WithErrorHandling',
    'Invoke-ClassMethod',
    'Write-Log',
    'Set-LogLevel',
    'Get-LogLevel'
)
