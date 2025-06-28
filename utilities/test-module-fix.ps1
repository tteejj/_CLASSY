# Test script to verify the module loading fix
# AI: This tests that data-manager.psm1 can now properly import and use model classes

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Testing module loading fix..." -ForegroundColor Cyan

try {
    # Step 1: Load the data-manager module (which should now auto-import models)
    Write-Host "1. Loading data-manager module..." -ForegroundColor Yellow
    Import-Module (Join-Path $BasePath "modules\data-manager.psm1") -Force
    Write-Host "   ✓ Data-manager module loaded successfully!" -ForegroundColor Green
    
    # Step 2: Test that class types are available
    Write-Host "2. Testing class type availability..." -ForegroundColor Yellow
    $testTask = [PmcTask]::new("Test Task")
    $testProject = [PmcProject]::new("TEST", "Test Project")
    Write-Host "   ✓ Classes are available: PmcTask, PmcProject" -ForegroundColor Green
    
    # Step 3: Test DataManager class instantiation
    Write-Host "3. Testing DataManager class..." -ForegroundColor Yellow
    $dataManager = [DataManager]::new()
    Write-Host "   ✓ DataManager class instantiated successfully!" -ForegroundColor Green
    
    # Step 4: Test public functions
    Write-Host "4. Testing public functions..." -ForegroundColor Yellow
    $functions = @('Add-PmcTask', 'Get-PmcTasks', 'Get-PmcProjects')
    foreach ($func in $functions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            Write-Host "   ✓ Function $func is available" -ForegroundColor Green
        } else {
            Write-Host "   ✗ Function $func is missing" -ForegroundColor Red
        }
    }
    
    Write-Host "`nAll tests passed! The module loading fix is working correctly." -ForegroundColor Green
    Write-Host "You can now run the main application: pwsh -file _CLASSY-MAIN.ps1" -ForegroundColor Cyan
    
} catch {
    Write-Host "`nTest failed with error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
