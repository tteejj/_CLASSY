# Test script to verify module loading works correctly
# This script mimics the loading sequence from _CLASSY-MAIN.ps1

# Import models module classes globally (must be at top of file)
using module .\modules\models.psm1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BasePath = $PSScriptRoot

try {
    Write-Host "Testing module loading sequence..." -ForegroundColor Cyan
    
    # Step 1: Verify models were loaded
    Write-Host "1. Verifying models module loaded..." -ForegroundColor Yellow
    Write-Host "   ✓ Models module loaded via using statement" -ForegroundColor Green
    
    # Step 2: Test if classes are available
    Write-Host "2. Testing class availability..." -ForegroundColor Yellow
    $testTask = [PmcTask]::new("Test Task")
    $testProject = [PmcProject]::new("TEST", "Test Project")
    Write-Host "   ✓ Classes are available: PmcTask, PmcProject" -ForegroundColor Green
    
    # Step 3: Load core modules
    Write-Host "3. Loading core modules..." -ForegroundColor Yellow
    Import-Module "$BasePath\modules\exceptions.psm1" -Force
    Import-Module "$BasePath\modules\logger.psm1" -Force  
    Import-Module "$BasePath\modules\event-system.psm1" -Force
    Write-Host "   ✓ Core modules loaded" -ForegroundColor Green
    
    # Step 4: Load data-manager module
    Write-Host "4. Loading data-manager module..." -ForegroundColor Yellow
    Import-Module "$BasePath\modules\data-manager.psm1" -Force
    Write-Host "   ✓ Data-manager module loaded successfully!" -ForegroundColor Green
    
    # Step 5: Test DataManager class instantiation
    Write-Host "5. Testing DataManager class..." -ForegroundColor Yellow
    $dataManager = [DataManager]::new()
    Write-Host "   ✓ DataManager class instantiated successfully!" -ForegroundColor Green
    
    # Step 6: Load keybinding-service module (this was failing before)
    Write-Host "6. Loading keybinding-service module..." -ForegroundColor Yellow
    Import-Module "$BasePath\services\keybinding-service.psm1" -Force
    Write-Host "   ✓ Keybinding-service module loaded successfully!" -ForegroundColor Green
    
    # Step 7: Load navigation-service-class module
    Write-Host "7. Loading navigation-service-class module..." -ForegroundColor Yellow
    Import-Module "$BasePath\services\navigation-service-class.psm1" -Force
    Write-Host "   ✓ Navigation-service-class module loaded successfully!" -ForegroundColor Green
    
    # Step 8: Test service class instantiation
    Write-Host "8. Testing service class instantiation..." -ForegroundColor Yellow
    $keybindingService = [KeybindingService]::new()
    $testServices = @{ DataManager = $dataManager }
    $navigationService = [NavigationService]::new($testServices)
    Write-Host "   ✓ Service classes instantiated successfully!" -ForegroundColor Green
    
    Write-Host "`nAll tests passed! The module loading issues have been resolved." -ForegroundColor Green
    Write-Host "✓ Model classes load correctly" -ForegroundColor Green
    Write-Host "✓ Data-manager module loads without type errors" -ForegroundColor Green
    Write-Host "✓ Keybinding-service module loads without syntax errors" -ForegroundColor Green
    Write-Host "✓ Navigation-service-class module loads without syntax errors" -ForegroundColor Green
    Write-Host "✓ All classes can be instantiated successfully" -ForegroundColor Green
    
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
