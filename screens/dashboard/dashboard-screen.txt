# ==============================================================================
# PMC Terminal v5 - Class-Based Dashboard Screen
# Main entry screen for the application.
# ==============================================================================

# AI: CRITICAL FIX - Import models module for TaskStatus enum and other types
using module '..\..\modules\models.psm1'

# AI: FIX - Use $PSScriptRoot-based paths for better portability
using module '..\..\components\ui-classes.psm1'
using module '..\..\layout\panels-class.psm1'
using module '..\..\components\navigation-class.psm1'
using module '..\..\components\advanced-data-components.psm1'

class DashboardScreen : Screen {
    [BorderPanel] $MainPanel
    [ContentPanel] $SummaryPanel
    [NavigationMenu] $MainMenu
    [BorderPanel] $MenuPanel
    [object[]] $Tasks = @()

    DashboardScreen([hashtable]$services) : base("DashboardScreen", $services) {
        Write-Log -Level Info -Message "Creating DashboardScreen instance."
    }

    [void] Initialize() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "Initialize" -ScriptBlock {
            $this.MainPanel = [BorderPanel]::new("DashboardMain", 0, 0, 120, 30)
            $this.MainPanel.Title = "PMC Terminal v5 - Dashboard"
            $this.MainPanel.BorderStyle = "Double"
            $this.AddPanel($this.MainPanel)

            $this.SummaryPanel = [ContentPanel]::new("DashboardSummary", 2, 2, 40, 10)
            $this.MainPanel.AddChild($this.SummaryPanel)

            # AI: FIX - NavigationMenu doesn't need positioning - its parent panel handles that
            $this.MainMenu = [NavigationMenu]::new("MainMenu")
            
            $this.BuildMainMenu()
            
            # AI: FIX - Create menu panel with proper dimensions and position
            $this.MenuPanel = [BorderPanel]::new("MenuContainer", 44, 2, 50, 12)
            $this.MenuPanel.Title = "Main Menu"
            $this.MenuPanel.AddChild($this.MainMenu)
            $this.MainPanel.AddChild($this.MenuPanel)

            $this.SubscribeToEvent("Tasks.Changed", { $this.RefreshData() })
            $this.RefreshData()
            
            Write-Log -Level Info -Message "DashboardScreen initialized successfully"
        }
    }

    hidden [void] BuildMainMenu() {
        $this.MainMenu.AddItem([NavigationItem]::new("1", "Task Management", { $this.Services.Navigation.GoTo("/tasks") }))
        $this.MainMenu.AddItem([NavigationItem]::new("2", "Project Management", { $this.Services.Navigation.GoTo("/projects") }))
        $this.MainMenu.AddItem([NavigationItem]::new("3", "Settings", { $this.Services.Navigation.GoTo("/settings") }))
        $this.MainMenu.AddSeparator()
        $this.MainMenu.AddItem([NavigationItem]::new("Q", "Quit Application", { $this.Services.Navigation.RequestExit() }))
        Write-Log -Level Debug -Message "Main menu built with $($this.MainMenu.Items.Count) items"
    }

    hidden [void] RefreshData() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "RefreshData" -ScriptBlock {
            if (-not $this.Services.DataManager) { Write-Log -Level Warning -Message "DataManager service not available"; return }
            $this.Tasks = @($this.Services.DataManager.GetTasks())
            $this.UpdateSummary()
            Write-Log -Level Debug -Message "Dashboard data refreshed - $($this.Tasks.Count) tasks loaded"
        }
    }

    hidden [void] UpdateSummary() {
        if (-not $this.SummaryPanel) { Write-Log -Level Warning -Message "Summary panel not initialized"; return }
        $total = $this.Tasks.Count
        # AI: FIX - TaskStatus enum should now be available from models.psm1 import
        $completed = ($this.Tasks | Where-Object { $_.Status -eq [TaskStatus]::Completed }).Count
        $pending = $total - $completed
        $summaryContent = @( "Task Summary", "═══════════", "", "Total Tasks: $total", "Completed:   $completed", "Pending:     $pending", "", "Use number keys or", "arrow keys + Enter" )
        $this.SummaryPanel.SetContent($summaryContent)
        Write-Log -Level Debug -Message "Summary updated: $total total, $completed completed"
    }

    [void] HandleInput([ConsoleKeyInfo]$key) {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "HandleInput" -ScriptBlock {
            if (-not $this.MainMenu) { Write-Log -Level Warning -Message "Main menu not initialized"; return }
            
            $keyChar = $key.KeyChar.ToString().ToUpper()
            if ($keyChar -match '^[123Q]$') {
                Write-Log -Level Debug -Message "Processing hotkey: $keyChar"
                $this.MainMenu.ExecuteAction($keyChar)
                return
            }
            
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) { if ($this.MainMenu.SelectedIndex -gt 0) { $this.MainMenu.SelectedIndex-- } }
                ([ConsoleKey]::DownArrow) { if ($this.MainMenu.SelectedIndex -lt ($this.MainMenu.Items.Count - 1)) { $this.MainMenu.SelectedIndex++ } }
                ([ConsoleKey]::Enter) {
                    $selectedItem = $this.MainMenu.Items[$this.MainMenu.SelectedIndex]
                    if ($selectedItem -and $selectedItem.Enabled) {
                        Write-Log -Level Debug -Message "Executing selected menu item: $($selectedItem.Key)"
                        $selectedItem.Execute()
                    }
                }
                ([ConsoleKey]::Escape) { Write-Log -Level Debug -Message "Escape pressed - requesting exit"; $this.Services.Navigation.RequestExit() }
                default { Write-Log -Level Debug -Message "Unhandled key: $($key.Key)" }
            }
        }
    }

    [void] OnDeactivate() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "OnDeactivate" -ScriptBlock {
            $this.Cleanup() # Unsubscribe from events
            Write-Log -Level Debug -Message "DashboardScreen deactivated and cleaned up"
        }
    }
}

Export-ModuleMember -Function @() -Variable @() -Cmdlet @() -Alias @()
