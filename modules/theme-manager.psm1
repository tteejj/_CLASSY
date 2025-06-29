# FILE: modules/theme-manager.psm1
# PURPOSE: Provides theming and color management for the TUI.
#

$script:CurrentTheme = $null
$script:Themes = @{
    Modern = @{ Name="Modern"; Colors=@{ Background=[ConsoleColor]::Black; Foreground=[ConsoleColor]::White; Primary=[ConsoleColor]::White; Secondary=[ConsoleColor]::Gray; Accent=[ConsoleColor]::Cyan; Success=[ConsoleColor]::Green; Warning=[ConsoleColor]::Yellow; Error=[ConsoleColor]::Red; Info=[ConsoleColor]::Blue; Header=[ConsoleColor]::Cyan; Border=[ConsoleColor]::DarkGray; Selection=[ConsoleColor]::Yellow; Highlight=[ConsoleColor]::Cyan; Subtle=[ConsoleColor]::DarkGray; Keyword=[ConsoleColor]::Blue; String=[ConsoleColor]::Green; Number=[ConsoleColor]::Magenta; Comment=[ConsoleColor]::DarkGray } }
    Dark   = @{ Name="Dark"; Colors=@{ Background=[ConsoleColor]::Black; Foreground=[ConsoleColor]::Gray; Primary=[ConsoleColor]::Gray; Secondary=[ConsoleColor]::DarkGray; Accent=[ConsoleColor]::DarkCyan; Success=[ConsoleColor]::DarkGreen; Warning=[ConsoleColor]::DarkYellow; Error=[ConsoleColor]::DarkRed; Info=[ConsoleColor]::DarkBlue; Header=[ConsoleColor]::DarkCyan; Border=[ConsoleColor]::DarkGray; Selection=[ConsoleColor]::Yellow; Highlight=[ConsoleColor]::Cyan; Subtle=[ConsoleColor]::DarkGray; Keyword=[ConsoleColor]::DarkBlue; String=[ConsoleColor]::DarkGreen; Number=[ConsoleColor]::DarkMagenta; Comment=[ConsoleColor]::DarkGray } }
    Light  = @{ Name="Light"; Colors=@{ Background=[ConsoleColor]::White; Foreground=[ConsoleColor]::Black; Primary=[ConsoleColor]::Black; Secondary=[ConsoleColor]::DarkGray; Accent=[ConsoleColor]::Blue; Success=[ConsoleColor]::Green; Warning=[ConsoleColor]::DarkYellow; Error=[ConsoleColor]::Red; Info=[ConsoleColor]::Blue; Header=[ConsoleColor]::Blue; Border=[ConsoleColor]::Gray; Selection=[ConsoleColor]::Cyan; Highlight=[ConsoleColor]::Yellow; Subtle=[ConsoleColor]::Gray; Keyword=[ConsoleColor]::Blue; String=[ConsoleColor]::Green; Number=[ConsoleColor]::Magenta; Comment=[ConsoleColor]::Gray } }
    Retro  = @{ Name="Retro"; Colors=@{ Background=[ConsoleColor]::Black; Foreground=[ConsoleColor]::Green; Primary=[ConsoleColor]::Green; Secondary=[ConsoleColor]::DarkGreen; Accent=[ConsoleColor]::Yellow; Success=[ConsoleColor]::Green; Warning=[ConsoleColor]::Yellow; Error=[ConsoleColor]::Red; Info=[ConsoleColor]::Cyan; Header=[ConsoleColor]::Yellow; Border=[ConsoleColor]::DarkGreen; Selection=[ConsoleColor]::Yellow; Highlight=[ConsoleColor]::White; Subtle=[ConsoleColor]::DarkGreen; Keyword=[ConsoleColor]::Yellow; String=[ConsoleColor]::Cyan; Number=[ConsoleColor]::White; Comment=[ConsoleColor]::DarkGreen } }
}

function Initialize-ThemeManager {
    Invoke-WithErrorHandling -Component "ThemeManager.Initialize" -Context "Initializing theme service" -ScriptBlock {
        Set-TuiTheme -ThemeName "Modern"
        Write-Log -Level Info -Message "Theme manager initialized."
    }
}

function Set-TuiTheme {
    param([Parameter(Mandatory)] [string]$ThemeName)
    Invoke-WithErrorHandling -Component "ThemeManager.SetTheme" -Context "Setting active TUI theme" -AdditionalData @{ ThemeName = $ThemeName } -ScriptBlock {
        if ($script:Themes.ContainsKey($ThemeName)) {
            $script:CurrentTheme = $script:Themes[$ThemeName]
            if ($Host.UI.RawUI) {
                $Host.UI.RawUI.BackgroundColor = $script:CurrentTheme.Colors.Background
                $Host.UI.RawUI.ForegroundColor = $script:CurrentTheme.Colors.Foreground
            }
            Write-Log -Level Debug -Message "Theme set to: $ThemeName"
            Publish-Event -EventName "Theme.Changed" -Data @{ ThemeName = $ThemeName; Theme = $script:CurrentTheme }
        } else {
            Write-Log -Level Warning -Message "Theme not found: $ThemeName"
        }
    }
}

function Get-ThemeColor {
    param([Parameter(Mandatory)] [string]$ColorName, [ConsoleColor]$Default = [ConsoleColor]::Gray)
    try {
        return $script:CurrentTheme.Colors[$ColorName] ?? $Default
    } catch {
        Write-Log -Level Warning -Message "Error in Get-ThemeColor for '$ColorName'. Returning default. Error: $_"
        return $Default
    }
}

function Get-TuiTheme {
    Invoke-WithErrorHandling -Component "ThemeManager.GetTheme" -Context "Retrieving current theme" -ScriptBlock {
        return $script:CurrentTheme
    }
}

function Get-AvailableThemes {
    Invoke-WithErrorHandling -Component "ThemeManager.GetAvailableThemes" -Context "Retrieving available themes" -ScriptBlock {
        return $script:Themes.Keys | Sort-Object
    }
}

function New-TuiTheme {
    param([Parameter(Mandatory)] [string]$Name, [string]$BaseTheme = "Modern", [hashtable]$Colors = @{})
    Invoke-WithErrorHandling -Component "ThemeManager.NewTheme" -Context "Creating new theme" -AdditionalData @{ ThemeName = $Name } -ScriptBlock {
        $newTheme = @{ Name = $Name; Colors = @{} }
        if ($script:Themes.ContainsKey($BaseTheme)) { $newTheme.Colors = $script:Themes[$BaseTheme].Colors.Clone() }
        foreach ($colorKey in $Colors.Keys) { $newTheme.Colors[$colorKey] = $Colors[$colorKey] }
        $script:Themes[$Name] = $newTheme
        Write-Log -Level Info -Message "Created new theme: $Name"
        return $newTheme
    }
}

function Export-TuiTheme {
    param([Parameter(Mandatory)] [string]$ThemeName, [Parameter(Mandatory)] [string]$Path)
    Invoke-WithErrorHandling -Component "ThemeManager.ExportTheme" -Context "Exporting theme to JSON" -AdditionalData @{ ThemeName = $ThemeName; FilePath = $Path } -ScriptBlock {
        if ($script:Themes.ContainsKey($ThemeName)) {
            $theme = $script:Themes[$ThemeName]
            $exportTheme = @{ Name = $theme.Name; Colors = @{} }
            foreach ($colorKey in $theme.Colors.Keys) { $exportTheme.Colors[$colorKey] = $theme.Colors[$colorKey].ToString() }
            $exportTheme | ConvertTo-Json -Depth 3 | Set-Content -Path $Path
            Write-Log -Level Info -Message "Exported theme '$ThemeName' to: $Path"
        } else {
            Write-Log -Level Warning -Message "Cannot export theme. Theme not found: $ThemeName"
        }
    }
}

function Import-TuiTheme {
    param([Parameter(Mandatory)] [string]$Path)
    Invoke-WithErrorHandling -Component "ThemeManager.ImportTheme" -Context "Importing theme from JSON" -AdditionalData @{ FilePath = $Path } -ScriptBlock {
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

Export-ModuleMember -Function 'Initialize-ThemeManager', 'Set-TuiTheme', 'Get-ThemeColor', 'Get-TuiTheme', 'Get-AvailableThemes', 'New-TuiTheme', 'Export-TuiTheme', 'Import-TuiTheme'