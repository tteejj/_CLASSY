# ==============================================================================
# PMC Terminal v5 - Class-Based Task List Screen
# Displays and manages tasks.
# ==============================================================================

# Import models for Task and enum types
using module '..\modules\models.psm1'

# Import base classes and components
using module '..\components\ui-classes.psm1'
using module '..\components\panel-classes.psm1'
using module '..\components\table-class.psm1'

# AI: Removed utility imports - these are loaded globally by main application
# Note: error-handling and event-system functions are available globally

class TaskListScreen : Screen {
    # --- UI Components ---
    [BorderPanel] $MainPanel
    [Table] $TaskTable
    [ContentPanel] $NavPanel

    # --- State ---
    [string] $FilterStatus = "All"

    TaskListScreen([hashtable]$services) : base("TaskListScreen", $services) { }

    [void] Initialize() {
        Invoke-WithErrorHandling -Component "TaskListScreen" -Context "Initialize" -ScriptBlock {
            # --- Panel Setup ---
            $this.MainPanel = [BorderPanel]::new("TaskListMain", 0, 0, 120, 30)
            $this.MainPanel.Title = "Task List"
            $this.AddPanel($this.MainPanel)

            # --- Task Table ---
            $this.TaskTable = [Table]::new("TaskTable")
            $this.TaskTable.SetColumns(@(
                [TableColumn]::new("Title", "Task Title", 50),
                [TableColumn]::new("Status", "Status", 15),
                [TableColumn]::new("Priority", "Priority", 12),
                [TableColumn]::new("DueDate", "Due Date", 15)
            ))
            
            $tableContainer = [BorderPanel]::new("TableContainer", 1, 1, 118, 24)
            $tableContainer.ShowBorder = $false
            $tableContainer.AddChild($this.TaskTable)
            $this.MainPanel.AddChild($tableContainer)
            
            # --- Navigation Panel ---
            $this.NavPanel = [ContentPanel]::new("NavPanel", 1, 26, 118, 3)
            $this.MainPanel.AddChild($this.NavPanel)
            
            # --- Event Subscriptions & Data Load ---
            $this.SubscribeToEvent("Tasks.Changed", { $this.RefreshData() })
            $this.RefreshData()
        }
    }

    hidden [void] RefreshData() {
        Invoke-WithErrorHandling -Component "TaskListScreen" -Context "RefreshData" -ScriptBlock {
            $allTasks = @($this.Services.DataManager.GetTasks())
            $filteredTasks = switch ($this.FilterStatus) {
                "Active" { $allTasks | Where-Object { $_.Status -ne 'Completed' } }
                "Completed" { $allTasks | Where-Object { $_.Status -eq 'Completed' } }
                default { $allTasks }
            }
            $this.TaskTable.SetData($filteredTasks)
            $this.UpdateNavText()
        }
    }

    hidden [void] UpdateNavText() {
        $navContent = @(
            "[N]ew | [E]dit | [D]elete | [Space]Toggle | [F]ilter: $($this.FilterStatus) | [Esc]Back"
        )
        $this.NavPanel.SetContent($navContent)
    }

    [void] HandleInput([ConsoleKeyInfo]$key) {
        Invoke-WithErrorHandling -Component "TaskListScreen" -Context "HandleInput" -ScriptBlock {
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) { $this.TaskTable.SelectPrevious() }
                ([ConsoleKey]::DownArrow) { $this.TaskTable.SelectNext() }
                ([ConsoleKey]::Spacebar) { $this.ToggleSelectedTask() }
                ([ConsoleKey]::Escape) { $this.Services.Navigation.PopScreen() }
                default {
                    switch ($key.KeyChar.ToString().ToUpper()) {
                        'N' { $this.Services.Navigation.PushScreen("NewTaskScreen") }
                        'E' { # Edit logic would go here }
                        'D' { # Delete logic would go here }
                        'F' { $this.CycleFilter() }
                    }
                }
            }
        }
    }
    
    hidden [void] ToggleSelectedTask() {
        $task = $this.TaskTable.GetSelectedItem()
        if ($task) {
            if ($task.Status -eq [TaskStatus]::Completed) {
                $task.Status = [TaskStatus]::Active
            } else {
                $task.Complete()
            }
            $this.Services.DataManager.UpdateTask($task)
        }
    }

    hidden [void] CycleFilter() {
        $this.FilterStatus = switch ($this.FilterStatus) {
            "All" { "Active" }
            "Active" { "Completed" }
            default { "All" }
        }
        $this.RefreshData()
    }
}