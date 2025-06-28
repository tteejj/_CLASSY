# Dashboard Screen Class Implementation
# Fixes Context parameter binding issues and initialization problems

using namespace System.Collections.Generic

# Import base classes
using module ..\..\components\ui-classes.psm1
using module ..\..\components\panel-classes.psm1

# Import utilities
Import-Module "$PSScriptRoot\..\..\utilities\error-handling.psm1" -Force
Import-Module "$PSScriptRoot\..\..\utilities\event-system.psm1" -Force

class DashboardScreen : Screen {
    # UI Components
    [BorderPanel] $MainPanel
    [ContentPanel] $SummaryPanel
    [ContentPanel] $TaskPanel
    [BorderPanel] $NavigationPanel
    
    # State
    [object[]] $Tasks = @()
    [int] $SelectedTaskIndex = 0
    
    DashboardScreen([hashtable]$services) : base("DashboardScreen", $services) {
        Write-Log -Level Info -Message "Creating DashboardScreen instance"
    }
    
    [void] Initialize() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "Initialize" -ScriptBlock {
            Write-Log -Level Info -Message "Initializing DashboardScreen"
            
            # Create main container panel
            $this.MainPanel = [BorderPanel]::new("DashboardMain", 0, 0, 120, 30)
            $this.MainPanel.Title = "PMC Terminal v5 - Dashboard"
            $this.MainPanel.BorderStyle = "Double"
            $this.AddPanel($this.MainPanel)
            
            # Create summary panel (left side)
            $this.SummaryPanel = [ContentPanel]::new("DashboardSummary", 2, 2, 40, 10)
            $this.MainPanel.AddChild($this.SummaryPanel)
            
            # Create task panel (right side)
            $this.TaskPanel = [ContentPanel]::new("DashboardTasks", 44, 2, 74, 20)
            $this.MainPanel.AddChild($this.TaskPanel)
            
            # Create navigation panel (bottom)
            $this.NavigationPanel = [BorderPanel]::new("DashboardNav", 2, 23, 116, 6)
            $this.NavigationPanel.Title = "Navigation"
            $this.NavigationPanel.BorderStyle = "Single"
            $this.MainPanel.AddChild($this.NavigationPanel)
            
            # Initialize navigation content
            $this.InitializeNavigation()
            
            # Subscribe to events
            $this.SubscribeToEvents()
            
            # Load initial data
            $this.RefreshData()
            
            # Mark as initialized
            $this.IsInitialized = $true
            Write-Log -Level Info -Message "DashboardScreen initialized successfully"
        }
    }
    
    hidden [void] InitializeNavigation() {
        $navContent = @(
            "[N] New Task    [E] Edit Task    [D] Delete Task    [Space] Toggle Complete",
            "[P] Projects    [T] Tags         [F] Filter        [S] Settings",
            "[↑↓] Navigate   [Enter] Select   [Esc] Back        [Q] Quit"
        )
        
        $navPanel = [ContentPanel]::new("NavContent", 3, 24, 114, 4)
        $navPanel.SetContent($navContent)
        $this.NavigationPanel.AddChild($navPanel)
    }
    
    hidden [void] SubscribeToEvents() {
        # Subscribe to task changes
        $this.SubscribeToEvent("Tasks.Changed", {
            param($eventArgs)
            $this.RefreshData()
        })
        
        # Subscribe to project changes
        $this.SubscribeToEvent("Projects.Changed", {
            param($eventArgs)
            $this.RefreshData()
        })
        
        Write-Log -Level Debug -Message "DashboardScreen subscribed to events"
    }
    
    hidden [void] RefreshData() {
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "RefreshData" -ScriptBlock {
            Write-Log -Level Debug -Message "Refreshing dashboard data"
            
            # Get data from services
            if ($null -ne $this.Services -and $null -ne $this.Services.DataManager) {
                $this.Tasks = @($this.Services.DataManager.GetTasks())
                
                # Update summary
                $this.UpdateSummary()
                
                # Update task list
                $this.UpdateTaskList()
            } else {
                Write-Log -Level Warning -Message "DataManager service not available"
            }
        }
    }
    
    hidden [void] UpdateSummary() {
        $totalTasks = $this.Tasks.Count
        $completedTasks = @($this.Tasks | Where-Object { $_.Status -eq "Completed" }).Count
        $todayTasks = @($this.Tasks | Where-Object { 
            $_.DueDate -and ([DateTime]$_.DueDate).Date -eq (Get-Date).Date 
        }).Count
        
        $summaryContent = @(
            "═══════════════════════════════════════",
            "         Task Summary",
            "═══════════════════════════════════════",
            "",
            "  Total Tasks:      $totalTasks",
            "  Completed:        $completedTasks",
            "  Due Today:        $todayTasks",
            "",
            "  Completion Rate:  $(if ($totalTasks -gt 0) { "{0:P0}" -f ($completedTasks / $totalTasks) } else { "N/A" })"
        )
        
        $this.SummaryPanel.SetContent($summaryContent)
    }
    
    hidden [void] UpdateTaskList() {
        $taskContent = @("═══════════════════════════════════════════════════════════════════════")
        $taskContent += "  #  Task Title                          Status       Priority   Due Date"
        $taskContent += "═══════════════════════════════════════════════════════════════════════"
        
        for ($i = 0; $i -lt $this.Tasks.Count; $i++) {
            $task = $this.Tasks[$i]
            $isSelected = $i -eq $this.SelectedTaskIndex
            $prefix = if ($isSelected) { "→" } else { " " }
            
            $title = if ($task.Title.Length -gt 35) { 
                $task.Title.Substring(0, 32) + "..." 
            } else { 
                $task.Title.PadRight(35) 
            }
            
            $status = ($task.Status ?? "Pending").PadRight(12)
            $priority = ($task.Priority ?? "Normal").PadRight(10)
            $dueDate = if ($task.DueDate) { 
                ([DateTime]$task.DueDate).ToString("MM/dd/yyyy") 
            } else { 
                "          " 
            }
            
            $line = "$prefix $("{0,2}" -f ($i + 1))  $title  $status $priority $dueDate"
            $taskContent += $line
        }
        
        if ($this.Tasks.Count -eq 0) {
            $taskContent += ""
            $taskContent += "                    No tasks found. Press [N] to create a new task."
        }
        
        $this.TaskPanel.SetContent($taskContent)
    }
    
    [void] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this.IsInitialized) {
            Write-Log -Level Warning -Message "HandleInput called on uninitialized screen"
            return
        }
        
        Invoke-WithErrorHandling -Component "DashboardScreen" -Context "HandleInput" -ScriptBlock {
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) {
                    if ($this.SelectedTaskIndex -gt 0) {
                        $this.SelectedTaskIndex--
                        $this.UpdateTaskList()
                    }
                }
                ([ConsoleKey]::DownArrow) {
                    if ($this.SelectedTaskIndex -lt ($this.Tasks.Count - 1)) {
                        $this.SelectedTaskIndex++
                        $this.UpdateTaskList()
                    }
                }
                ([ConsoleKey]::Enter) {
                    if ($this.Tasks.Count -gt 0 -and $this.SelectedTaskIndex -ge 0) {
                        $selectedTask = $this.Tasks[$this.SelectedTaskIndex]
                        $this.Services.Navigation.PushScreen("TaskDetailScreen", @{TaskId = $selectedTask.Id})
                    }
                }
                ([ConsoleKey]::Escape) {
                    # Already at top level, could show exit confirmation
                }
                default {
                    # Handle character keys
                    $char = [char]$key.KeyChar
                    switch ($char.ToString().ToUpper()) {
                        'N' { $this.Services.Navigation.PushScreen("NewTaskScreen") }
                        'E' { 
                            if ($this.Tasks.Count -gt 0) {
                                $selectedTask = $this.Tasks[$this.SelectedTaskIndex]
                                $this.Services.Navigation.PushScreen("EditTaskScreen", @{TaskId = $selectedTask.Id})
                            }
                        }
                        'D' { 
                            if ($this.Tasks.Count -gt 0) {
                                $selectedTask = $this.Tasks[$this.SelectedTaskIndex]
                                $this.Services.DataManager.DeleteTask($selectedTask.Id)
                            }
                        }
                        'P' { $this.Services.Navigation.PushScreen("ProjectListScreen") }
                        'T' { $this.Services.Navigation.PushScreen("TaskListScreen") }
                        'Q' { 
                            # Exit is handled by main loop
                            # Could show exit confirmation here if needed
                        }
                    }
                }
            }
        }
    }
    
    [void] Cleanup() {
        Write-Log -Level Info -Message "Cleaning up DashboardScreen"
        
        # Call base cleanup (which handles event unsubscription)
        ([Screen]$this).Cleanup()
    }
}

# Export the class
Export-ModuleMember -Function * -Cmdlet * -Variable * -Alias *