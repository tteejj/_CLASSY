#
# FILE: _CLASSY-MAIN.ps1
# PURPOSE: PMC Terminal v5 "Helios" - Class-Based Main Entry Point
# AI: FIXED - Load exceptions/logger first, then define functions that depend on them
#

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

# AI: FIXED - Corrected load order per fix guide - base classes MUST load before inheriters
$script:ModulesToLoad = @(
    # CORE: No dependencies
    @{ Name = "exceptions"; Path = "modules\exceptions.psm1"; Required = $true },
    @{ Name = "logger"; Path = "modules\logger.psm1"; Required = $true },
    @{ Name = "models"; Path = "modules\models.psm1"; Required = $true },
    
    # FOUNDATION: Depend on CORE
    @{ Name = "event-system"; Path = "modules\event-system.psm1"; Required = $true },
    @{ Name = "theme-manager"; Path = "modules\theme-manager.psm1"; Required = $true },
    @{ Name = "ui-classes"; Path = "components\ui-classes.psm1"; Required = $true },

    # SERVICES & MANAGERS: Depend on FOUNDATION
    @{ Name = "data-manager"; Path = "modules\data-manager.psm1"; Required = $true },
    @{ Name = "keybinding-service"; Path = "services\keybinding-service.psm1"; Required = $true },
    @{ Name = "focus-manager"; Path = "utilities\focus-manager.psm1"; Required = $true },
    @{ Name = "tui-framework"; Path = "modules\tui-framework.psm1"; Required = $true },
    
    # UI CLASSES: Inherit from ui-classes - MUST come after ui-classes
    @{ Name = "panels-class"; Path = "layout\panels-class.psm1"; Required = $true },
    @{ Name = "navigation-class"; Path = "components\navigation-class.psm1"; Required = $true },
    @{ Name = "advanced-data-components"; Path = "components\advanced-data-components.psm1"; Required = $true },
    
    # ENGINE & DIALOGS: Depend on everything above
    @{ Name = "tui-engine-v2"; Path = "modules\tui-engine-v2.psm1"; Required = $true },
    @{ Name = "dialog-system"; Path = "modules\dialog-system.psm1"; Required = $true },
    
    # SERVICES: Class-based services (depend on foundation)
    @{ Name = "navigation-service"; Path = "services\navigation-service-class.psm1"; Required = $true },

    # LEGACY UI (load last, minimal dependencies)
    @{ Name = "advanced-input-components"; Path = "components\advanced-input-components.psm1"; Required = $true },
    @{ Name = "tui-components"; Path = "components\tui-components.psm1"; Required = $false }
)

# AI: Updated screen modules to match existing structure
$script:ScreenModules = @(
    "dashboard\dashboard-screen",
    "task-list-screen"
)

# ===================================================================
# BOOTSTRAP: Load core modules first
# ===================================================================
try {
    # CRITICAL: Pre-load logger and exceptions BEFORE anything else
    $loggerModulePath = Join-Path $script:BasePath "modules\logger.psm1"
    $exceptionsModulePath = Join-Path $script:BasePath "modules\exceptions.psm1"
    
    if (-not (Test-Path $exceptionsModulePath)) { 
        throw "CRITICAL: The core exceptions module is missing at '$exceptionsModulePath'." 
    }
    if (-not (Test-Path $loggerModulePath)) { 
        throw "CRITICAL: The core logger module is missing at '$loggerModulePath'." 
    }
    
    Import-Module $exceptionsModulePath -Force -Global
    Import-Module $loggerModulePath -Force -Global

    # Initialize logger
    Initialize-Logger
    
} catch {
    Write-Host "FATAL ERROR during core module bootstrap: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

# ===================================================================
# MAIN FUNCTIONS: Now that error handling is available, define functions
# ===================================================================

function Initialize-PMCModules {
    param([bool]$Silent = $false)
    
    return Invoke-WithErrorHandling -Component "ModuleLoader" -Context "Initializing core and utility modules" -ScriptBlock {
        if (-not $Silent) {
            Write-Host "Verifying console environment..." -ForegroundColor Gray
        }
        
        # Console size validation
        $minWidth = 80
        $minHeight = 24
        if ($Host.UI.RawUI) {
            if ($Host.UI.RawUI.WindowSize.Width -lt $minWidth -or $Host.UI.RawUI.WindowSize.Height -lt $minHeight) {
                Write-Host "Console window too small. Please resize to at least $minWidth x $minHeight and restart." -ForegroundColor Yellow
                Read-Host "Press Enter to exit."
                throw "Console window too small."
            }
        }

        $loadedModules = @()
        $totalModules = $script:ModulesToLoad.Count
        $currentModule = 0

        foreach ($module in $script:ModulesToLoad) {
            $currentModule++
            $modulePath = Join-Path $script:BasePath $module.Path
            
            if (-not $Silent) {
                $percent = [Math]::Round(($currentModule / $totalModules) * 100)
                Write-Host "`rLoading modules... [$percent%] $($module.Name)" -NoNewline -ForegroundColor Cyan
            }
            
            if (Test-Path $modulePath) {
                try {
                    # Skip exceptions and logger since they're already loaded
                    if ($module.Name -notin @("exceptions", "logger")) {
                        Import-Module $modulePath -Force -Global
                    }
                    $loadedModules += $module.Name
                    Write-Log -Level Debug -Message "Successfully loaded module: $($module.Name)" -Data @{ Component = "ModuleLoader" }
                } catch {
                    if ($module.Required) {
                        Write-Host "`nFATAL: Failed to load required module: $($module.Name)" -ForegroundColor Red
                        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                        throw "Failed to load required module: $($module.Name). Error: $($_.Exception.Message)"
                    } else {
                        if (-not $Silent) { Write-Host "`nSkipping optional module: $($module.Name)" -ForegroundColor Yellow }
                    }
                }
            } else {
                if ($module.Required) {
                    throw "Required module file not found: $($module.Name) at $modulePath"
                }
            }
        }
        
        if (-not $Silent) { Write-Host "`rModules loaded successfully.                                    " -ForegroundColor Green }
        return $loadedModules
    }
}

function Initialize-PMCScreens {
    param([bool]$Silent = $false)
    
    return Invoke-WithErrorHandling -Component "ScreenLoader" -Context "Initializing screen modules" -ScriptBlock {
        if (-not $Silent) { Write-Host "Loading screens..." -ForegroundColor Cyan }
        
        $loadedScreens = @()
        foreach ($screenName in $script:ScreenModules) {
            $screenPath = Join-Path $script:BasePath "screens\$screenName.psm1"
            if (Test-Path $screenPath) {
                try {
                    Import-Module $screenPath -Force -Global
                    $loadedScreens += $screenName
                    Write-Log -Level Debug -Message "Successfully loaded screen: $screenName" -Data @{ Component = "ScreenLoader" }
                } catch {
                    Write-Warning "Failed to load screen module '$screenName': $_"
                }
            } else {
                Write-Warning "Screen module not found: $screenPath"
            }
        }
        
        if (-not $Silent) { Write-Host "Screens loaded: $($loadedScreens.Count) of $($script:ScreenModules.Count)" -ForegroundColor Green }
        return $loadedScreens
    }
}

function Start-PMCTerminal {
    param([bool]$Silent = $false)
    
    Invoke-WithErrorHandling -Component "Main" -Context "Main startup sequence" -ScriptBlock {
        Write-Log -Level Info -Message "PMC Terminal v5 'Helios' Class-Based startup initiated."
        
        # --- 1. Load Core Modules ---
        $loadedModules = Initialize-PMCModules -Silent:$Silent
        Write-Log -Level Info -Message "Core modules loaded: $($loadedModules -join ', ')"
        
        # --- 2. Load UI Screens ---
        $loadedScreens = Initialize-PMCScreens -Silent:$Silent
        Write-Log -Level Info -Message "Screen modules loaded: $($loadedScreens -join ', ')"
        
        # --- 3. Initialize Core Systems (in dependency order) ---
        Initialize-EventSystem
        Initialize-ThemeManager
        $dataManagerService = Initialize-DataManager
        Initialize-TuiFramework
        
        if (Get-Command Initialize-FocusManager -ErrorAction SilentlyContinue) {
            Initialize-FocusManager
        }
        Initialize-DialogSystem
        
        # --- 4. Initialize Services ---
        $keybindingService = [KeybindingService]::new()
        
        # --- 5. Assemble Service Locator ---
        $global:Services = @{
            DataManager = $dataManagerService
            Keybinding = $keybindingService
        }
        
        # AI: Initialize NavigationService with service dependencies
        $navigationService = [NavigationService]::new($global:Services)
        $global:Services.Navigation = $navigationService
        
        Write-Log -Level Info -Message "Services initialized and assembled"
        
        # --- 6. Initialize TUI Engine ---
        Initialize-TuiEngine
        
        # --- 7. Navigate to Initial Screen ---
        $startPath = "/dashboard"
        Write-Log -Level Info -Message "Navigating to initial screen: $startPath"
        
        if ($global:Services.Navigation) {
            $navigationResult = $global:Services.Navigation.GoTo($startPath)
            if (-not $navigationResult) {
                throw "Failed to navigate to initial screen at path: $startPath"
            }
        } else {
            throw "Navigation service is not available"
        }
        
        # --- 8. Start Main Loop ---
        Start-TuiLoop
        
        Write-Log -Level Info -Message "PMC Terminal exited gracefully."
    }
}

# ===================================================================
# MAIN EXECUTION BLOCK
# ===================================================================
try {
    # Start the main application logic
    Start-PMCTerminal -Silent:$false
    
} catch {
    # This is our absolute last resort error handler
    $errorMessage = "A fatal, unhandled exception occurred during application startup: $($_.Exception.Message)"
    Write-Host "`n$errorMessage" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    # Try to log if possible
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Fatal -Message $errorMessage -Data @{
            Exception = $_.Exception
            ScriptStackTrace = $_.ScriptStackTrace
        } -Force
    }
    
    # Exit with a non-zero code to indicate failure
    exit 1
}
finally {
    # Final cleanup actions
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Info -Message "Application shutting down."
    }
    
    # AI: Check if $global:Services exists before trying to access it
    if (Test-Path Variable:global:Services) {
        if ($global:Services -and $global:Services.DataManager) {
            try {
                if (Get-Member -InputObject $global:Services.DataManager -Name "SaveData" -ErrorAction SilentlyContinue) {
                    $global:Services.DataManager.SaveData()
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log -Level Info -Message "Data saved successfully."
                    }
                }
            }
            catch {
                Write-Warning "Failed to save data on exit: $_"
            }
        }
    }
    
    # Restore console
    if (Get-Command Restore-Console -ErrorAction SilentlyContinue) {
        Restore-Console
    }
}
