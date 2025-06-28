#
# MODULE: logger.psm1
# PURPOSE: Provides a robust, granular logging system for the PMC Terminal application.
# This module is self-contained and manages its own state for logging configuration and in-memory log queues.
#

# ------------------------------------------------------------------------------
# Module-Scoped State Variables
# ------------------------------------------------------------------------------

# NOTE: The use of '$script:' scope is intentional and correct for managing state
# internal to this module. It does not violate the project's scope purity rules,
# which are designed to prevent state sharing *between* modules.

$script:LogPath = $null
$script:LogLevel = "Info" # Default log level.
$script:LogQueue = [System.Collections.Generic.List[object]]::new() # Use a generic list for better performance over @()
$script:MaxLogSize = 5MB
$script:LogInitialized = $false
$script:CallDepth = 0
$script:TraceAllCalls = $false

# ------------------------------------------------------------------------------
# Private Helper Functions
# ------------------------------------------------------------------------------

# Internal helper to safely serialize objects for logging, preventing circular references or errors.
function ConvertTo-SerializableObject {
    param([object]$Object)

    if ($null -eq $Object) { return $null }

    # Use a set to track visited objects to prevent infinite recursion
    $visited = New-Object 'System.Collections.Generic.HashSet[object]'

    function Convert-Internal {
        param([object]$InputObject, [int]$Depth)

        if ($null -eq $InputObject -or $Depth -gt 5) { return $null }
        if ($InputObject -is [System.Management.Automation.ScriptBlock]) { return '<ScriptBlock>' }
        if ($visited.Contains($InputObject)) { return '<CircularReference>' }
        
        # For non-collection reference types, add to visited set
        if (-not $InputObject.GetType().IsValueType -and -not ($InputObject -is [string])) {
            [void]$visited.Add($InputObject)
        }

        switch ($InputObject.GetType().Name) {
            'Hashtable' {
                $result = @{}
                foreach ($key in $InputObject.Keys) {
                    try {
                        $result[$key] = Convert-Internal -InputObject $InputObject[$key] -Depth ($Depth + 1)
                    } catch {
                        $result[$key] = "<SerializationError: $($_.Exception.Message)>"
                    }
                }
                return $result
            }
            'PSCustomObject' {
                $result = @{}
                foreach ($prop in $InputObject.PSObject.Properties) {
                    try {
                        # Avoid serializing script methods
                        if ($prop.MemberType -ne 'ScriptMethod') {
                           $result[$prop.Name] = Convert-Internal -InputObject $prop.Value -Depth ($Depth + 1)
                        }
                    } catch {
                        $result[$prop.Name] = "<SerializationError: $($_.Exception.Message)>"
                    }
                }
                return $result
            }
            'Object[]' {
                $result = @()
                # Limit array size for performance
                for ($i = 0; $i -lt [Math]::Min($InputObject.Count, 10); $i++) {
                    try {
                        $result += Convert-Internal -InputObject $InputObject[$i] -Depth ($Depth + 1)
                    } catch {
                        $result += "<SerializationError: $($_.Exception.Message)>"
                    }
                }
                if ($InputObject.Count -gt 10) {
                    $result += "<... $($InputObject.Count - 10) more items>"
                }
                return $result
            }
            default {
                try {
                    # For simple types, return as-is or convert to string
                    if ($InputObject -is [string] -or $InputObject -is [int] -or $InputObject -is [bool] -or $InputObject -is [double] -or $InputObject -is [datetime] -or $InputObject -is [decimal]) {
                        return $InputObject
                    } else {
                        return $InputObject.ToString()
                    }
                } catch {
                    return "<ToString failed: $($_.Exception.Message)>"
                }
            }
        }
    }

    return Convert-Internal -InputObject $Object -Depth 0
}

# ------------------------------------------------------------------------------
# Public Functions
# ------------------------------------------------------------------------------

function Initialize-Logger {
    [CmdletBinding()]
    param(
        [string]$LogDirectory = (Join-Path $env:TEMP "PMCTerminal"),
        [string]$LogFileName = "pmc_terminal_{0:yyyy-MM-dd}.log" -f (Get-Date),
        [ValidateSet("Debug", "Verbose", "Info", "Warning", "Error", "Fatal", "Trace")]
        [string]$Level = "Debug"
    )

    # Defensive checks
    if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
        Write-Warning "Initialize-Logger: LogDirectory parameter cannot be null or empty."
        return
    }
    if ([string]::IsNullOrWhiteSpace($LogFileName)) {
        Write-Warning "Initialize-Logger: LogFileName parameter cannot be null or empty."
        return
    }

    try {
        if (-not (Test-Path $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null
        }

        $script:LogPath = Join-Path $LogDirectory $LogFileName
        $script:LogLevel = $Level
        $script:LogInitialized = $true

        Write-Log -Level Info -Message "Logger initialized" -Data @{
            LogPath           = $script:LogPath
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OS                = $PSVersionTable.OS
            ProcessId         = $PID
            InitializedAt     = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        } -Force # Force this initial message to be written

    } catch {
        Write-Warning "Failed to initialize logger: $_"
        $script:LogInitialized = $false
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [ValidateSet("Debug", "Verbose", "Info", "Warning", "Error", "Fatal", "Trace")]
        [string]$Level = "Info",
        [Parameter(Mandatory)]
        [string]$Message,
        [object]$Data,
        [switch]$Force # Force logging even if level is below threshold
    )

    if (-not $script:LogInitialized -and -not $Force) { return }

    $levelPriority = @{
        Debug   = 0
        Trace   = 0
        Verbose = 1
        Info    = 2
        Warning = 3
        Error   = 4
        Fatal   = 5
    }

    if (-not $Force -and $levelPriority[$Level] -lt $levelPriority[$script:LogLevel]) { return }

    try {
        $callStack = Get-PSCallStack
        $caller = if ($callStack.Count -gt 1) { $callStack[1] } else { $callStack[0] }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId

        $logContext = @{
            Timestamp     = $timestamp
            Level         = $Level
            ThreadId      = $threadId
            CallDepth     = $script:CallDepth
            Message       = $Message
            Caller        = @{
                Command      = $caller.Command
                Location     = $caller.Location
                ScriptName   = $caller.ScriptName
                LineNumber   = $caller.ScriptLineNumber
            }
        }

        if ($PSBoundParameters.ContainsKey('Data')) {
            $logContext.UserData = if ($Data -is [Exception]) {
                @{
                    Type           = "Exception"
                    Message        = $Data.Message
                    StackTrace     = $Data.StackTrace
                    InnerException = if ($Data.InnerException) { $Data.InnerException.Message } else { $null }
                }
            } else {
                ConvertTo-SerializableObject -Object $Data
            }
        }

        $indent = "  " * $script:CallDepth
        $callerInfo = if ($caller.ScriptName) {
            "$([System.IO.Path]::GetFileName($caller.ScriptName)):$($caller.ScriptLineNumber)"
        } else {
            $caller.Command
        }

        $logEntry = "$timestamp [$($Level.PadRight(7))] $indent [$callerInfo] $Message"

        if ($PSBoundParameters.ContainsKey('Data')) {
            $dataStr = if ($Data -is [Exception]) {
                "`n${indent}  Exception: $($Data.Message)`n${indent}  StackTrace: $($Data.StackTrace)"
            } else {
                try {
                    $json = ConvertTo-SerializableObject -Object $Data | ConvertTo-Json -Compress -Depth 4 -WarningAction SilentlyContinue
                    "`n${indent}  Data: $json"
                } catch {
                    "`n${indent}  Data: $($Data.ToString())"
                }
            }
            $logEntry += $dataStr
        }

        $script:LogQueue.Add($logContext)
        if ($script:LogQueue.Count -gt 2000) {
            $script:LogQueue.RemoveRange(0, $script:LogQueue.Count - 2000)
        }

        if ($script:LogPath) {
            try {
                if ((Test-Path $script:LogPath) -and (Get-Item $script:LogPath).Length -gt $script:MaxLogSize) {
                    $archivePath = $script:LogPath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                    Move-Item $script:LogPath $archivePath -Force
                }
                Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8 -Force
            } catch {
                Write-Host "LOG WRITE FAILED: $logEntry" -ForegroundColor Yellow
                Write-Host "Error: $_" -ForegroundColor Red
            }
        }

        if ($Level -in @('Error', 'Fatal', 'Warning')) {
            $color = if ($Level -in @('Error', 'Fatal')) { 'Red' } else { 'Yellow' }
            Write-Host $logEntry -ForegroundColor $color
        }

    } catch {
        try {
            $errorEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [LOGGER ERROR] Failed to log message '$Message': $_"
            if ($script:LogPath) {
                Add-Content -Path $script:LogPath -Value $errorEntry -Encoding UTF8
            }
            Write-Host $errorEntry -ForegroundColor Red
        } catch {
            Write-Host "CRITICAL: Logger completely failed: $_" -ForegroundColor Red
        }
    }
}

function Trace-FunctionEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,
        [object]$Parameters
    )
    if (-not $script:TraceAllCalls) { return }
    $script:CallDepth++
    Write-Log -Level Trace -Message "ENTER: $FunctionName" -Data @{
        Parameters = $Parameters
        Action     = "FunctionEntry"
    }
}

function Trace-FunctionExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,
        [object]$ReturnValue,
        [switch]$WithError
    )
    if (-not $script:TraceAllCalls) { return }
    Write-Log -Level Trace -Message "EXIT: $FunctionName" -Data @{
        ReturnValue = $ReturnValue
        Action      = if ($WithError) { "FunctionExitWithError" } else { "FunctionExit" }
        HasError    = $WithError.IsPresent
    }
    $script:CallDepth--
    if ($script:CallDepth -lt 0) { $script:CallDepth = 0 }
}

function Trace-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,
        [object]$StepData,
        [string]$Module
    )
    $caller = (Get-PSCallStack)[1]
    $moduleInfo = if ($Module) { $Module } elseif ($caller.ScriptName) { [System.IO.Path]::GetFileNameWithoutExtension($caller.ScriptName) } else { "Unknown" }

    Write-Log -Level Debug -Message "STEP: $StepName" -Data @{
        StepData = $StepData
        Module   = $moduleInfo
        Action   = "Step"
    }
}

function Trace-StateChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateType,
        [object]$OldValue,
        [object]$NewValue,
        [string]$PropertyPath
    )
    Write-Log -Level Debug -Message "STATE: $StateType changed" -Data @{
        StateType    = $StateType
        PropertyPath = $PropertyPath
        OldValue     = $OldValue
        NewValue     = $NewValue
        Action       = "StateChange"
    }
}

function Trace-ComponentLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComponentType,
        [Parameter(Mandatory)]
        [string]$ComponentId,
        [Parameter(Mandatory)]
        [ValidateSet('Create', 'Initialize', 'Render', 'Update', 'Destroy')]
        [string]$Phase,
        [object]$ComponentData
    )
    Write-Log -Level Debug -Message "COMPONENT: $ComponentType [$ComponentId] $Phase" -Data @{
        ComponentType = $ComponentType
        ComponentId   = $ComponentId
        Phase         = $Phase
        ComponentData = $ComponentData
        Action        = "ComponentLifecycle"
    }
}

function Trace-ServiceCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$MethodName,
        [object]$Parameters,
        [object]$Result,
        [switch]$IsError
    )
    $action = if ($IsError) { "ServiceCallError" } else { "ServiceCall" }
    Write-Log -Level Debug -Message "SERVICE: $ServiceName.$MethodName" -Data @{
        ServiceName = $ServiceName
        MethodName  = $MethodName
        Parameters  = $Parameters
        Result      = $Result
        Action      = $action
        IsError     = $IsError.IsPresent
    }
}

function Get-LogEntries {
    [CmdletBinding()]
    param(
        [int]$Count = 100,
        [string]$Level,
        [string]$Module,
        [string]$Action
    )
    try {
        $entries = $script:LogQueue.ToArray() # Work on a copy

        if ($Level) {
            $entries = $entries | Where-Object { $_.Level -eq $Level }
        }
        if ($Module) {
            $entries = $entries | Where-Object { $_.Caller.ScriptName -and ([System.IO.Path]::GetFileNameWithoutExtension($_.Caller.ScriptName) -like "*$Module*") }
        }
        if ($Action) {
            $entries = $entries | Where-Object { $_.UserData.Action -eq $Action }
        }

        return $entries | Select-Object -Last $Count
    } catch {
        Write-Warning "Error getting log entries: $_"
        return @()
    }
}

function Get-CallTrace {
    [CmdletBinding()]
    param([int]$Depth = 10)

    try {
        $callStack = Get-PSCallStack
        $trace = @()

        for ($i = 1; $i -lt [Math]::Min($callStack.Count, $Depth + 1); $i++) { # Skip self
            $call = $callStack[$i]
            $trace += @{
                Level      = $i - 1
                Command    = $call.Command
                Location   = $call.Location
                ScriptName = $call.ScriptName
                LineNumber = $call.ScriptLineNumber
            }
        }
        return $trace
    } catch {
        Write-Warning "Error getting call trace: $_"
        return @()
    }
}

function Clear-LogQueue {
    param()
    try {
        $script:LogQueue.Clear()
        Write-Log -Level Info -Message "In-memory log queue cleared"
    } catch {
        Write-Warning "Error clearing log queue: $_"
    }
}

function Set-LogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Debug", "Verbose", "Info", "Warning", "Error", "Fatal", "Trace")]
        [string]$Level
    )
    try {
        $oldLevel = $script:LogLevel
        $script:LogLevel = $Level
        Write-Log -Level Info -Message "Log level changed from '$oldLevel' to '$Level'" -Force
    } catch {
        Write-Warning "Error setting log level to '$Level': $_"
    }
}

function Enable-CallTracing {
    param()
    $script:TraceAllCalls = $true
    Write-Log -Level Info -Message "Call tracing enabled" -Force
}

function Disable-CallTracing {
    param()
    $script:TraceAllCalls = $false
    Write-Log -Level Info -Message "Call tracing disabled" -Force
}

function Get-LogPath {
    param()
    return $script:LogPath
}

function Get-LogStatistics {
    param()
    try {
        $stats = [PSCustomObject]@{
            TotalEntries       = $script:LogQueue.Count
            LogPath            = $script:LogPath
            LogLevel           = $script:LogLevel
            CallTracingEnabled = $script:TraceAllCalls
            LogFileSize        = if ($script:LogPath -and (Test-Path $script:LogPath)) { (Get-Item $script:LogPath).Length } else { 0 }
            EntriesByLevel     = @{}
            EntriesByModule    = @{}
            EntriesByAction    = @{}
        }

        foreach ($entry in $script:LogQueue) {
            $level = $entry.Level
            if (-not $stats.EntriesByLevel.ContainsKey($level)) { $stats.EntriesByLevel[$level] = 0 }
            $stats.EntriesByLevel[$level]++

            if ($entry.Caller.ScriptName) {
                $module = [System.IO.Path]::GetFileNameWithoutExtension($entry.Caller.ScriptName)
                if (-not $stats.EntriesByModule.ContainsKey($module)) { $stats.EntriesByModule[$module] = 0 }
                $stats.EntriesByModule[$module]++
            }

            if ($entry.UserData -and $entry.UserData.Action) {
                $action = $entry.UserData.Action
                if (-not $stats.EntriesByAction.ContainsKey($action)) { $stats.EntriesByAction[$action] = 0 }
                $stats.EntriesByAction[$action]++
            }
        }

        return $stats
    } catch {
        Write-Warning "Error getting log statistics: $_"
        return [PSCustomObject]@{}
    }
}

Export-ModuleMember -Function @(
    'Initialize-Logger',
    'Write-Log',
    'Trace-FunctionEntry',
    'Trace-FunctionExit',
    'Trace-Step',
    'Trace-StateChange',
    'Trace-ComponentLifecycle',
    'Trace-ServiceCall',
    'Get-LogEntries',
    'Get-CallTrace',
    'Clear-LogQueue',
    'Set-LogLevel',
    'Enable-CallTracing',
    'Disable-CallTracing',
    'Get-LogPath',
    'Get-LogStatistics'
)