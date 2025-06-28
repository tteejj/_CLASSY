# ==============================================================================
# PMC Terminal v5 - Class-Based Task List Screen
# Displays and manages tasks.
# ==============================================================================

# AI: FIX - Removed all using module statements. Dependencies managed by _CLASSY-MAIN.ps1.
# Note: All required classes and functions are available globally after module loading.

class TaskListScreen : Screen {
    # --- UI Components ---
    [BorderPanel] $MainPanel
    [DataTableComponent] $TaskTable
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
            $this.TaskTable = [DataTableComponent]::new("TaskTable")
            $this.TaskTable.X = 1
            $this.TaskTable.Y = 1
            $this.TaskTable.Width = 118
            $this.TaskTable.Height = 24
            $this.TaskTable.Title = "Tasks"
            $this.TaskTable.ShowBorder = $false
            
            # Set columns for the data table
            $columns = @(
                @{ Name = "Title"; Header = "Task Title"; Width = 50 },
                @{ Name = "Status"; Header = "Status"; Width = 15 },
                @{ Name = "Priority"; Header = "Priority"; Width = 12 },
                @{ Name = "DueDate"; Header = "Due Date"; Width = 15 }
            )
            $this.TaskTable.SetColumns($columns)
            
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
            # Let the data table handle its own input first
            if ($this.TaskTable.HandleInput($key)) {
                return
            }
            
            # Handle screen-specific input
            switch ($key.Key) {
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
        if ($this.TaskTable.ProcessedData -and $this.TaskTable.SelectedRow -lt $this.TaskTable.ProcessedData.Count) {
            $task = $this.TaskTable.ProcessedData[$this.TaskTable.SelectedRow]
            if ($task) {
                if ($task.Status -eq [TaskStatus]::Completed) {
                    $task.Status = [TaskStatus]::Active
                } else {
                    $task.Complete()
                }
                $this.Services.DataManager.UpdateTask($task)
            }
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