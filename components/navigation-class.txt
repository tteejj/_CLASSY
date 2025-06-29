# Navigation Component Classes Module for PMC Terminal v5
# Implements navigation menu functionality with keyboard shortcuts

using namespace System.Management.Automation
using module ..\components\ui-classes.psm1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        if ([string]::IsNullOrWhiteSpace($key))   { throw [ArgumentException]::new("Navigation key cannot be null or empty") }
        if ([string]::IsNullOrWhiteSpace($label)) { throw [ArgumentException]::new("Navigation label cannot be null or empty") }
        if ($null -eq $action)                    { throw [ArgumentNullException]::new("action", "Navigation action cannot be null") }
        
        $this.Key = $key.ToUpper()
        $this.Label = $label
        $this.Action = $action
    }
    
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
    
    [string] FormatDisplay([bool]$showDescription = $false) {
        $display = [System.Text.StringBuilder]::new()
        
        [void]$display.Append($this.SetColor($this.KeyColor)).Append("[$($this.Key)]").Append($this.ResetColor()).Append(" ")
        
        if ($this.Enabled) {
            [void]$display.Append($this.SetColor($this.LabelColor)).Append($this.Label)
        }
        else {
            [void]$display.Append($this.SetColor([ConsoleColor]::DarkGray)).Append($this.Label).Append(" (Disabled)")
        }
        [void]$display.Append($this.ResetColor())
        
        if ($showDescription -and -not [string]::IsNullOrWhiteSpace($this.Description)) {
            [void]$display.Append(" - ").Append($this.SetColor([ConsoleColor]::Gray)).Append($this.Description).Append($this.ResetColor())
        }
        
        return $display.ToString()
    }
    
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{ Black=30;DarkRed=31;DarkGreen=32;DarkYellow=33;DarkBlue=34;DarkMagenta=35;DarkCyan=36;Gray=37;DarkGray=90;Red=91;Green=92;Yellow=93;Blue=94;Magenta=95;Cyan=96;White=97 }
        return "`e[$($colorMap[$color.ToString()])m"
    }
    
    hidden [string] ResetColor() { return "`e[0m" }
}

# NavigationMenu - Component for displaying and handling navigation options
class NavigationMenu : Component {
    [System.Collections.Generic.List[NavigationItem]] $Items
    [hashtable] $Services
    [string] $Orientation = "Vertical"
    [string] $Separator = "  |  "
    [bool] $ShowDescriptions = $false
    [ConsoleColor] $SeparatorColor = [ConsoleColor]::DarkGray
    [int] $SelectedIndex = 0
    
    NavigationMenu([string]$name) : base($name) {
        $this.Items = [System.Collections.Generic.List[NavigationItem]]::new()
    }
    
    NavigationMenu([string]$name, [hashtable]$services) : base($name) {
        if ($null -eq $services) { throw [ArgumentNullException]::new("services") }
        $this.Services = $services
        $this.Items = [System.Collections.Generic.List[NavigationItem]]::new()
    }
    
    [void] AddItem([NavigationItem]$item) {
        if (-not $item) { throw [ArgumentNullException]::new("item") }
        if ($this.Items.Exists({$_.Key -eq $item.Key})) { throw [InvalidOperationException]::new("Item with key '$($item.Key)' already exists") }
        $this.Items.Add($item)
    }
    
    [void] RemoveItem([string]$key) {
        $item = $this.GetItem($key)
        if ($item) { [void]$this.Items.Remove($item) }
    }
    
    [NavigationItem] GetItem([string]$key) {
        return $this.Items.Find({$_.Key -eq $key.ToUpper()})
    }

    [void] ExecuteAction([string]$key) {
        $item = $this.GetItem($key)
        if ($item -and $item.Visible) {
            Invoke-WithErrorHandling -Component "NavigationMenu" -Context "ExecuteAction:$key" -ScriptBlock { $item.Execute() }
        }
    }

    [void] AddSeparator() {
        $separatorItem = [NavigationItem]::new("-", "---", {})
        $separatorItem.Enabled = $false
        $this.Items.Add($separatorItem)
    }

    # AI: FIX - Corrected the syntax within the switch statement blocks.
    [void] BuildContextMenu([string]$context) {
        $this.Items.Clear()
        
        switch ($context) {
            "Dashboard" {
                $this.AddItem([NavigationItem]::new("N", "New Task", { $this.Services.Navigation.PushScreen("NewTaskScreen") }))
                $this.AddItem([NavigationItem]::new("P", "Projects", { $this.Services.Navigation.PushScreen("ProjectListScreen") }))
                $this.AddItem([NavigationItem]::new("S", "Settings", { $this.Services.Navigation.PushScreen("SettingsScreen") }))
                $this.AddSeparator()
                $this.AddItem([NavigationItem]::new("Q", "Quit", { $this.Services.AppState.RequestExit() }))
            }
            "TaskList" {
                $this.AddItem([NavigationItem]::new("N", "New", { $this.Services.Navigation.PushScreen("NewTaskScreen") }))
                $this.AddItem([NavigationItem]::new("E", "Edit", { }))
                $this.AddItem([NavigationItem]::new("D", "Delete", { }))
                $this.AddItem([NavigationItem]::new("F", "Filter", { $this.Services.Navigation.PushScreen("FilterScreen") }))
                $this.AddSeparator()
                $this.AddItem([NavigationItem]::new("B", "Back", { $this.Services.Navigation.PopScreen() }))
            }
            default {
                $this.AddItem([NavigationItem]::new("B", "Back", { $this.Services.Navigation.PopScreen() }))
                $this.AddItem([NavigationItem]::new("H", "Home", { $this.Services.Navigation.NavigateToRoot() }))
            }
        }
    }
    
    [string] Render() {
        return Invoke-WithErrorHandling -Component "NavigationMenu" -Context "Render:$($this.Name)" -ScriptBlock {
            $menuBuilder = [System.Text.StringBuilder]::new()
            $visibleItems = $this.Items | Where-Object { $_.Visible }
            if ($visibleItems.Count -eq 0) { return "" }
            
            if ($this.Orientation -eq "Horizontal") { $this.RenderHorizontal($menuBuilder, $visibleItems) }
            else { $this.RenderVertical($menuBuilder, $visibleItems) }
            
            return $menuBuilder.ToString()
        }
    }
    
    hidden [void] RenderHorizontal([System.Text.StringBuilder]$builder, [object[]]$items) {
        $isFirst = $true
        foreach ($item in $items) {
            if (-not $isFirst) {
                [void]$builder.Append($this.SetColor($this.SeparatorColor)).Append($this.Separator).Append($this.ResetColor())
            }
            [void]$builder.Append($item.FormatDisplay($this.ShowDescriptions))
            $isFirst = $false
        }
    }
    
    hidden [void] RenderVertical([System.Text.StringBuilder]$builder, [object[]]$items) {
        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            if ($i -eq $this.SelectedIndex -and $item.Key -ne "-") {
                [void]$builder.Append($this.SetColor([ConsoleColor]::Black)).Append($this.SetBackgroundColor([ConsoleColor]::White))
                [void]$builder.Append(" > ").Append($item.FormatDisplay($this.ShowDescriptions)).Append(" ").Append($this.ResetColor())
            } else {
                [void]$builder.Append("   ").Append($item.FormatDisplay($this.ShowDescriptions))
            }
            [void]$builder.AppendLine()
        }
    }
    
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{ Black=30;DarkRed=31;DarkGreen=32;DarkYellow=33;DarkBlue=34;DarkMagenta=35;DarkCyan=36;Gray=37;DarkGray=90;Red=91;Green=92;Yellow=93;Blue=94;Magenta=95;Cyan=96;White=97 }
        return "`e[$($colorMap[$color.ToString()])m"
    }
    
    hidden [string] SetBackgroundColor([ConsoleColor]$color) {
        $colorMap = @{ Black=40;DarkRed=41;DarkGreen=42;DarkYellow=43;DarkBlue=44;DarkMagenta=45;DarkCyan=46;Gray=47;White=107 }
        return "`e[$($colorMap[$color.ToString()])m"
    }
    
    hidden [string] ResetColor() { return "`e[0m" }
}