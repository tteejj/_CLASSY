
# MODULE: logger.psm1
# PURPOSE: Provides a robust, granular logging system for the PMC Terminal application.
# This module is self-contained and manages its own state for logging configuration and in-memory log queues.
#

# ------------------------------------------------------------------------------
# Module-Scoped State Variables
# ------------------------------------------------------------------------------
$script:LogPath = $null
$script:LogLevel = "Info" # Default log level.
$script:LogQueue = [System.Collections.Generic.List[object]]::new()
$script:MaxLogSize = 5MB
$script:LogInitialized = $false
$script:CallDepth = 0
$script:TraceAllCalls = $false

# ------------------------------------------------------------------------------
# Private Helper Functions
# ------------------------------------------------------------------------------
function ConvertTo-SerializableObject {
    param([object]$Object)
    if ($null -eq $Object) { return $null }
    $visited = New-Object 'System.Collections.Generic.HashSet[object]'
    function Convert-Internal {
        param([object]$InputObject, [int]$Depth)
        if ($null -eq $InputObject -or $Depth -gt 5) { return $null }
        if ($InputObject -is [System.Management.Automation.ScriptBlock]) { return '<ScriptBlock>' }
        if ($visited.Contains($InputObject)) { return '<CircularReference>' }
        if (-not $InputObject.GetType().IsValueType -and -not ($InputObject -is [string])) { [void]$visited.Add($InputObject) }
        switch ($InputObject.GetType().Name) {
            'Hashtable' { $r = @{}; foreach ($k in $InputObject.Keys) { try { $r[$k] = Convert-Internal $InputObject[$k] ($Depth+1) } catch { $r[$k] = "<Err>" } }; return $r }
            'PSCustomObject' { $r = @{}; foreach ($p in $InputObject.PSObject.Properties) { try { if ($p.MemberType -ne 'ScriptMethod') { $r[$p.Name] = Convert-Internal $p.Value ($Depth+1) } } catch { $r[$p.Name] = "<Err>" } }; return $r }
            'Object[]' { $r = @(); for ($i=0; $i -lt [Math]::Min($InputObject.Count,10); $i++) { try { $r += Convert-Internal $InputObject[$i] ($Depth+1) } catch { $r += "<Err>" } }; if($InputObject.Count -gt 10) { $r += "<...>" }; return $r }
            default { try { if ($InputObject -is [ValueType] -or $InputObject -is [string] -or $InputObject -is [datetime]) { return $InputObject } else { return $InputObject.ToString() } } catch { return "<Err>" } }
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
    if ([string]::IsNullOrWhiteSpace($LogDirectory) -or [string]::IsNullOrWhiteSpace($LogFileName)) { Write-Warning "Invalid logger parameters."; return }
    try {
        if (-not (Test-Path $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null }
        $script:LogPath = Join-Path $LogDirectory $LogFileName
        $script:LogLevel = $Level
        $script:LogInitialized = $true
        Write-Log -Level Info -Message "Logger initialized" -Data @{ LogPath = $script:LogPath; PowerShellVersion = $PSVersionTable.PSVersion.ToString(); OS = $PSVersionTable.OS; PID = $PID } -Force
    } catch { Write-Warning "Failed to initialize logger: $_"; $script:LogInitialized = $false }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [ValidateSet("Debug", "Verbose", "Info", "Warning", "Error", "Fatal", "Trace")] [string]$Level = "Info",
        [Parameter(Mandatory)] [string]$Message,
        [object]$Data,
        [switch]$Force
    )
    if (-not $script:LogInitialized -and -not $Force) { return }
    $levelPriority = @{ Debug=0; Trace=0; Verbose=1; Info=2; Warning=3; Error=4; Fatal=5 }
    if (-not $Force -and $levelPriority[$Level] -lt $levelPriority[$script:LogLevel]) { return }
    try {
        $caller = (Get-PSCallStack)[1]
        $logContext = @{
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"); Level = $Level; ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            CallDepth = $script:CallDepth; Message = $Message; Caller = @{ Command = $caller.Command; Location = $caller.Location; ScriptName = $caller.ScriptName; LineNumber = $caller.ScriptLineNumber }
        }
        if ($PSBoundParameters.ContainsKey('Data')) { $logContext.UserData = if ($Data -is [Exception]) { @{ Type="Exception"; Message=$Data.Message; StackTrace=$Data.StackTrace; InnerException=$Data.InnerException.Message } } else { ConvertTo-SerializableObject -Object $Data } }
        $indent = "  " * $script:CallDepth
        $callerInfo = if ($caller.ScriptName) { "$([System.IO.Path]::GetFileName($caller.ScriptName)):$($caller.ScriptLineNumber)" } else { $caller.Command }
        $logEntry = "$($logContext.Timestamp) [$($Level.PadRight(7))] $indent [$callerInfo] $Message"
        if ($PSBoundParameters.ContainsKey('Data')) { $logEntry += if ($Data -is [Exception]) { "`n${indent}  Exception: $($Data.Message)`n${indent}  StackTrace: $($Data.StackTrace)" } else { try { "`n${indent}  Data: $(ConvertTo-SerializableObject -Object $Data | ConvertTo-Json -Compress -Depth 4 -WarningAction SilentlyContinue)" } catch { "`n${indent}  Data: $($Data.ToString())" } } }
        $script:LogQueue.Add($logContext)
        if ($script:LogQueue.Count -gt 2000) { $script:LogQueue.RemoveRange(0, 1000) }
        if ($script:LogPath) {
            try {
                if ((Test-Path $script:LogPath) -and (Get-Item $script:LogPath).Length -gt $script:MaxLogSize) { Move-Item $script:LogPath ($script:LogPath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Force }
                Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8 -Force
            } catch { Write-Host "LOG WRITE FAILED: $logEntry`nError: $_" -ForegroundColor Yellow }
        }
        if ($Level -in @('Error', 'Fatal', 'Warning')) { Write-Host $logEntry -ForegroundColor ($Level -in @('Error', 'Fatal') ? 'Red' : 'Yellow') }
    } catch { try { $errorEntry = "$(Get-Date -Format 'o') [LOGGER ERROR] Failed to log: $_"; if ($script:LogPath) { Add-Content -Path $script:LogPath -Value $errorEntry -Encoding UTF8 }; Write-Host $errorEntry -ForegroundColor Red } catch { Write-Host "CRITICAL: Logger failed: $_" -ForegroundColor Red } }
}

function Trace-FunctionEntry { [CmdletBinding()] param([string]$FunctionName, [object]$Parameters); if (-not $script:TraceAllCalls) { return }; $script:CallDepth++; Write-Log -Level Trace -Message "ENTER: $FunctionName" -Data @{ Parameters=$Parameters; Action="FunctionEntry" } }
function Trace-FunctionExit { [CmdletBinding()] param([string]$FunctionName, [object]$ReturnValue, [switch]$WithError); if (-not $script:TraceAllCalls) { return }; Write-Log -Level Trace -Message "EXIT: $FunctionName" -Data @{ ReturnValue=$ReturnValue; Action=($WithError ? "FunctionExitWithError" : "FunctionExit"); HasError=$WithError.IsPresent }; $script:CallDepth = [Math]::Max(0, $script:CallDepth - 1) }
function Trace-Step { [CmdletBinding()] param([string]$StepName, [object]$StepData, [string]$Module); $caller = (Get-PSCallStack)[1]; $moduleInfo = $Module ?? ($caller.ScriptName ? [System.IO.Path]::GetFileNameWithoutExtension($caller.ScriptName) : "Unknown"); Write-Log -Level Debug -Message "STEP: $StepName" -Data @{ StepData=$StepData; Module=$moduleInfo; Action="Step" } }
function Trace-StateChange { [CmdletBinding()] param([string]$StateType, [object]$OldValue, [object]$NewValue, [string]$PropertyPath); Write-Log -Level Debug -Message "STATE: $StateType changed" -Data @{ StateType=$StateType; PropertyPath=$PropertyPath; OldValue=$OldValue; NewValue=$NewValue; Action="StateChange" } }
function Trace-ComponentLifecycle { [CmdletBinding()] param([string]$ComponentType, [string]$ComponentId, [ValidateSet('Create','Initialize','Render','Update','Destroy')] [string]$Phase, [object]$ComponentData); Write-Log -Level Debug -Message "COMPONENT: $ComponentType [$ComponentId] $Phase" -Data @{ ComponentType=$ComponentType; ComponentId=$ComponentId; Phase=$Phase; ComponentData=$ComponentData; Action="ComponentLifecycle" } }
function Trace-ServiceCall { [CmdletBinding()] param([string]$ServiceName, [string]$MethodName, [object]$Parameters, [object]$Result, [switch]$IsError); Write-Log -Level Debug -Message "SERVICE: $ServiceName.$MethodName" -Data @{ ServiceName=$ServiceName; MethodName=$MethodName; Parameters=$Parameters; Result=$Result; Action=($IsError ? "ServiceCallError" : "ServiceCall"); IsError=$IsError.IsPresent } }

function Get-LogEntries {
    [CmdletBinding()]
    param([int]$Count = 100, [string]$Level, [string]$Module, [string]$Action)
    try {
        $entries = $script:LogQueue.ToArray()
        if ($Level) { $entries = $entries | Where-Object { $_.Level -eq $Level } }
        if ($Module) { $entries = $entries | Where-Object { $_.Caller.ScriptName -and ([System.IO.Path]::GetFileNameWithoutExtension($_.Caller.ScriptName) -like "*$Module*") } }
        if ($Action) { $entries = $entries | Where-Object { $_.UserData.Action -eq $Action } }
        return $entries | Select-Object -Last $Count
    } catch { Write-Warning "Error getting log entries: $_"; return @() }
}

function Get-CallTrace {
    [CmdletBinding()]
    param([int]$Depth = 10)
    try {
        $callStack = Get-PSCallStack; $trace = @()
        for ($i = 1; $i -lt [Math]::Min($callStack.Count, $Depth + 1); $i++) { $call = $callStack[$i]; $trace += @{ Level=$i-1; Command=$call.Command; Location=$call.Location; ScriptName=$call.ScriptName; LineNumber=$call.ScriptLineNumber } }
        return $trace
    } catch { Write-Warning "Error getting call trace: $_"; return @() }
}

function Clear-LogQueue { try { $script:LogQueue.Clear(); Write-Log -Level Info -Message "In-memory log queue cleared" } catch { Write-Warning "Error clearing log queue: $_" } }
function Set-LogLevel { [CmdletBinding()] param([Parameter(Mandatory)] [ValidateSet("Debug","Verbose","Info","Warning","Error","Fatal","Trace")] [string]$Level); try { $oldLevel = $script:LogLevel; $script:LogLevel = $Level; Write-Log -Level Info -Message "Log level changed from '$oldLevel' to '$Level'" -Force } catch { Write-Warning "Error setting log level to '$Level': $_" } }
function Enable-CallTracing { $script:TraceAllCalls = $true; Write-Log -Level Info -Message "Call tracing enabled" -Force }
function Disable-CallTracing { $script:TraceAllCalls = $false; Write-Log -Level Info -Message "Call tracing disabled" -Force }
function Get-LogPath { return $script:LogPath }

function Get-LogStatistics {
    [CmdletBinding()]
    param()
    try {
        $stats = [PSCustomObject]@{ TotalEntries=$script:LogQueue.Count; LogPath=$script:LogPath; LogLevel=$script:LogLevel; CallTracingEnabled=$script:TraceAllCalls; LogFileSize=($script:LogPath -and (Test-Path $script:LogPath) ? (Get-Item $script:LogPath).Length : 0); EntriesByLevel=@{}; EntriesByModule=@{}; EntriesByAction=@{} }
        foreach ($entry in $script:LogQueue) {
            $level = $entry.Level; if (-not $stats.EntriesByLevel.ContainsKey($level)) { $stats.EntriesByLevel[$level]=0 }; $stats.EntriesByLevel[$level]++
            if ($entry.Caller.ScriptName) { $module = [System.IO.Path]::GetFileNameWithoutExtension($entry.Caller.ScriptName); if (-not $stats.EntriesByModule.ContainsKey($module)) { $stats.EntriesByModule[$module]=0 }; $stats.EntriesByModule[$module]++ }
            if ($entry.UserData.Action) { $action = $entry.UserData.Action; if (-not $stats.EntriesByAction.ContainsKey($action)) { $stats.EntriesByAction[$action]=0 }; $stats.EntriesByAction[$action]++ }
        }
        return $stats
    } catch { Write-Warning "Error getting log statistics: $_"; return [PSCustomObject]@{} }
}

Export-ModuleMember -Function 'Initialize-Logger', 'Write-Log', 'Trace-FunctionEntry', 'Trace-FunctionExit', 'Trace-Step', 'Trace-StateChange', 'Trace-ComponentLifecycle', 'Trace-ServiceCall', 'Get-LogEntries', 'Get-CallTrace', 'Clear-LogQueue', 'Set-LogLevel', 'Enable-CallTracing', 'Disable-CallTracing', 'Get-LogPath', 'Get-LogStatistics'
