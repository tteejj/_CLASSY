
# MODULE: exceptions.psm1
# PURPOSE: Provides custom exception types and a centralized error handling wrapper
#

# ------------------------------------------------------------------------------
# Module-Scoped State Variables
# ------------------------------------------------------------------------------

$script:ErrorHistory = [System.Collections.Generic.List[object]]::new()
$script:MaxErrorHistory = 100

# ------------------------------------------------------------------------------
# Custom Exception Type Definition
# ------------------------------------------------------------------------------

try {
    if (-not ('Helios.HeliosException' -as [type])) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Management.Automation;
        using System.Collections;

        namespace Helios {
            public class HeliosException : System.Management.Automation.RuntimeException {
                public Hashtable DetailedContext { get; set; }
                public string Component { get; set; }
                public DateTime Timestamp { get; set; }

                public HeliosException(string message, string component, Hashtable detailedContext, Exception innerException)
                    : base(message, innerException) {
                    this.Component = component ?? "Unknown";
                    this.DetailedContext = detailedContext ?? new Hashtable();
                    this.Timestamp = DateTime.Now;
                }
            }

            public class NavigationException : HeliosException { public NavigationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class ServiceInitializationException : HeliosException { public ServiceInitializationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class ComponentRenderException : HeliosException { public ComponentRenderException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class StateMutationException : HeliosException { public StateMutationException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class InputHandlingException : HeliosException { public InputHandlingException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
            public class DataLoadException : HeliosException { public DataLoadException(string m, string c, Hashtable ctx, Exception i) : base(m, c, ctx, i) { } }
        }
"@ -ErrorAction Stop
    }
} catch {
    Write-Warning "CRITICAL: Failed to compile custom Helios exception types: $($_.Exception.Message). The application will lack detailed error information."
}

# ------------------------------------------------------------------------------
# Private Helper Functions
# ------------------------------------------------------------------------------

function _Identify-HeliosComponent {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    try {
        $scriptName = $ErrorRecord.InvocationInfo.ScriptName ?? (Get-PSCallStack | Where-Object ScriptName | Select-Object -First 1).ScriptName
        if (-not $scriptName) { return "Interactive/Unknown" }

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

        $componentMap = @{
            'tui-engine' = 'TUI Engine'; 'navigation' = 'Navigation Service'; 'keybindings' = 'Keybinding Service'
            'task-service' = 'Task Service'; 'helios-components' = 'Helios UI Components'; 'helios-panels' = 'Helios UI Panels'
            'dashboard-screen' = 'Dashboard Screen'; 'task-screen' = 'Task Screen'; 'exceptions' = 'Exception Module'
            'logger' = 'Logger Module'; 'Start-PMCTerminal' = 'Application Entry'
        }

        foreach ($pattern in $componentMap.Keys) {
            if ($fileName -like "*$pattern*") { return $componentMap[$pattern] }
        }
        return "Unknown ($fileName)"
    } catch { return "Component Identification Failed" }
}

function _Get-DetailedError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [hashtable]$AdditionalContext = @{}
    )
    try {
        $errorInfo = [PSCustomObject]@{
            Timestamp = Get-Date -Format "o"; Summary = $ErrorRecord.Exception.Message; Type = $ErrorRecord.Exception.GetType().FullName
            Category = $ErrorRecord.CategoryInfo.Category.ToString(); TargetObject = $ErrorRecord.TargetObject
            ScriptName = $ErrorRecord.InvocationInfo.ScriptName; LineNumber = $ErrorRecord.InvocationInfo.ScriptLineNumber
            Line = $ErrorRecord.InvocationInfo.Line; PositionMessage = $ErrorRecord.InvocationInfo.PositionMessage
            StackTrace = $ErrorRecord.Exception.StackTrace; InnerExceptions = @(); AdditionalContext = $AdditionalContext
            SystemContext = @{
                ProcessId = $PID; ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                PowerShellVersion = $PSVersionTable.PSVersion.ToString(); OS = $PSVersionTable.OS
            }
        }

        $innerEx = $ErrorRecord.Exception.InnerException
        while ($innerEx) {
            $errorInfo.InnerExceptions += [PSCustomObject]@{ Message = $innerEx.Message; Type = $innerEx.GetType().FullName; StackTrace = $innerEx.StackTrace }
            $innerEx = $innerEx.InnerException
        }
        return $errorInfo
    } catch {
        return [PSCustomObject]@{ Timestamp = Get-Date -Format "o"; Summary = "CRITICAL: Error analysis failed."; OriginalError = $ErrorRecord.Exception.Message; AnalysisError = $_.Exception.Message; Type = "ErrorAnalysisFailure" }
    }
}

# ------------------------------------------------------------------------------
# Public Functions
# ------------------------------------------------------------------------------

function Invoke-WithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Component,
        [Parameter(Mandatory)] [string]$Context,
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [hashtable]$AdditionalData = @{}
    )

    if (-not $ScriptBlock) { throw "Invoke-WithErrorHandling: ScriptBlock parameter cannot be null." }
    $Component = [string]::IsNullOrWhiteSpace($Component) ? "Unknown Component" : $Component
    $Context = [string]::IsNullOrWhiteSpace($Context) ? "Unknown Operation" : $Context

    try {
        return (& $ScriptBlock)
    }
    catch {
        $originalErrorRecord = $_
        $identifiedComponent = _Identify-HeliosComponent -ErrorRecord $originalErrorRecord
        $finalComponent = ($Component -ne "Unknown Component") ? $Component : $identifiedComponent

        $errorContext = @{ Operation = $Context }
        $AdditionalData.GetEnumerator() | ForEach-Object { $errorContext[$_.Name] = $_.Value }
        $detailedError = _Get-DetailedError -ErrorRecord $originalErrorRecord -AdditionalContext $errorContext

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level Error -Message "Error in '$finalComponent' during '$Context': $($originalErrorRecord.Exception.Message)" -Data $detailedError
        }

        [void]$script:ErrorHistory.Add($detailedError)
        if ($script:ErrorHistory.Count -gt $script:MaxErrorHistory) { $script:ErrorHistory.RemoveAt(0) }

        $contextHashtable = @{
            Operation = $Context; Timestamp = $detailedError.Timestamp; LineNumber = $detailedError.LineNumber
            ScriptName = $detailedError.ScriptName ?? "Unknown"
        }
        
        foreach ($key in $AdditionalData.Keys) {
            $value = $AdditionalData[$key]
            if ($value -is [string] -or $value -is [int] -or $value -is [bool] -or $value -is [datetime]) { $contextHashtable[$key] = $value }
        }
        
        $heliosException = New-Object Helios.HeliosException($originalErrorRecord.Exception.Message, $finalComponent, $contextHashtable, $originalErrorRecord.Exception)
        throw $heliosException
    }
}

function Get-ErrorHistory {
    [CmdletBinding()]
    param([int]$Count = 25)
    
    $total = $script:ErrorHistory.Count
    if ($Count -ge $total) { return $script:ErrorHistory }
    $start = $total - $Count
    return $script:ErrorHistory.GetRange($start, $Count)
}

Export-ModuleMember -Function 'Invoke-WithErrorHandling', 'Get-ErrorHistory'