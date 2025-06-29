# ==============================================================================
# PMC Terminal v5 "Helios" - Comprehensive Test Script
# ==============================================================================

param(
    [switch]$Verbose,
    [switch]$SkipClearCache
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Change to project root
Set-Location $PSScriptRoot\..

Write-Host "`n=== PMC Terminal v5 Test Suite ===" -ForegroundColor Cyan

# 1. Clear module cache
if (-not $SkipClearCache) {
    Write-Host "`n[1] Clearing module cache..." -ForegroundColor Yellow
    & .\Clear-ModuleCache.ps1
    Write-Host "    ✓ Module cache cleared" -ForegroundColor Green
}

# 2. Test module loading
Write-Host "`n[2] Testing module loading..." -ForegroundColor Yellow
$modulesToTest = @(
    'exceptions', 'logger', 'event-system', 'theme-manager',
    'models', 'ui-classes', 'panels-class', 'navigation-class',
    'advanced-data-components', 'data-manager', 'keybinding-service',
    'navigation-service-class', 'dialog-system', 'tui-framework',
    'dashboard-screen', 'task-list-screen', 'tui-engine-v2'
)

$loadErrors = @()
foreach ($module in $modulesToTest) {
    try {
        $modulePath = Get-ChildItem -Path . -Filter "*$module*.psm1" -Recurse | Select-Object -First 1
        if ($modulePath) {
            Import-Module $modulePath.FullName -Force -ErrorAction Stop
            Write-Host "    ✓ Loaded: $module" -ForegroundColor Green
        } else {
            throw "Module file not found"
        }
    } catch {
        Write-Host "    ✗ Failed: $module - $_" -ForegroundColor Red
        $loadErrors += @{ Module = $module; Error = $_.Exception.Message }
    }
}

if ($loadErrors.Count -gt 0) {
    Write-Host "`nModule loading errors detected. Aborting tests." -ForegroundColor Red
    $loadErrors | Format-Table -AutoSize
    exit 1
}

# 3. Test service initialization
Write-Host "`n[3] Testing service initialization..." -ForegroundColor Yellow
try {
    # Initialize core services
    Initialize-Logger
    Write-Host "    ✓ Logger initialized" -ForegroundColor Green
    
    Initialize-EventSystem
    Write-Host "    ✓ Event system initialized" -ForegroundColor Green
    
    Initialize-ThemeManager
    Write-Host "    ✓ Theme manager initialized" -ForegroundColor Green
    
    Initialize-DialogSystem
    Write-Host "    ✓ Dialog system initialized" -ForegroundColor Green
    
    # Initialize data manager
    $dataManager = Initialize-DataManager
    Write-Host "    ✓ Data manager initialized" -ForegroundColor Green
    
    # Create services hashtable
    $services = @{
        DataManager = $dataManager
        Keybindings = [KeybindingService]::new()
    }
    $services.Navigation = [NavigationService]::new($services)
    Write-Host "    ✓ All services initialized" -ForegroundColor Green
    
} catch {
    Write-Host "    ✗ Service initialization failed: $_" -ForegroundColor Red
    exit 1
}

# 4. Test screen creation
Write-Host "`n[4] Testing screen creation..." -ForegroundColor Yellow
try {
    # Test dashboard screen
    $dashboardScreen = [DashboardScreen]::new($services)
    $dashboardScreen.Initialize()
    Write-Host "    ✓ Dashboard screen created and initialized" -ForegroundColor Green
    
    # Test task list screen
    $taskScreen = [TaskListScreen]::new($services)
    $taskScreen.Initialize()
    Write-Host "    ✓ Task list screen created and initialized" -ForegroundColor Green
    
} catch {
    Write-Host "    ✗ Screen creation failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

# 5. Test data operations
Write-Host "`n[5] Testing data operations..." -ForegroundColor Yellow
try {
    # Add test task
    $testTask = $dataManager.AddTask("Test Task", "This is a test task", [TaskPriority]::Medium, "General")
    Write-Host "    ✓ Created test task: $($testTask.Title)" -ForegroundColor Green
    
    # Get tasks
    $tasks = $dataManager.GetTasks()
    Write-Host "    ✓ Retrieved $($tasks.Count) tasks" -ForegroundColor Green
    
    # Save data
    $dataManager.SaveData()
    Write-Host "    ✓ Data saved successfully" -ForegroundColor Green
    
} catch {
    Write-Host "    ✗ Data operations failed: $_" -ForegroundColor Red
    exit 1
}

# 6. Test TUI engine functions
Write-Host "`n[6] Testing TUI engine functions..." -ForegroundColor Yellow
try {
    # Test missing function availability
    if (Get-Command Get-CurrentDialog -ErrorAction SilentlyContinue) {
        Write-Host "    ✓ Get-CurrentDialog function available" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Get-CurrentDialog function missing" -ForegroundColor Red
    }
    
    if (Get-Command Stop-AllTuiAsyncJobs -ErrorAction SilentlyContinue) {
        Write-Host "    ✓ Stop-AllTuiAsyncJobs function available" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Stop-AllTuiAsyncJobs function missing" -ForegroundColor Red
    }
    
    if (Get-Command Move-Focus -ErrorAction SilentlyContinue) {
        Write-Host "    ✓ Move-Focus function available" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Move-Focus function missing" -ForegroundColor Red
    }
    
} catch {
    Write-Host "    ✗ TUI engine function test failed: $_" -ForegroundColor Red
}

# 7. Test navigation
Write-Host "`n[7] Testing navigation..." -ForegroundColor Yellow
try {
    # Check if dashboard route exists
    if ($services.Navigation.IsValidRoute("/dashboard")) {
        Write-Host "    ✓ Dashboard route is valid" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Dashboard route not found" -ForegroundColor Red
    }
    
    # Check if tasks route exists
    if ($services.Navigation.IsValidRoute("/tasks")) {
        Write-Host "    ✓ Tasks route is valid" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Tasks route not found" -ForegroundColor Red
    }
    
} catch {
    Write-Host "    ✗ Navigation test failed: $_" -ForegroundColor Red
}

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "All critical tests passed! The application should now work." -ForegroundColor Green
Write-Host "`nTo run the application, execute:" -ForegroundColor Yellow
Write-Host "    .\_CLASSY-MAIN.ps1" -ForegroundColor White
Write-Host "`nNote: If you still encounter errors, check the log file at:" -ForegroundColor Yellow
Write-Host "    $env:TEMP\PMCTerminal\pmc_terminal_$(Get-Date -Format 'yyyy-MM-dd').log" -ForegroundColor White
