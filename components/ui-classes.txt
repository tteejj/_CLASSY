# ==============================================================================
# PMC Terminal v5 - Base UI Class Hierarchy
# Provides the foundational classes for all UI components.
# ==============================================================================

using namespace System.Text
using namespace System.Management.Automation

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Base UI Element (with integrated safe rendering) ---
class UIElement {
    [string]$Name
    [bool]$Visible = $true
    [bool]$Enabled = $true
    
    UIElement([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("UIElement name cannot be null or empty.")
        }
        $this.Name = $name
    }

    [string] Render() {
        return Invoke-WithErrorHandling -Component $this.Name -Context "Render" -ScriptBlock {
            if (-not $this.Visible) { return "" }
            return $this._RenderContent()
        } -AdditionalData @{ ComponentType = $this.GetType().Name }
    }

    hidden [string] _RenderContent() {
        throw [NotImplementedException]::new("Component '$($this.Name)' of type '$($this.GetType().Name)' must implement the _RenderContent() method.")
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
        if (-not $child) { throw [ArgumentNullException]::new("child") }
        if ($child -eq $this) { throw [InvalidOperationException]::new("A component cannot be its own child.") }
        
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
        if ($width -le 0 -or $height -le 0) { throw [ArgumentOutOfRangeException]::new("Panel dimensions must be positive.") }
        
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
    }

    [hashtable] GetContentArea() {
        $borderOffset = $this.ShowBorder ? 1 : 0
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
        if (-not $services) { throw [ArgumentNullException]::new("services") }
        
        $this.Services = $services
        $this.State = [System.Collections.Generic.Dictionary[string, object]]::new()
        $this.Panels = [System.Collections.Generic.List[Panel]]::new()
        $this.EventSubscriptions = [System.Collections.Generic.Dictionary[string, string]]::new()
    }
    
    [void] Initialize() { }
    [void] OnEnter() { }
    [void] OnExit() { }
    [void] OnResume() { }
    [void] HandleInput([System.ConsoleKeyInfo]$key) { }

    [void] Cleanup() {
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
        if (-not $panel) { throw [ArgumentNullException]::new("panel") }
        $this.Panels.Add($panel)
    }

    [void] SubscribeToEvent([string]$eventName, [scriptblock]$action) {
        if ([string]::IsNullOrWhiteSpace($eventName)) { throw [ArgumentException]::new("Event name cannot be null or empty.") }
        if (-not $action) { throw [ArgumentNullException]::new("action") }
        
        $subscriptionId = Subscribe-Event -EventName $eventName -Action $action
        $this.EventSubscriptions[$eventName] = $subscriptionId
    }
}