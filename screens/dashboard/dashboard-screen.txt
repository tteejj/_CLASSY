# ==============================================================================
# PMC Terminal v5 - Class-Based Dashboard Screen
# Main entry screen for the application.
# ==============================================================================

using namespace System.Collections.Generic

# Import base classes and components this screen uses
using module '..\..\components\ui-classes.psm1'
using module '..\..\components\panel-classes.psm1'
using module '..\..\components\table-class.psm1'

# Import utilities
Import-Module "$PSScriptRoot\..\..\utilities\error-handling.psm1" -Force
Import-Module "$PSScriptRoot\..\..\utilities\event-system.psm1" -Force

class DashboardScreen : Screen {
    # --- UI Components ---
    [BorderPanel] $MainPanel
    [ContentPanel] $SummaryPanel
    [Table] $MenuTable
    
    # --- State ---
    [object[]] $Tasks = @()

    DashboardScreen([hashtable]$services) : base("DashboardScreen", $services) {
        Write-Log -Level Info -Message "Creating DashboardScreen instance."
    }

    [void] Initialize() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "Initialize" -ScriptBlock {
            # --- Panel Setup ---
            $this.MainPanel = [BorderPanel]::new("DashboardMain", 0, 0, 120, 30)
            $this.MainPanel.Title = "PMC Terminal v5 - Dashboard"
            $this.MainPanel.BorderStyle = "Double"
            $this.AddPanel($this.MainPanel)

            $this.SummaryPanel = [ContentPanel]::new("DashboardSummary", 2, 2, 40, 10)
            $this.MainPanel.AddChild($this.SummaryPanel)

            # --- Main Menu Table ---
            $this.MenuTable = [Table]::new("MainMenu")
            $this.MenuTable.SetColumns(@(
                [TableColumn]::new("Key", "Key", 5),
                [TableColumn]::new("Action", "Action", 40)
            ))
            $menuItems = @(
                [pscustomobject]@{ Key = '1'; Action = 'Task Management'; Screen = 'TaskListScreen' },
                [pscustomobject]@{ Key = '2'; Action = 'Project Management'; Screen = 'ProjectListScreen' },
                [pscustomobject]@{ Key = '3'; Action = 'Settings'; Screen = 'SettingsScreen' },
                [pscustomobject]@{ Key = 'Q'; Action = 'Quit Application'; Screen = 'EXIT' }
            )
            $this.MenuTable.SetData($menuItems)
            $this.MenuTable.ShowHeaders = $false
            
            # Add table to a containing panel for layout
            $menuPanel = [BorderPanel]::new("MenuContainer", 44, 2, 50, 10)
            $menuPanel.Title = "Main Menu"
            $menuPanel.AddChild($this.MenuTable)
            $this.MainPanel.AddChild($menuPanel)

            # --- Event Subscription & Data Refresh ---
            $this.SubscribeToEvent("Tasks.Changed", { $this.RefreshData() })
            $this.RefreshData() # Initial data load
        }
    }

    hidden [void] RefreshData() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "RefreshData" -ScriptBlock {
            $this.Tasks = @($this.Services.DataManager.GetTasks())
            $this.UpdateSummary()
        }
    }

    hidden [void] UpdateSummary() {
        $total = $this.Tasks.Count
        $completed = ($this.Tasks | Where-Object { $_.Status -eq 'Completed' }).Count
        
        $summaryContent = @(
            "Task Summary",
            "------------",
            "Total Tasks: $total",
            "Completed:   $completed"
        )
        $this.SummaryPanel.SetContent($summaryContent)
    }

    [void] HandleInput([ConsoleKeyInfo]$key) {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "HandleInput" -ScriptBlock {
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) { $this.MenuTable.SelectPrevious() }
                ([ConsoleKey]::DownArrow) { $this.MenuTable.SelectNext() }
                ([ConsoleKey]::Enter) {
                    $selectedItem = $this.MenuTable.GetSelectedItem()
                    if ($selectedItem) {
                        if ($selectedItem.Screen -eq 'EXIT') {
                            $this.Services.Navigation.RequestExit()
                        } else {
                            $this.Services.Navigation.PushScreen($selectedItem.Screen)
                        }
                    }
                }
                default {
                    # Handle hotkeys
                    $selectedItem = $this.MenuTable.Data | Where-Object { $_.Key -eq $key.KeyChar.ToString().ToUpper() } | Select-Object -First 1
                    if ($selectedItem) {
                         if ($selectedItem.Screen -eq 'EXIT') {
                            $this.Services.Navigation.RequestExit()
                        } else {
                            $this.Services.Navigation.PushScreen($selectedItem.Screen)
                        }
                    }
                }
            }
        }
    }
}