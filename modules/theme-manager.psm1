#
# FILE: modules/theme-manager.psm1
# PURPOSE: Provides theming and color management for the TUI.
# AI: This module has been refactored to wrap all public functions in Invoke-WithErrorHandling
#     for consistent, robust error logging and handling, adhering to the project's core principles.
#

$script:CurrentTheme = $null
$script:Themes = @{
    Modern = @{
        Name = "Modern"
        Colors = @{
            Background = [ConsoleColor]::Black; Foreground = [ConsoleColor]::White
            Primary = [ConsoleColor]::White; Secondary = [ConsoleColor]::Gray
            Accent = [ConsoleColor]::Cyan; Success = [ConsoleColor]::Green
            Warning = [ConsoleColor]::Yellow; Error = [ConsoleColor]::Red
            Info = [ConsoleColor]::Blue; Header = [ConsoleColor]::Cyan
            Border = [ConsoleColor]::DarkGray; Selection = [ConsoleColor]::Yellow
            Highlight = [ConsoleColor]::Cyan; Subtle = [ConsoleColor]::DarkGray
            Keyword = [ConsoleColor]::Blue; String = [ConsoleColor]::Green
            Number = [ConsoleColor]::Magenta; Comment = [ConsoleColor]::DarkGray
        }
    }
    Dark = @{
        Name = "Dark"
        Colors = @{
            Background = [ConsoleColor]::Black; Foreground = [ConsoleColor]::Gray
            Primary = [ConsoleColor]::Gray; Secondary = [ConsoleColor]::DarkGray
            Accent = [ConsoleColor]::DarkCyan; Success = [ConsoleColor]::DarkGreen
            Warning = [ConsoleColor]::DarkYellow; Error = [ConsoleColor]::DarkRed
            Info = [ConsoleColor]::DarkBlue; Header = [ConsoleColor]::DarkCyan
            Border = [ConsoleColor]::DarkGray; Selection = [ConsoleColor]::Yellow
            Highlight = [ConsoleColor]::Cyan; Subtle = [ConsoleColor]::DarkGray
            Keyword = [ConsoleColor]::DarkBlue; String = [ConsoleColor]::DarkGreen
            Number = [ConsoleColor]::DarkMagenta; Comment = [ConsoleColor]::DarkGray
        }
    }
    Light = @{
        Name = "Light"
        Colors = @{
            Background = [ConsoleColor]::White; Foreground = [ConsoleColor]::Black
            Primary = [ConsoleColor]::Black; Secondary = [ConsoleColor]::DarkGray
            Accent = [ConsoleColor]::Blue; Success = [ConsoleColor]::Green
            Warning = [ConsoleColor]::DarkYellow; Error = [ConsoleColor]::Red
            Info = [ConsoleColor]::Blue; Header = [ConsoleColor]::Blue
            Border = [ConsoleColor]::Gray; Selection = [ConsoleColor]::Cyan
            Highlight = [ConsoleColor]::Yellow; Subtle = [ConsoleColor]::Gray
            Keyword = [ConsoleColor]::Blue; String = [ConsoleColor]::Green
            Number = [ConsoleColor]::Magenta; Comment = [ConsoleColor]::Gray
        }
    }
    Retro = @{
        Name = "Retro"
        Colors = @{
            Background = [ConsoleColor]::Black; Foreground = [ConsoleColor]::Green
            Primary = [ConsoleColor]::Green; Secondary = [ConsoleColor]::DarkGreen
            Accent = [ConsoleColor]::Yellow; Success = [ConsoleColor]::Green
            Warning = [ConsoleColor]::Yellow; Error = [ConsoleColor]::Red
            Info = [ConsoleColor]::Cyan; Header = [ConsoleColor]::Yellow
            Border = [ConsoleColor]::DarkGreen; Selection = [ConsoleColor]::Yellow
            Highlight = [ConsoleColor]::White; Subtle = [ConsoleColor]::DarkGreen
            Keyword = [ConsoleColor]::Yellow; String = [ConsoleColor]::Cyan
            Number = [ConsoleColor]::White; Comment = [ConsoleColor]::DarkGreen
        }
    }
}

function global:Initialize-ThemeManager {
    <#
    .SYNOPSIS
    Initializes the theme manager.
    #>
    Invoke-WithErrorHandling -Component "ThemeManager.Initialize" -Context "Initializing the theme service" -ScriptBlock {
        Set-TuiTheme -ThemeName "Modern"
        Write-Log -Level Info -Message "Theme manager initialized."
    }
}

function global:Set-TuiTheme {
    <#
    .SYNOPSIS
    Sets the current theme for the application.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ThemeName
    )
    Invoke-WithErrorHandling -Component "ThemeManager.SetTheme" -Context "Setting active TUI theme" -AdditionalData @{ ThemeName = $ThemeName } -ScriptBlock {
        if ($script:Themes.ContainsKey($ThemeName)) {
            $script:CurrentTheme = $script:Themes[$ThemeName]
            
            # Defensively check if RawUI exists. In some environments (like the VS Code
            # Integrated Console), it can be $null and cause a crash.
            if ($Host.UI.RawUI) {
                $Host.UI.RawUI.BackgroundColor = $script:CurrentTheme.Colors.Background
                $Host.UI.RawUI.ForegroundColor = $script:CurrentTheme.Colors.Foreground
            }
            
            Write-Log -Level Debug -Message "Theme set to: $ThemeName"
            
            # Publish theme change event if the event system is available.
            if (Get-Command -Name Publish-Event -ErrorAction SilentlyContinue) {
                Publish-Event -EventName "Theme.Changed" -Data @{ ThemeName = $ThemeName; Theme = $script:CurrentTheme }
            }
        } else {
            Write-Log -Level Warning -Message "Theme not found: $ThemeName"
        }
    }
}

function global:Get-ThemeColor {
    <#
    .SYNOPSIS
    Gets a color from the current theme.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ColorName,
        [Parameter()]
        [ConsoleColor]$Default = [ConsoleColor]::Gray
    )
    # AI: This function is called frequently during render. The wrapper adds negligible overhead
    #     but ensures any unexpected state corruption is handled gracefully.
    try {
        if ($script:CurrentTheme -and $script:CurrentTheme.Colors.ContainsKey($ColorName)) {
            return $script:CurrentTheme.Colors[$ColorName]
        }
        return $Default
    } catch {
        # Failsafe for render-critical function.
        Write-Log -Level Warning -Message "Error in Get-ThemeColor for '$ColorName'. Returning default. Error: $_"
        return $Default
    }
}

function global:Get-TuiTheme {
    <#
    .SYNOPSIS
    Gets the current theme object.
    #>
    Invoke-WithErrorHandling -Component "ThemeManager.GetTheme" -Context "Retrieving the current theme object" -ScriptBlock {
        return $script:CurrentTheme
    }
}

function global:Get-AvailableThemes {
    <#
    .SYNOPSIS
    Gets a list of all available theme names.
    #>
    Invoke-WithErrorHandling -Component "ThemeManager.GetAvailableThemes" -Context "Retrieving all available theme names" -ScriptBlock {
        return $script:Themes.Keys | Sort-Object
    }
}

function global:New-TuiTheme {
    <#
    .SYNOPSIS
    Creates a new theme in memory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$BaseTheme = "Modern",
        [hashtable]$Colors = @{}
    )
    Invoke-WithErrorHandling -Component "ThemeManager.NewTheme" -Context "Creating a new theme" -AdditionalData @{ ThemeName = $Name } -ScriptBlock {
        $newTheme = @{ Name = $Name; Colors = @{} }
        
        if ($script:Themes.ContainsKey($BaseTheme)) {
            $newTheme.Colors = $script:Themes[$BaseTheme].Colors.Clone()
        }
        
        foreach ($colorKey in $Colors.Keys) {
            $newTheme.Colors[$colorKey] = $Colors[$colorKey]
        }
        
        $script:Themes[$Name] = $newTheme
        Write-Log -Level Info -Message "Created new theme: $Name"
        return $newTheme
    }
}

function global:Export-TuiTheme {
    <#
    .SYNOPSIS
    Exports a theme to a JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ThemeName,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Invoke-WithErrorHandling -Component "ThemeManager.ExportTheme" -Context "Exporting a theme to JSON" -AdditionalData @{ ThemeName = $ThemeName; FilePath = $Path } -ScriptBlock {
        if ($script:Themes.ContainsKey($ThemeName)) {
            $theme = $script:Themes[$ThemeName]
            $exportTheme = @{ Name = $theme.Name; Colors = @{} }
            
            foreach ($colorKey in $theme.Colors.Keys) {
                $exportTheme.Colors[$colorKey] = $theme.Colors[$colorKey].ToString()
            }
            
            $exportTheme | ConvertTo-Json -Depth 3 | Set-Content -Path $Path
            Write-Log -Level Info -Message "Exported theme '$ThemeName' to: $Path"
        } else {
            Write-Log -Level Warning -Message "Cannot export theme. Theme not found: $ThemeName"
        }
    }
}

function global:Import-TuiTheme {
    <#
    .SYNOPSIS
    Imports a theme from a JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Invoke-WithErrorHandling -Component "ThemeManager.ImportTheme" -Context "Importing a theme from JSON" -AdditionalData @{ FilePath = $Path } -ScriptBlock {
        if (Test-Path $Path) {
            $importedTheme = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
            $theme = @{ Name = $importedTheme.Name; Colors = @{} }
            
            foreach ($colorKey in $importedTheme.Colors.Keys) {
                $theme.Colors[$colorKey] = [System.Enum]::Parse([System.ConsoleColor], $importedTheme.Colors[$colorKey], $true)
            }
            
            $script:Themes[$theme.Name] = $theme
            Write-Log -Level Info -Message "Imported theme: $($theme.Name)"
            return $theme
        } else {
            Write-Log -Level Warning -Message "Cannot import theme. File not found: $Path"
            return $null
        }
    }
}

Export-ModuleMember -Function @(
    'Initialize-ThemeManager',
    'Set-TuiTheme',
    'Get-ThemeColor',
    'Get-TuiTheme',
    'Get-AvailableThemes',
    'New-TuiTheme',
    'Export-TuiTheme',
    'Import-TuiTheme'
)