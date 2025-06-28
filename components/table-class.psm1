# ==============================================================================
# PMC Terminal v5 - Class-Based Navigation Menu Component
# Provides a reusable menu component driven by keyboard shortcuts.
# ==============================================================================

# Import base classes this module extends
using module '.\ui-classes.psm1'

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import utilities
Import-Module -Name "$PSScriptRoot\..\utilities\error-handling.psm1" -Force

# --- NavigationItem Class ---
# Represents a single, executable item within a NavigationMenu.
class NavigationItem {
    [string]$Key
    [string]$Label
    [scriptblock]$Action
    [bool]$Enabled = $true
    
    NavigationItem([string]$key, [string]$label, [scriptblock]$action) {
        if ([string]::IsNullOrWhiteSpace($key)) { throw [System.ArgumentException]::new("key") }
        if ([string]::IsNullOrWhiteSpace($label)) { throw [System.ArgumentException]::new("label") }
        if (-not $action) { throw [System.ArgumentNullException]::new("action") }
        
        $this.Key = $key.ToUpper()
        $this.Label = $label
        $this.Action = $action
    }

    [void] Execute() {
        if (-not $this.Enabled) { return }
        Invoke-WithErrorHandling -Component "NavigationItem" -Context "Execute:$($this.Key)" -ScriptBlock {
            & $this.Action
        }
    }
}

# --- NavigationMenu Class ---
# A component that renders a list of NavigationItems and executes their actions.
class NavigationMenu : Component {
    [System.Collections.Generic.List[NavigationItem]]$Items
    [string]$Orientation = "Horizontal" # 'Horizontal' or 'Vertical'
    [string]$Separator = " | "

    NavigationMenu([string]$name) : base($name) {
        $this.Items = [System.Collections.Generic.List[NavigationItem]]::new()
    }

    [void] AddItem([NavigationItem]$item) {
        if (-not $item) { throw [System.ArgumentNullException]::new("item") }
        $this.Items.Add($item)
    }

    [void] ExecuteActionByKey([string]$key) {
        $item = $this.Items.Find({ param($i) $i.Key -eq $key.ToUpper() })
        if ($item) { $item.Execute() }
    }

    # AI: Implements the abstract _RenderContent from UIElement.
    hidden [string] _RenderContent() {
        $sb = [System.Text.StringBuilder]::new()
        $visibleItems = $this.Items | Where-Object { $_.Visible -ne $false }

        if ($this.Orientation -eq "Horizontal") {
            $line = $visibleItems.ForEach({
                $text = if ($_.Enabled) { "[$($_.Key)]$($_.Label)" } else { "(dim)[$($_.Key)]$($_.Label)(/dim)" }
                $text
            }) -join $this.Separator
            [void]$sb.Append($line)
        } else {
            foreach ($item in $visibleItems) {
                $text = if ($item.Enabled) { "[$($item.Key)] $($item.Label)" } else { "(dim)[$($item.Key)] $($item.Label)(/dim)" }
                [void]$sb.AppendLine($text)
            }
        }
        return $sb.ToString()
    }
}