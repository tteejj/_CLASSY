#
# MODULE: exceptions.psm1
# PURPOSE: Provides custom exception types and a centralized error handling wrapper
# for the PMC Terminal application. This ensures all errors are consistently logged
# with rich contextual information.
#

# ------------------------------------------------------------------------------
# Module-Scoped State Variables
# ------------------------------------------------------------------------------

# A running history of the most recent errors encountered in the application.
$script:ErrorHistory = [System.Collections.Generic.List[object]]::new()
$script:MaxErrorHistory = 100 # Keep a reasonable number of recent errors.

# ------------------------------------------------------------------------------
# Custom Exception Type Definition
# ------------------------------------------------------------------------------

# Define custom exception types using C# via Add-Type. This provides strongly-typed
# exceptions that can be caught specifically throughout the application.
try {
    # Only add the type if it doesn't already exist to prevent errors on module re-import.
    if (-not ('Helios.HeliosException' -as [type])) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Management.Automation;
        using System.Collections;

        namespace Helios {
            // Base exception for all custom application errors. Inherits from RuntimeException for better PowerShell integration.
            public class HeliosException : System.Management.Automation.RuntimeException {
                public Hashtable DetailedContext { get; set; }
                public string Component { get; set; }
                public DateTime Timestamp { get; set; }

                public HeliosException(string message, string component, Hashtable detailedContext, Exception innerException)
                    : base(message, innerException)
                {
                    this.Component = component ?? "Unknown";
                    this.DetailedContext = detailedContext ?? new Hashtable();
                    this.Timestamp = DateTime.Now;
                }
            }

            // Specific exception types for better categorization and targeted catch blocks.
            public class NavigationException : HeliosException { public NavigationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class ServiceInitializationException : HeliosException { public ServiceInitializationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class ComponentRenderException : HeliosException { public ComponentRenderException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class StateMutationException : HeliosException { public StateMutationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class InputHandlingException : HeliosException { public InputHandlingException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class DataLoadException : HeliosException { public DataLoadException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
        }
"@ -ErrorAction Stop
        # This log message will only appear if the logger is already imported and the log level is appropriate.
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level Debug -Message "Custom Helios exception types compiled successfully."
        }
    }
} catch {
    # If Add-Type fails, this is a critical environment issue. Log it prominently.
    # The application will fall back to using standard RuntimeExceptions.
    Write-Warning "CRITICAL: Failed to compile custom Helios exception types: $($_.Exception.Message). The application will lack detailed error information."
}


# ------------------------------------------------------------------------------
# Private Helper Functions
# ------------------------------------------------------------------------------

# Identifies the component/module where an error originated based on the call stack.
function _Identify-HeliosComponent {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    try {
        $scriptName = $ErrorRecord.InvocationInfo.ScriptName
        if (-not $scriptName) {
            # Walk the call stack to find the first script file.
            $callStack = Get-PSCallStack
            foreach ($frame in $callStack) {
                if ($frame.ScriptName) {
                    $scriptName = $frame.ScriptName
                    break
                }
            }
        }

        if (-not $scriptName) { return "Interactive/Unknown" }

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

        # Map filenames to logical application components according to the new file structure.
        $componentMap = @{
            'tui-engine'        = 'TUI Engine'
            'navigation'        = 'Navigation Service'
            'keybindings'       = 'Keybinding Service'
            'task-service'      = 'Task Service'
            'helios-components' = 'Helios UI Components'
            'helios-panels'     = 'Helios UI Panels'
            'dashboard-screen'  = 'Dashboard Screen'
            'task-screen'       = 'Task Screen'
            'exceptions'        = 'Exception Module'
            'logger'            = 'Logger Module'
            'Start-PMCTerminal' = 'Application Entry'
        }

        foreach ($pattern in $componentMap.Keys) {
            if ($fileName -like "*$pattern*") {
                return $componentMap[$pattern]
            }
        }

        return "Unknown ($fileName)"

    } catch {
        return "Component Identification Failed"
    }
}

# Gathers extensive details about an error for logging and debugging.
function _Get-DetailedError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [hashtable]$AdditionalContext = @{}
    )
    try {
        $errorInfo = [PSCustomObject]@{
            Timestamp         = Get-Date -Format "o"
            Summary           = $ErrorRecord.Exception.Message
            Type              = $ErrorRecord.Exception.GetType().FullName
            Category          = $ErrorRecord.CategoryInfo.Category.ToString()
            TargetObject      = $ErrorRecord.TargetObject
            ScriptName        = $ErrorRecord.InvocationInfo.ScriptName
            LineNumber        = $ErrorRecord.InvocationInfo.ScriptLineNumber
            Line              = $ErrorRecord.InvocationInfo.Line
            PositionMessage   = $ErrorRecord.InvocationInfo.PositionMessage
            StackTrace        = $ErrorRecord.Exception.StackTrace
            InnerExceptions   = @()
            AdditionalContext = $AdditionalContext
            SystemContext     = @{
                ProcessId         = $PID
                ThreadId          = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                OS                = $PSVersionTable.OS
            }
        }

        $innerEx = $ErrorRecord.Exception.InnerException
        while ($innerEx) {
            $errorInfo.InnerExceptions += [PSCustomObject]@{
                Message    = $innerEx.Message
                Type       = $innerEx.GetType().FullName
                StackTrace = $innerEx.StackTrace
            }
            $innerEx = $innerEx.InnerException
        }

        return $errorInfo

    } catch {
        # Fallback if the error analysis itself fails.
        return [PSCustomObject]@{
            Timestamp     = Get-Date -Format "o"
            Summary       = "CRITICAL: Error analysis failed."
            OriginalError = $ErrorRecord.Exception.Message
            AnalysisError = $_.Exception.Message
            Type          = "ErrorAnalysisFailure"
        }
    }
}

# ------------------------------------------------------------------------------
# Public Functions
# ------------------------------------------------------------------------------

function Invoke-WithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory)]
        [string]$Component,
        [Parameter(Mandatory)]
        [string]$Context, # A simple string describing the operation, e.g., "Loading tasks from disk".
        [hashtable]$AdditionalData = @{}
    )

    # Defensive checks
    if ($null -eq $ScriptBlock) {
        # This is a programming error, so we throw directly.
        throw "Invoke-WithErrorHandling: ScriptBlock parameter cannot be null."
    }
    if ([string]::IsNullOrWhiteSpace($Component)) {
        $Component = "Unknown Component"
    }
    if ([string]::IsNullOrWhiteSpace($Context)) {
        $Context = "Unknown Operation"
    }

    try {
        # Execute the provided scriptblock.
        return (& $ScriptBlock)
    }
    catch {
        # This block catches any terminating error from the ScriptBlock.
        $originalErrorRecord = $_

        # 1. Identify the component where the error occurred.
        $identifiedComponent = _Identify-HeliosComponent -ErrorRecord $originalErrorRecord
        $finalComponent = if ($Component -ne "Unknown Component") { $Component } else { $identifiedComponent }

        # 2. Gather all possible details about the error.
        $errorContext = @{
            Operation = $Context
        }
        # Merge additional data provided by the caller.
        $AdditionalData.GetEnumerator() | ForEach-Object { $errorContext[$_.Name] = $_.Value }
        $detailedError = _Get-DetailedError -ErrorRecord $originalErrorRecord -AdditionalContext $errorContext

        # 3. Log the error using the logger module.
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level Error -Message "Error in '$finalComponent' during '$Context': $($originalErrorRecord.Exception.Message)" -Data $detailedError
        }

        # 4. Add the detailed error to the in-memory history for debugging.
        [void]$script:ErrorHistory.Add($detailedError)
        if ($script:ErrorHistory.Count -gt $script:MaxErrorHistory) {
            $script:ErrorHistory.RemoveAt(0)
        }

        # 5. Create a new, rich, strongly-typed exception and throw it.
        # This allows upstream code to catch '[Helios.HeliosException]' specifically.
        # AI: Create a simplified context hashtable to avoid serialization issues
        $contextHashtable = @{
            Operation = $Context
            Timestamp = $detailedError.Timestamp
            LineNumber = $detailedError.LineNumber
            ScriptName = if ($detailedError.ScriptName) { [string]$detailedError.ScriptName } else { "Unknown" }
        }
        
        # AI: Add simple additional data only
        foreach ($key in $AdditionalData.Keys) {
            $value = $AdditionalData[$key]
            if ($value -is [string] -or $value -is [int] -or $value -is [bool] -or $value -is [datetime]) {
                $contextHashtable[$key] = $value
            }
        }
        
        $heliosException = New-Object Helios.HeliosException(
            $originalErrorRecord.Exception.Message,
            $finalComponent,
            $contextHashtable,
            $originalErrorRecord.Exception
        )
        
        # Re-throw the rich exception to allow for top-level handling.
        throw $heliosException
    }
}

function Get-ErrorHistory {
    [CmdletBinding()]
    param(
        [int]$Count = 25
    )
    
    $total = $script:ErrorHistory.Count
    if ($Count -ge $total) {
        return $script:ErrorHistory
    }

    $start = $total - $Count
    return $script:ErrorHistory.GetRange($start, $Count)
}


Export-ModuleMember -Function @(
    'Invoke-WithErrorHandling',
    'Get-ErrorHistory'
)

# NOTE: Custom types defined with Add-Type are automatically available to the session
# after the module is imported. They do not need to be explicitly exported.
