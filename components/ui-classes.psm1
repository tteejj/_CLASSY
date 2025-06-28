# ==============================================================================
# PMC Terminal v5 - Base UI Class Hierarchy
# Provides the foundational classes for all UI components, incorporating the
# stable and safe IRenderable pattern directly into the base element.
# ==============================================================================

using namespace System.Text

# AI: FIX - Removed internal Import-Module statement. Dependencies managed by _CLASSY-MAIN.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Base UI Element (with integrated safe rendering) ---
class UIElement {
    [string]$Name
    [bool]$Visible = $true
    [bool]$Enabled = $true
    
    UIElement([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new("UIElement name cannot be null or empty.")
        }
        $this.Name = $name
    }

    # Public, safe render method. Derived classes should NOT override this.
    [string] Render() {
        return Invoke-WithErrorHandling -Component $this.Name -Context "Render" -ScriptBlock {
            if (-not $this.Visible) { return "" }
            
            # Call the internal, abstract render method that derived classes MUST implement.
            return $this._RenderContent()
        } -AdditionalData @{ ComponentType = $this.GetType().Name }
    }

    # Abstract method - must be implemented by derived classes.
    hidden [string] _RenderContent() {
        throw [System.NotImplementedException]::new("Component '$($this.Name)' of type '$($this.GetType().Name)' must implement the _RenderContent() method.")
    }
    
    [string] ToString() {
        return "$($this.GetType().Name): $($this.Name)"
    }
}

# --- Base Component (can contain children) ---
class Component : UIElement {
    [object]$Parent
    [System.Collections.Generic.List[UIElement]]$Children

    Component([string]$name) : base($name) {
        $this.Children = [System.Collections.Generic.List[UIElement]]::new()
    }

    [void] AddChild([UIElement]$child) {
        if (-not $child) { throw [System.ArgumentNullException]::new("child") }
        if ($child -eq $this) { throw [System.InvalidOperationException]::new("A component cannot be its own child.") }
        
        $child.Parent = $this
        $this.Children.Add($child)
    }
}

# --- Base Panel (rectangular area) ---
class Panel : Component {
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height
    [string]$Title = ""
    [bool]$ShowBorder = $true

    Panel([string]$name, [int]$x, [int]$y, [int]$width, [int]$height) : base($name) {
        if ($width -le 0 -or $height -le 0) { throw [System.ArgumentOutOfRangeException]::new("Panel dimensions must be positive.") }
        
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
    }

    [hashtable] GetContentArea() {
        $borderOffset = if ($this.ShowBorder) { 1 } else { 0 }
        return @{
            X      = $this.X + $borderOffset
            Y      = $this.Y + $borderOffset
            Width  = $this.Width - (2 * $borderOffset)
            Height = $this.Height - (2 * $borderOffset)
        }
    }
}

# --- Base Screen (top-level container) ---
class Screen : UIElement {
    [hashtable]$Services
    [System.Collections.Generic.Dictionary[string, object]]$State
    [System.Collections.Generic.List[Panel]]$Panels
    hidden [System.Collections.Generic.Dictionary[string, string]]$EventSubscriptions

    Screen([string]$name, [hashtable]$services) : base($name) {
        if (-not $services) { throw [System.ArgumentNullException]::new("services") }
        
        $this.Services = $services
        $this.State = [System.Collections.Generic.Dictionary[string, object]]::new()
        $this.Panels = [System.Collections.Generic.List[Panel]]::new()
        $this.EventSubscriptions = [System.Collections.Generic.Dictionary[string, string]]::new()
    }
    
    # Virtual lifecycle methods for derived screens to override.
    [void] Initialize() { }
    [void] OnEnter() { }
    [void] OnExit() { }
    [void] OnResume() { }
    [void] HandleInput([System.ConsoleKeyInfo]$key) { }

    [void] Cleanup() {
        # Unsubscribe from all events to prevent memory leaks
        foreach ($kvp in $this.EventSubscriptions.GetEnumerator()) {
            try {
                Unsubscribe-Event -EventName $kvp.Key -SubscriberId $kvp.Value
            }
            catch {
                Write-Log -Level Warning -Message "Failed to unregister event '$($kvp.Key)' for screen '$($this.Name)'."
            }
        }
        $this.EventSubscriptions.Clear()
        $this.Panels.Clear()
        Write-Log -Level Debug -Message "Cleaned up screen: $($this.Name)"
    }
    
    [void] AddPanel([Panel]$panel) {
        if (-not $panel) { throw [System.ArgumentNullException]::new("panel") }
        $this.Panels.Add($panel)
    }

    [void] SubscribeToEvent([string]$eventName, [scriptblock]$action) {
        if ([string]::IsNullOrWhiteSpace($eventName)) { throw [System.ArgumentException]::new("Event name cannot be null or empty.") }
        if (-not $action) { throw [System.ArgumentNullException]::new("action") }
        
        $subscriptionId = Subscribe-Event -EventName $eventName -Action $action
        $this.EventSubscriptions[$eventName] = $subscriptionId
    }
}

# AI: FIX - Removed -Class parameter for PowerShell 5.1 compatibility
# Classes are automatically exported in PowerShell 5.1 when defined in a module