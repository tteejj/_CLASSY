# ==============================================================================
# PMC Terminal v5 - Class-Based Task List Screen
# Displays and manages tasks.
# ==============================================================================

# AI: CRITICAL FIX - Import models module for TaskStatus enum and other types
using module '..\modules\models.psm1'

# AI: FIX - Use relative paths for better portability
using module '..\components\ui-classes.psm1'
using module '..\layout\panels-class.psm1'
using module '..\components\advanced-data-components.psm1'

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
                "Active" { $allTasks | Where-Object { $_.Status -ne [TaskStatus]::Completed } }
                "Completed" { $allTasks | Where-Object { $_.Status -eq [TaskStatus]::Completed } }
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
                        'N' { $this.ShowNewTaskDialog() }
                        'E' { $this.EditSelectedTask() }
                        'D' { $this.DeleteSelectedTask() }
                        'F' { $this.CycleFilter() }
                    }
                }
            }
        }
    }
    
    hidden [void] ToggleSelectedTask() {
        $task = $this.TaskTable.GetSelectedItem()
        if ($task) {
            # AI: FIX - TaskStatus enum should now be available from models.psm1 import
            if ($task.Status -eq [TaskStatus]::Completed) {
                $task.Status = [TaskStatus]::Pending
            } else {
                $task.Complete()
            }
            $this.Services.DataManager.UpdateTask($task)
        }
    }

    hidden [void] ShowNewTaskDialog() {
        # AI: FIX - Implemented new task dialog functionality
        Write-Log -Level Info -Message "New task dialog requested"
        
        # AI: FIX - Capture $this context for closure
        $dataManager = $this.Services.DataManager
        $refreshCallback = { $this.RefreshData() }.GetNewClosure()
        
        # Use the input dialog from dialog system
        Show-InputDialog -Title "New Task" -Prompt "Enter task title:" -OnSubmit {
            param($Value)
            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                $newTask = $dataManager.AddTask($Value, "", [TaskPriority]::Medium, "General")
                Write-Log -Level Info -Message "Created new task: $($newTask.Title)"
                & $refreshCallback
            }
        }
    }

    hidden [void] EditSelectedTask() {
        $task = $this.TaskTable.GetSelectedItem()
        if ($task) {
            Write-Log -Level Info -Message "Edit task requested for: $($task.Title)"
        }
    }

    hidden [void] DeleteSelectedTask() {
        $task = $this.TaskTable.GetSelectedItem()
        if ($task) {
            Write-Log -Level Info -Message "Delete task requested for: $($task.Title)"
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

Export-ModuleMember -Function @() -Variable @() -Cmdlet @() -Alias @()
