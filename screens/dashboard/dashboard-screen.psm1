# ==============================================================================
# PMC Terminal v5 - Class-Based Dashboard Screen
# Main entry screen for the application.
# AI: Phase 2 - Updated to use NavigationMenu instead of deleted Table class
# ==============================================================================

# AI: No more using module statements - all dependencies loaded by main app
class DashboardScreen : Screen {
    # --- UI Components ---
    [BorderPanel] $MainPanel
    [ContentPanel] $SummaryPanel
    [NavigationMenu] $MainMenu
    [BorderPanel] $MenuPanel
    
    # --- State ---
    [object[]] $Tasks = @()

    DashboardScreen([hashtable]$services) : base("DashboardScreen", $services) {
        Write-Log -Level Info -Message "Creating DashboardScreen instance." -Component "DashboardScreen"
    }

    [void] Initialize() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "Initialize" -ScriptBlock {
            # --- Main Panel Setup ---
            $this.MainPanel = [BorderPanel]::new("DashboardMain", 0, 0, 120, 30)
            $this.MainPanel.Title = "PMC Terminal v5 - Dashboard"
            $this.MainPanel.BorderStyle = "Double"
            $this.AddPanel($this.MainPanel)

            # --- Summary Panel ---
            $this.SummaryPanel = [ContentPanel]::new("DashboardSummary", 2, 2, 40, 10)
            $this.MainPanel.AddChild($this.SummaryPanel)

            # --- Navigation Menu Setup ---
            $this.MainMenu = [NavigationMenu]::new("MainMenu")
            $this.MainMenu.X = 44
            $this.MainMenu.Y = 4
            $this.MainMenu.Width = 50
            $this.MainMenu.Height = 8
            
            # AI: Build the main menu using NavigationMenu instead of Table
            $this.BuildMainMenu()
            
            # --- Menu Container Panel ---
            $this.MenuPanel = [BorderPanel]::new("MenuContainer", 44, 2, 50, 12)
            $this.MenuPanel.Title = "Main Menu"
            $this.MenuPanel.AddChild($this.MainMenu)
            $this.MainPanel.AddChild($this.MenuPanel)

            # --- Event Subscription & Data Refresh ---
            Subscribe-Event -EventName "Tasks.Changed" -Action { $this.RefreshData() }
            $this.RefreshData() # Initial data load
            
            Write-Log -Level Info -Message "DashboardScreen initialized successfully" -Component "DashboardScreen"
        }
    }

    # AI: Build navigation menu with proper service integration
    hidden [void] BuildMainMenu() {
        # AI: Create navigation items with proper service calls
        $taskManagementItem = [NavigationItem]::new("1", "Task Management", {
            $this.Services.Navigation.GoTo("/tasks")
        })
        
        $projectManagementItem = [NavigationItem]::new("2", "Project Management", {
            $this.Services.Navigation.GoTo("/projects")
        })
        
        $settingsItem = [NavigationItem]::new("3", "Settings", {
            $this.Services.Navigation.GoTo("/settings")
        })
        
        $quitItem = [NavigationItem]::new("Q", "Quit Application", {
            $this.Services.Navigation.RequestExit()
        })
        
        # Add items to menu
        $this.MainMenu.AddItem($taskManagementItem)
        $this.MainMenu.AddItem($projectManagementItem)
        $this.MainMenu.AddItem($settingsItem)
        $this.MainMenu.AddSeparator()
        $this.MainMenu.AddItem($quitItem)
        
        Write-Log -Level Debug -Message "Main menu built with $($this.MainMenu.Items.Count) items" -Component "DashboardScreen"
    }

    hidden [void] RefreshData() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "RefreshData" -ScriptBlock {
            if ($null -eq $this.Services -or $null -eq $this.Services.DataManager) {
                Write-Log -Level Warning -Message "DataManager service not available for refresh" -Component "DashboardScreen"
                return
            }
            
            $this.Tasks = @($this.Services.DataManager.GetTasks())
            $this.UpdateSummary()
            Write-Log -Level Debug -Message "Dashboard data refreshed - $($this.Tasks.Count) tasks loaded" -Component "DashboardScreen"
        }
    }

    hidden [void] UpdateSummary() {
        if ($null -eq $this.SummaryPanel) {
            Write-Log -Level Warning -Message "Summary panel not initialized" -Component "DashboardScreen"
            return
        }
        
        $total = $this.Tasks.Count
        $completed = ($this.Tasks | Where-Object { $_.Status -eq [TaskStatus]::Completed }).Count
        $pending = $total - $completed
        
        $summaryContent = @(
            "Task Summary",
            "═══════════",
            "",
            "Total Tasks: $total",
            "Completed:   $completed", 
            "Pending:     $pending",
            "",
            "Use number keys or",
            "arrow keys + Enter"
        )
        
        $this.SummaryPanel.SetContent($summaryContent)
        Write-Log -Level Debug -Message "Summary updated: $total total, $completed completed" -Component "DashboardScreen"
    }

    [void] HandleInput([ConsoleKeyInfo]$key) {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "HandleInput" -ScriptBlock {
            if ($null -eq $this.MainMenu) {
                Write-Log -Level Warning -Message "Main menu not initialized for input handling" -Component "DashboardScreen"
                return
            }
            
            # AI: Handle direct key presses (1, 2, 3, Q)
            $keyChar = $key.KeyChar.ToString().ToUpper()
            if (-not [string]::IsNullOrEmpty($keyChar) -and $keyChar -match '^[123Q]$') {
                Write-Log -Level Debug -Message "Processing hotkey: $keyChar" -Component "DashboardScreen"
                $this.MainMenu.ExecuteAction($keyChar)
                return
            }
            
            # AI: Handle navigation keys for menu selection
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) { 
                    if ($this.MainMenu.SelectedIndex -gt 0) {
                        $this.MainMenu.SelectedIndex--
                    }
                }
                ([ConsoleKey]::DownArrow) { 
                    if ($this.MainMenu.SelectedIndex -lt ($this.MainMenu.Items.Count - 1)) {
                        $this.MainMenu.SelectedIndex++
                    }
                }
                ([ConsoleKey]::Enter) {
                    $selectedItem = $this.MainMenu.Items[$this.MainMenu.SelectedIndex]
                    if ($null -ne $selectedItem -and $selectedItem.Enabled) {
                        Write-Log -Level Debug -Message "Executing selected menu item: $($selectedItem.Key)" -Component "DashboardScreen"
                        $selectedItem.Execute()
                    }
                }
                ([ConsoleKey]::Escape) {
                    Write-Log -Level Debug -Message "Escape pressed - requesting exit" -Component "DashboardScreen"
                    $this.Services.Navigation.RequestExit()
                }
                default {
                    Write-Log -Level Debug -Message "Unhandled key: $($key.Key)" -Component "DashboardScreen"
                }
            }
        }
    }

    # AI: Override to ensure proper cleanup
    [void] OnDeactivate() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "OnDeactivate" -ScriptBlock {
            # Unsubscribe from events to prevent memory leaks
            Unsubscribe-Event -EventName "Tasks.Changed"
            Write-Log -Level Debug -Message "DashboardScreen deactivated and cleaned up" -Component "DashboardScreen"
        }
    }
}

# Export the screen class
Export-ModuleMember -Variable @() -Function @() -Cmdlet @() -Alias @()