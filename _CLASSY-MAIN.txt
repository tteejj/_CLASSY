# ==============================================================================
# PMC Terminal v5 "Helios" - Modern PowerShell 7 Main Entry Point
# ==============================================================================

# --- Declarative Module Loading ---
# PowerShell 7+ loads all necessary modules and their classes/functions here.
# Order is important: dependencies must be loaded before dependents.

# Core Services (no dependencies)
using module '.\modules\exceptions.psm1'
using module '.\modules\logger.psm1'
using module '.\modules\event-system.psm1'
using module '.\modules\theme-manager.psm1'

# Base Classes
using module '.\modules\models.psm1'
using module '.\components\ui-classes.psm1'

# Components (depend on base classes)
using module '.\layout\panels-class.psm1'
using module '.\components\navigation-class.psm1'
using module '.\components\advanced-data-components.psm1'
using module '.\components\advanced-input-components.psm1'
using module '.\components\tui-components.psm1'

# Framework & Services (depend on core services and models)
using module '.\modules\data-manager.psm1'
using module '.\services\keybinding-service.psm1'
using module '.\services\navigation-service-class.psm1'
using module '.\modules\dialog-system.psm1'
using module '.\modules\tui-framework.psm1'

# Screens (depend on services and components)
using module '.\screens\dashboard\dashboard-screen.psm1'
using module '.\screens\task-list-screen.psm1'

# Engine (loaded last, depends on many utilities)
using module '.\modules\tui-engine-v2.psm1'

# --- Script Configuration ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Main Application Logic ---
function Start-PMCTerminal {
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "Main" -Context "Main startup sequence" -ScriptBlock {
        # --- 1. Initialize Core Systems ---
        Initialize-Logger
        Write-Log -Level Info -Message "PMC Terminal v5 'Helios' startup initiated."
        
        Initialize-EventSystem
        Initialize-ThemeManager
        Initialize-DialogSystem
        
        # --- 2. Initialize and Assemble Services ---
        $services = @{
            DataManager = Initialize-DataManager
            Keybindings = [KeybindingService]::new()
        }
        $services.Navigation = [NavigationService]::new($services)
        
        $global:Services = $services
        Write-Log -Level Info -Message "All services initialized and assembled."
        
        # --- 3. Initialize TUI Engine and Navigate ---
        Write-Host "`nStarting TUI..." -ForegroundColor Green
        Clear-Host
        
        Initialize-TuiEngine
        
        $startPath = if ($args -contains "-start" -and ($args.IndexOf("-start") + 1) -lt $args.Count) {
            $args[$args.IndexOf("-start") + 1]
        } else {
            "/dashboard"
        }
        
        if (-not $services.Navigation.IsValidRoute($startPath)) {
            Write-Log -Level Warning -Message "Startup path '$startPath' is not valid. Defaulting to /dashboard."
            $startPath = "/dashboard"
        }
        
        $services.Navigation.GoTo($startPath, @{})
        
        # --- 4. Start the Main Loop ---
        Start-TuiLoop
        
        Write-Log -Level Info -Message "PMC Terminal exited gracefully."
    }
}

# --- Main Execution Block ---
try {
    Start-PMCTerminal
}
catch {
    $errorMessage = "A fatal, unhandled exception occurred: $($_.Exception.Message)"
    Write-Host "`n$errorMessage" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Fatal -Message $errorMessage -Data @{ Exception = $_.Exception; Stack = $_.ScriptStackTrace } -Force
    }
    
    exit 1
}
finally {
    if ($global:Services -and $global:Services.DataManager) {
        try {
            $global:Services.DataManager.SaveData()
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log -Level Info -Message "Data saved on exit." -Force
            }
        }
        catch {
            Write-Warning "Failed to save data on exit: $_"
        }
    }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Info -Message "Application shutdown complete." -Force
    }
}
