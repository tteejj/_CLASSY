#
# FILE: _CLASSY-MAIN.ps1
# PURPOSE: PMC Terminal v5 "Helios" - Class-Based Main Entry Point
# AI: This file has been refactored to incorporate the sophisticated module loading and
#     service initialization patterns from the R2 version, adapted for class-based architecture.
#

# Set strict mode for better error handling and PowerShell best practices.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get the directory where this script is located to build absolute paths for modules.
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

# AI: Corrected module load order to include missing components and updated dependency order
# This incorporates improvements from R2 while maintaining class-based architecture.
$script:ModulesToLoad = @(
    # Core infrastructure (no dependencies)
    @{ Name = "exceptions"; Path = "modules\exceptions.psm1"; Required = $true },
    @{ Name = "logger"; Path = "modules\logger.psm1"; Required = $true },
    @{ Name = "event-system"; Path = "modules\event-system.psm1"; Required = $true },
    @{ Name = "models"; Path = "modules\models.psm1"; Required = $true },

    # Data and theme (depend on event system and models)
    @{ Name = "data-manager"; Path = "modules\data-manager.psm1"; Required = $true },
    @{ Name = "theme-manager"; Path = "modules\theme-manager.psm1"; Required = $true },

    # Framework (depends on event system)
    @{ Name = "tui-framework"; Path = "modules\tui-framework.psm1"; Required = $true },

    # Engine (depends on theme and framework)
    @{ Name = "tui-engine-v2"; Path = "modules\tui-engine-v2.psm1"; Required = $true },

    # Dialog system (depends on engine)
    @{ Name = "dialog-system"; Path = "modules\dialog-system.psm1"; Required = $true },

    # Services (class-based)
    @{ Name = "keybinding-service"; Path = "services\keybinding-service.psm1"; Required = $true },
    @{ Name = "navigation-service"; Path = "services\navigation-service-class.psm1"; Required = $true },

    # Layout system
    @{ Name = "panels-class"; Path = "layout\panels-class.psm1"; Required = $true },

    # Focus management (depends on event system)
    @{ Name = "focus-manager"; Path = "utilities\focus-manager.psm1"; Required = $true },

    # Components (depend on engine and panels)
    @{ Name = "advanced-input-components"; Path = "components\advanced-input-components.psm1"; Required = $true },
    @{ Name = "advanced-data-components"; Path = "components\advanced-data-components.psm1"; Required = $true },
    @{ Name = "tui-components"; Path = "components\tui-components.psm1"; Required = $false },

    # UI Classes (depend on engine and models) - MUST be loaded in dependency order
    @{ Name = "ui-classes"; Path = "components\ui-classes.psm1"; Required = $true },
    @{ Name = "panel-classes"; Path = "components\panel-classes.psm1"; Required = $true },
    @{ Name = "table-class"; Path = "components\table-class.psm1"; Required = $true },
    @{ Name = "navigation-class"; Path = "components\navigation-class.psm1"; Required = $true }
)

# Screen modules will be loaded dynamically by the framework.
# AI: Updated to match existing screens in CLASSY - only load screens that exist
$script:ScreenModules = @(
    "dashboard\dashboard-screen",  # AI: Corrected path for dashboard screen
    "task-list-screen"              # AI: Keep existing class-based screen
)

function Initialize-PMCModules {
    param([bool]$Silent = $false)
    
    return Invoke-WithErrorHandling -Component "ModuleLoader" -ScriptBlock {
        if (-not $Silent) {
            Write-Host "Verifying console environment..." -ForegroundColor Gray
        }
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
                    Import-Module $modulePath -Force -Global
                    $loadedModules += $module.Name
                } catch {
                    if ($module.Required) {
                        Write-Host "`nFATAL: Failed to load required module: $($module.Name)" -ForegroundColor Red
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
    } -Context "Initializing core and utility modules"
}

function Initialize-PMCScreens {
    param([bool]$Silent = $false)
    
    return Invoke-WithErrorHandling -Component "ScreenLoader" -ScriptBlock {
        if (-not $Silent) { Write-Host "Loading screens..." -ForegroundColor Cyan }
        
        $loadedScreens = @()
        foreach ($screenName in $script:ScreenModules) {
            $screenPath = Join-Path $script:BasePath "screens\$screenName.psm1"
            if (Test-Path $screenPath) {
                try {
                    Import-Module $screenPath -Force -Global
                    $loadedScreens += $screenName
                } catch {
                    Write-Warning "Failed to load screen module '$screenName': $_"
                }
            }
        }
        
        if (-not $Silent) { Write-Host "Screens loaded: $($loadedScreens.Count) of $($script:ScreenModules.Count)" -ForegroundColor Green }
        return $loadedScreens
    } -Context "Initializing screen modules"
}

function Start-PMCTerminal {
    param([bool]$Silent = $false)
    
    Invoke-WithErrorHandling -Component "Main" -ScriptBlock {
        Write-Log -Level Info -Message "PMC Terminal v5 'Helios' Class-Based startup initiated."
        
        # --- 1. Load Core Modules ---
        $loadedModules = Initialize-PMCModules -Silent:$Silent
        Write-Log -Level Info -Message "Core modules loaded: $($loadedModules -join ', ')"
        
        # --- 2. Load UI Screens (before services that depend on them) ---
        # AI: Moved screen loading before service initialization so screen functions are available
        $loadedScreens = Initialize-PMCScreens -Silent:$Silent
        Write-Log -Level Info -Message "Screen modules loaded: $($loadedScreens -join ', ')"
        
        # --- 3. Initialize Core Systems (in dependency order) ---
        # AI: The service initialization sequence is now explicit and ordered by dependency.
        Initialize-EventSystem
        Initialize-ThemeManager
        $dataManagerService = Initialize-DataManager
        Initialize-TuiFramework
        if (Get-Command Initialize-FocusManager -ErrorAction SilentlyContinue) {
            Initialize-FocusManager
        }
        Initialize-DialogSystem
        
        # --- 4. Initialize and Assemble Class-Based Services ---
        $services = @{
            DataManager = $dataManagerService
        }
        
        # AI: Create class-based services
        if (Get-Command Initialize-KeybindingService -ErrorAction SilentlyContinue) {
            $services.Keybindings = Initialize-KeybindingService -EnableChords $false
        } else {
            # Fallback to class-based keybinding service
            $services.Keybindings = [KeybindingService]::new()
        }
        
        # AI: Initialize class-based navigation service
        if ([NavigationService]) {
            $services.Navigation = [NavigationService]::new($services)
        } else {
            Write-Log -Level Warning -Message "NavigationService class not available, using fallback initialization"
            if (Get-Command Initialize-NavigationService -ErrorAction SilentlyContinue) {
                $services.Navigation = Initialize-NavigationService $services
            }
        }
        
        $global:Services = $services
        Write-Log -Level Info -Message "All services initialized and assembled."
        
        # --- 5. Register Navigation Routes ---
        # AI: Routes are now registered automatically in the class constructor
        Write-Log -Level Info -Message "Navigation routes registered automatically."
        
        # --- 6. Initialize TUI Engine and Navigate ---
        if (-not $Silent) { Write-Host "`nStarting TUI..." -ForegroundColor Green }
        Clear-Host
        
        Initialize-TuiEngine
        
        $startPath = if ($args -contains "-start" -and ($args.IndexOf("-start") + 1) -lt $args.Count) {
            $args[$args.IndexOf("-start") + 1]
        } else {
            "/dashboard"
        }
        
        # AI: Use clean navigation abstraction - no direct access to internals
        if ($services.Navigation) {
            # Check if route is valid before navigating
            if ((Get-Member -InputObject $services.Navigation -Name "IsValidRoute" -ErrorAction SilentlyContinue) -and 
                -not $services.Navigation.IsValidRoute($startPath)) {
                Write-Log -Level Warning -Message "Startup path '$startPath' is not valid. Defaulting to /dashboard."
                $startPath = "/dashboard"
            }
            
            # Navigate using the GoTo method - returns boolean indicating success
            $navigationResult = $services.Navigation.GoTo($startPath)
            if (-not $navigationResult) {
                throw "Failed to navigate to initial screen at path: $startPath"
            }
        } else {
            throw "Navigation service is not available"
        }
        
        # --- 7. Start the Main Loop ---
        Start-TuiLoop
        
        Write-Log -Level Info -Message "PMC Terminal exited gracefully."
    } -Context "Main startup sequence"
}

# ===================================================================
# MAIN EXECUTION BLOCK
# ===================================================================
try {
    # CRITICAL: Pre-load logger and exceptions BEFORE anything else to ensure
    # error handling and logging are available throughout the entire startup sequence.
    $loggerModulePath = Join-Path $script:BasePath "modules\logger.psm1"
    $exceptionsModulePath = Join-Path $script:BasePath "modules\exceptions.psm1"
    
    if (-not (Test-Path $exceptionsModulePath)) { throw "CRITICAL: The core exceptions module is missing at '$exceptionsModulePath'." }
    if (-not (Test-Path $loggerModulePath)) { throw "CRITICAL: The core logger module is missing at '$loggerModulePath'." }
    
    Import-Module $exceptionsModulePath -Force -Global
    Import-Module $loggerModulePath -Force -Global

    # Now that logger is available, initialize it.
    Initialize-Logger
    
    # Start the main application logic, wrapped in top-level error handling.
    Start-PMCTerminal -Silent:$false
    
} catch {
    # This is our absolute last resort error handler.
    $errorMessage = "A fatal, unhandled exception occurred during application startup: $($_.Exception.Message)"
    Write-Host "`n$errorMessage" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    # Try to log if possible.
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Fatal -Message $errorMessage -Data @{
            Exception = $_.Exception
            ScriptStackTrace = $_.ScriptStackTrace
        } -Force
    }
    
    # Exit with a non-zero code to indicate failure.
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
}