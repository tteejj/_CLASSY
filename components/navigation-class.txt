# Navigation Component Classes Module for PMC Terminal v5
# Implements navigation menu functionality with keyboard shortcuts
# AI: Implements Phase 2.2 of the class migration plan - Navigation Component

# Import base classes
using module '.\ui-classes.psm1'

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"



# Import utilities for error handling
Import-Module -Name "$PSScriptRoot\..\utilities\error-handling.psm1" -Force

# NavigationItem - Represents a single menu item
class NavigationItem {
    [string] $Key
    [string] $Label
    [scriptblock] $Action
    [bool] $Enabled = $true
    [bool] $Visible = $true
    [string] $Description = ""
    [ConsoleColor] $KeyColor = [ConsoleColor]::Yellow
    [ConsoleColor] $LabelColor = [ConsoleColor]::White
    
    NavigationItem([string]$key, [string]$label, [scriptblock]$action) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw [System.ArgumentException]::new("Navigation key cannot be null or empty")
        }
        if ([string]::IsNullOrWhiteSpace($label)) {
            throw [System.ArgumentException]::new("Navigation label cannot be null or empty")
        }
        if ($null -eq $action) {
            throw [System.ArgumentNullException]::new("action", "Navigation action cannot be null")
        }
        
        $this.Key = $key.ToUpper()
        $this.Label = $label
        $this.Action = $action
    }
    
    # AI: Execute the action with error handling
    [void] Execute() {
        if (-not $this.Enabled) {
            Write-Log -Level Warning -Message "Attempted to execute disabled navigation item: $($this.Key)" -Component "NavigationItem"
            return
        }
        
        try {
            Write-Log -Level Debug -Message "Executing navigation item: $($this.Key) - $($this.Label)" -Component "NavigationItem"
            & $this.Action
        }
        catch {
            Write-Log -Level Error -Message "Navigation action failed for item '$($this.Key)': $_" -Component "NavigationItem"
            throw
        }
    }
    
    # AI: Format the menu item for display
    [string] FormatDisplay([bool]$showDescription = $false) {
        $display = [System.Text.StringBuilder]::new()
        
        # Key with brackets
        [void]$display.Append($this.SetColor($this.KeyColor))
        [void]$display.Append("[$($this.Key)]")
        [void]$display.Append($this.ResetColor())
        
        # Label
        [void]$display.Append(" ")
        
        if ($this.Enabled) {
            [void]$display.Append($this.SetColor($this.LabelColor))
            [void]$display.Append($this.Label)
        }
        else {
            [void]$display.Append($this.SetColor([ConsoleColor]::DarkGray))
            [void]$display.Append($this.Label)
            [void]$display.Append(" (Disabled)")
        }
        
        [void]$display.Append($this.ResetColor())
        
        # Description if requested
        if ($showDescription -and -not [string]::IsNullOrWhiteSpace($this.Description)) {
            [void]$display.Append(" - ")
            [void]$display.Append($this.SetColor([ConsoleColor]::Gray))
            [void]$display.Append($this.Description)
            [void]$display.Append($this.ResetColor())
        }
        
        return $display.ToString()
    }
    
    # AI: Helper methods for ANSI colors
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{
            'Black' = 30; 'DarkRed' = 31; 'DarkGreen' = 32; 'DarkYellow' = 33
            'DarkBlue' = 34; 'DarkMagenta' = 35; 'DarkCyan' = 36; 'Gray' = 37
            'DarkGray' = 90; 'Red' = 91; 'Green' = 92; 'Yellow' = 93
            'Blue' = 94; 'Magenta' = 95; 'Cyan' = 96; 'White' = 97
        }
        $colorCode = $colorMap[$color.ToString()]
        return "`e[${colorCode}m"
    }
    
    hidden [string] ResetColor() {
        return "`e[0m"
    }
}

# NavigationMenu - Component for displaying and handling navigation options
class NavigationMenu : Component {
    [System.Collections.Generic.List[NavigationItem]] $Items
    [hashtable] $Services
    [string] $Orientation = "Horizontal" # Horizontal or Vertical
    [string] $Separator = "  |  "
    [bool] $ShowDescriptions = $false
    [ConsoleColor] $SeparatorColor = [ConsoleColor]::DarkGray
    
    NavigationMenu([string]$name, [hashtable]$services) : base($name) {
        if ($null -eq $services) {
            throw [System.ArgumentNullException]::new("services", "Services cannot be null")
        }
        
        $this.Services = $services
        $this.Items = [System.Collections.Generic.List[NavigationItem]]::new()
    }
    
    [void] AddItem([NavigationItem]$item) {
        if ($null -eq $item) {
            throw [System.ArgumentNullException]::new("item", "NavigationItem cannot be null")
        }
        
        # AI: Check for duplicate keys
        $existingItem = $this.Items | Where-Object { $_.Key -eq $item.Key } | Select-Object -First 1
        if ($null -ne $existingItem) {
            throw [System.InvalidOperationException]::new("Navigation item with key '$($item.Key)' already exists")
        }
        
        $this.Items.Add($item)
    }
    
    [void] RemoveItem([string]$key) {
        $item = $this.Items | Where-Object { $_.Key -eq $key.ToUpper() } | Select-Object -First 1
        if ($null -ne $item) {
            [void]$this.Items.Remove($item)
        }
    }
    
    [void] EnableItem([string]$key, [bool]$enabled = $true) {
        $item = $this.GetItem($key)
        if ($null -ne $item) {
            $item.Enabled = $enabled
        }
    }
    
    [void] ShowItem([string]$key, [bool]$visible = $true) {
        $item = $this.GetItem($key)
        if ($null -ne $item) {
            $item.Visible = $visible
        }
    }
    
    [NavigationItem] GetItem([string]$key) {
        return $this.Items | Where-Object { $_.Key -eq $key.ToUpper() } | Select-Object -First 1
    }
    
    [void] ExecuteAction([string]$key) {
        $item = $this.GetItem($key)
        
        if ($null -eq $item) {
            Write-Log -Level Debug -Message "Navigation key '$key' not found" -Component "NavigationMenu"
            return
        }
        
        if (-not $item.Visible) {
            Write-Log -Level Debug -Message "Navigation item '$key' is not visible" -Component "NavigationMenu"
            return
        }
        
        Invoke-WithErrorHandling -Component "NavigationMenu" -Context "ExecuteAction:$key" -ScriptBlock {
            $item.Execute()
        }
    }
    
    [void] AddSeparator() {
        # AI: Add a special separator item
        $separatorItem = [NavigationItem]::new("-", "---", {})
        $separatorItem.Visible = $true
        $separatorItem.Enabled = $false
        $this.Items.Add($separatorItem)
    }
    
    # AI: Build navigation menu with context-aware items
    [void] BuildContextMenu([string]$context) {
        $this.Items.Clear()
        
        switch ($context) {
            "Dashboard" {
                $this.AddItem([NavigationItem]::new("N", "New Task", {
                    $this.Services.Navigation.PushScreen("NewTaskScreen")
                }))
                
                $this.AddItem([NavigationItem]::new("P", "Projects", {
                    $this.Services.Navigation.PushScreen("ProjectListScreen")
                }))
                
                $this.AddItem([NavigationItem]::new("S", "Settings", {
                    $this.Services.Navigation.PushScreen("SettingsScreen")
                }))
                
                $this.AddSeparator()
                
                $this.AddItem([NavigationItem]::new("Q", "Quit", {
                    $this.Services.AppState.RequestExit()
                }))
            }
            
            "TaskList" {
                $this.AddItem([NavigationItem]::new("N", "New", {
                    $this.Services.Navigation.PushScreen("NewTaskScreen")
                }))
                
                $this.AddItem([NavigationItem]::new("E", "Edit", {
                    # Context-specific logic would go here
                }))
                
                $this.AddItem([NavigationItem]::new("D", "Delete", {
                    # Context-specific logic would go here
                }))
                
                $this.AddItem([NavigationItem]::new("F", "Filter", {
                    $this.Services.Navigation.PushScreen("FilterScreen")
                }))
                
                $this.AddSeparator()
                
                $this.AddItem([NavigationItem]::new("B", "Back", {
                    $this.Services.Navigation.PopScreen()
                }))
            }
            
            default {
                # Default navigation for unknown contexts
                $this.AddItem([NavigationItem]::new("B", "Back", {
                    $this.Services.Navigation.PopScreen()
                }))
                
                $this.AddItem([NavigationItem]::new("H", "Home", {
                    $this.Services.Navigation.NavigateToRoot()
                }))
            }
        }
    }
    
    [string] Render() {
        return Invoke-WithErrorHandling -Component "NavigationMenu" -Context "Render:$($this.Name)" -ScriptBlock {
            $menuBuilder = [System.Text.StringBuilder]::new()
            
            $visibleItems = $this.Items | Where-Object { $_.Visible }
            
            if ($visibleItems.Count -eq 0) {
                return ""
            }
            
            if ($this.Orientation -eq "Horizontal") {
                $this.RenderHorizontal($menuBuilder, $visibleItems)
            }
            else {
                $this.RenderVertical($menuBuilder, $visibleItems)
            }
            
            return $menuBuilder.ToString()
        }
    }
    
    hidden [void] RenderHorizontal([System.Text.StringBuilder]$builder, [object[]]$items) {
        $isFirst = $true
        
        foreach ($item in $items) {
            if (-not $isFirst) {
                [void]$builder.Append($this.SetColor($this.SeparatorColor))
                [void]$builder.Append($this.Separator)
                [void]$builder.Append($this.ResetColor())
            }
            
            [void]$builder.Append($item.FormatDisplay($this.ShowDescriptions))
            $isFirst = $false
        }
    }
    
    hidden [void] RenderVertical([System.Text.StringBuilder]$builder, [object[]]$items) {
        foreach ($item in $items) {
            [void]$builder.AppendLine($item.FormatDisplay($this.ShowDescriptions))
        }
    }
    
    # AI: Helper methods for ANSI colors
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{
            'Black' = 30; 'DarkRed' = 31; 'DarkGreen' = 32; 'DarkYellow' = 33
            'DarkBlue' = 34; 'DarkMagenta' = 35; 'DarkCyan' = 36; 'Gray' = 37
            'DarkGray' = 90; 'Red' = 91; 'Green' = 92; 'Yellow' = 93
            'Blue' = 94; 'Magenta' = 95; 'Cyan' = 96; 'White' = 97
        }
        $colorCode = $colorMap[$color.ToString()]
        return "`e[${colorCode}m"
    }
    
    hidden [string] ResetColor() {
        return "`e[0m"
    }
}

# Export all classes
Export-ModuleMember -Function * -Cmdlet * -Variable * -Alias *