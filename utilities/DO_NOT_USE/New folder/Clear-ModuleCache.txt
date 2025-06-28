# Clear PowerShell Module Cache for PMC Terminal
Write-Host "Clearing PowerShell module cache..." -ForegroundColor Yellow

# Get all loaded modules from our application
$modulesToRemove = Get-Module | Where-Object { 
    $_.Path -like "*\_CLASSY*" -or 
    $_.Name -in @('models', 'logger', 'exceptions', 'event-system', 'data-manager', 
                   'theme-manager', 'tui-framework', 'tui-engine-v2', 'dialog-system',
                   'keybinding-service', 'navigation-service-class', 'panels-class',
                   'focus-manager', 'advanced-input-components', 'advanced-data-components',
                   'ui-classes', 'panel-classes', 'table-class', 'navigation-class')
}

foreach ($module in $modulesToRemove) {
    Write-Host "Removing module: $($module.Name)" -ForegroundColor Cyan
    Remove-Module $module -Force -ErrorAction SilentlyContinue
}

# Clear any compiled assemblies (for our custom exceptions)
if ('Helios.HeliosException' -as [type]) {
    Write-Host "Note: Custom exception types are loaded and cannot be unloaded in this session." -ForegroundColor Yellow
    Write-Host "For a complete refresh, please start a new PowerShell session." -ForegroundColor Yellow
}

Write-Host "`nModule cache cleared. You can now run the application again." -ForegroundColor Green
Write-Host "Run: pwsh -file _CLASSY-MAIN.ps1" -ForegroundColor White
