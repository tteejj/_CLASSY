
# Data Manager Module
# Unified data persistence and CRUD operations with event integration

using module ..\modules\models.psm1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Module-level state variables
$script:Data = @{
    Projects = [System.Collections.Generic.List[PmcProject]]::new()
    Tasks = [System.Collections.Generic.List[PmcTask]]::new()
    TimeEntries = @()
    ActiveTimers = @{}
    TodoTemplates = @{}
    Settings = @{
        DefaultView = "Dashboard"
        Theme = "Modern"
        AutoSave = $true
        BackupCount = 5
    }
    time_entries = @() # underscore format for action compatibility
    timers = @()       # for action compatibility
}

$script:DataPath = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PMCTerminal\pmc-data.json"
$script:BackupPath = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PMCTerminal\backups"
$script:LastSaveTime = $null
$script:DataModified = $false

function Initialize-DataManager {
    <#
    .SYNOPSIS
    Initializes the data management system, loads data, and returns a service instance.
    #>
    [CmdletBinding()]
    param()
    
    return Invoke-WithErrorHandling -Component "DataManager.Initialize" -Context "DataManager initialization" -ScriptBlock {
        $dataDirectory = Split-Path $script:DataPath -Parent
        if (-not (Test-Path $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
            Write-Log -Level Info -Message "Created data directory: $dataDirectory"
        }
        
        if (-not (Test-Path $script:BackupPath)) {
            New-Item -ItemType Directory -Path $script:BackupPath -Force | Out-Null
            Write-Log -Level Info -Message "Created backup directory: $script:BackupPath"
        }
        
        Load-UnifiedData
        Initialize-DataEventHandlers
        
        Write-Log -Level Info -Message "DataManager initialized successfully"
        return [DataManager]::new()
    }
}

function Load-UnifiedData {
    <#
    .SYNOPSIS
    Loads application data from disk into strongly-typed objects.
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.LoadData" -Context "Loading unified data from disk" -ScriptBlock {
        if (Test-Path $script:DataPath) {
            try {
                $loadedData = Get-Content -Path $script:DataPath -Raw | ConvertFrom-Json -AsHashtable
                
                if ($loadedData -is [hashtable]) {
                    if ($loadedData.Tasks) {
                        $script:Data.Tasks.Clear()
                        foreach ($taskData in $loadedData.Tasks) {
                            if ($taskData -is [hashtable]) { $script:Data.Tasks.Add([PmcTask]::FromLegacyFormat($taskData)) }
                        }
                        Write-Log -Level Debug -Message "Re-hydrated $($script:Data.Tasks.Count) tasks as PmcTask objects"
                    }
                    
                    if ($loadedData.Projects -is [hashtable]) {
                        $script:Data.Projects.Clear()
                        foreach ($projectKey in $loadedData.Projects.Keys) {
                            $projectData = $loadedData.Projects[$projectKey]
                            if ($projectData -is [hashtable]) { $script:Data.Projects.Add([PmcProject]::FromLegacyFormat($projectData)) }
                        }
                        Write-Log -Level Debug -Message "Re-hydrated $($script:Data.Projects.Count) projects as PmcProject objects"
                    }
                    
                    foreach ($key in 'TimeEntries', 'ActiveTimers', 'TodoTemplates', 'Settings', 'time_entries', 'timers') {
                        if ($loadedData.ContainsKey($key)) { $script:Data[$key] = $loadedData[$key] }
                    }
                    
                    $global:Data = $script:Data
                    Write-Log -Level Info -Message "Data loaded successfully from disk"
                } else {
                    Write-Log -Level Warning -Message "Invalid data format in file, using defaults"
                    $global:Data = $script:Data
                }
            } catch {
                Write-Log -Level Error -Message "Failed to parse data file: $_"
                $global:Data = $script:Data
            }
        } else {
            Write-Log -Level Info -Message "No existing data file found, using defaults"
            $global:Data = $script:Data
        }
        
        $script:LastSaveTime = Get-Date
    }
}

function Save-UnifiedData {
    <#
    .SYNOPSIS
    Saves application data to disk with backup rotation.
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.SaveData" -Context "Saving unified data to disk" -ScriptBlock {
        if (Test-Path $script:DataPath) {
            $backupName = "pmc-data_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date)
            Copy-Item -Path $script:DataPath -Destination (Join-Path $script:BackupPath $backupName) -Force
            
            $backups = Get-ChildItem -Path $script:BackupPath -Filter "pmc-data_*.json" | Sort-Object LastWriteTime -Descending
            if ($backups.Count -gt $script:Data.Settings.BackupCount) {
                $backups | Select-Object -Skip $script:Data.Settings.BackupCount | Remove-Item -Force
            }
        }
        
        $dataToSave = @{
            Tasks = @($script:Data.Tasks | ForEach-Object { $_.ToLegacyFormat() })
            Projects = @{}
            TimeEntries = $script:Data.TimeEntries
            ActiveTimers = $script:Data.ActiveTimers
            TodoTemplates = $script:Data.TodoTemplates
            Settings = $script:Data.Settings
            time_entries = $script:Data.time_entries
            timers = $script:Data.timers
        }
        
        foreach ($project in $script:Data.Projects) { $dataToSave.Projects[$project.Key] = $project.ToLegacyFormat() }
        
        $dataToSave | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:DataPath -Encoding UTF8
        $script:LastSaveTime = Get-Date; $script:DataModified = $false
        Write-Log -Level Debug -Message "Data saved successfully"
    }
}

#region Task Management Functions

function Add-PmcTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Title,
        [string]$Description = "",
        [ValidateSet("low", "medium", "high")] [string]$Priority = "medium",
        [string]$Category = "General",
        [string]$DueDate = ""
    )
    
    return Invoke-WithErrorHandling -Component "DataManager.AddTask" -Context "Adding new task" -ScriptBlock {
        if ([string]::IsNullOrWhiteSpace($Title)) { throw [StateMutationException]::new("Task title cannot be empty", @{ Title = $Title }) }
        
        $taskPriority = [TaskPriority]::$Priority
        $newTask = [PmcTask]::new($Title, $Description, $taskPriority, $Category)
        
        if ($DueDate -and $DueDate -ne "N/A") {
            try { $newTask.DueDate = [datetime]::Parse($DueDate) } catch { Write-Log -Level Warning -Message "Invalid due date format: $DueDate" }
        }
        
        $script:Data.Tasks.Add($newTask); $script:DataModified = $true
        Write-Log -Level Info -Message "Created task '$($newTask.Title)' with ID $($newTask.Id)"
        
        if ($script:Data.Settings.AutoSave) { Save-UnifiedData }
        
        Publish-Event -EventName "Tasks.Changed" -Data @{ Action = "Created"; TaskId = $newTask.Id; Task = $newTask }
        return $newTask
    }
}

function Update-PmcTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PmcTask]$Task,
        [string]$Title, [string]$Description, [ValidateSet("low", "medium", "high")] [string]$Priority,
        [string]$Category, [string]$DueDate, [bool]$Completed, [ValidateRange(0, 100)] [int]$Progress
    )
    
    return Invoke-WithErrorHandling -Component "DataManager.UpdateTask" -Context "Updating task" -ScriptBlock {
        $managedTask = $script:Data.Tasks.Find({$_.Id -eq $Task.Id})
        if (-not $managedTask) { throw [StateMutationException]::new("Task not found in data store", @{ TaskId = $Task.Id }) }
        
        $updatedFields = @()
        if ($PSBoundParameters.ContainsKey('Title')) { $managedTask.Title = $Title.Trim(); $updatedFields += "Title" }
        if ($PSBoundParameters.ContainsKey('Description')) { $managedTask.Description = $Description; $updatedFields += "Description" }
        if ($PSBoundParameters.ContainsKey('Priority')) { $managedTask.Priority = [TaskPriority]::$Priority; $updatedFields += "Priority" }
        if ($PSBoundParameters.ContainsKey('Category')) { $managedTask.ProjectKey = $Category; $managedTask.Category = $Category; $updatedFields += "Category" }
        if ($PSBoundParameters.ContainsKey('DueDate')) {
            try { $managedTask.DueDate = ($DueDate -and $DueDate -ne "N/A") ? [datetime]::Parse($DueDate) : $null } catch { Write-Log -Level Warning -Message "Invalid due date format: $DueDate" }
            $updatedFields += "DueDate"
        }
        if ($PSBoundParameters.ContainsKey('Progress')) { $managedTask.UpdateProgress($Progress); $updatedFields += "Progress" }
        if ($PSBoundParameters.ContainsKey('Completed')) {
            if ($Completed) { $managedTask.Complete() } else { $managedTask.Status = [TaskStatus]::Pending; $managedTask.Completed = $false; $managedTask.Progress = 0 }
            $updatedFields += "Completed"
        }
        
        $managedTask.UpdatedAt = [datetime]::Now; $script:DataModified = $true
        Write-Log -Level Info -Message "Updated task $($managedTask.Id) - Fields: $($updatedFields -join ', ')"
        
        if ($script:Data.Settings.AutoSave) { Save-UnifiedData }
        
        Publish-Event -EventName "Tasks.Changed" -Data @{ Action = "Updated"; TaskId = $managedTask.Id; Task = $managedTask; UpdatedFields = $updatedFields }
        return $managedTask
    }
}

function Remove-PmcTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PmcTask]$Task)
    
    return Invoke-WithErrorHandling -Component "DataManager.RemoveTask" -Context "Removing task" -ScriptBlock {
        $taskToRemove = $script:Data.Tasks.Find({$_.Id -eq $Task.Id})
        if ($taskToRemove) {
            $script:Data.Tasks.Remove($taskToRemove) | Out-Null; $script:DataModified = $true
            Write-Log -Level Info -Message "Deleted task $($Task.Id)"
            if ($script:Data.Settings.AutoSave) { Save-UnifiedData }
            Publish-Event -EventName "Tasks.Changed" -Data @{ Action = "Deleted"; TaskId = $Task.Id; Task = $Task }
            return $true
        }
        Write-Log -Level Warning -Message "Task not found with ID $($Task.Id)"; return $false
    }
}

function Get-PmcTasks {
    [CmdletBinding()]
    param([bool]$Completed, [ValidateSet("low", "medium", "high")] [string]$Priority, [string]$Category)
    
    return Invoke-WithErrorHandling -Component "DataManager.GetTasks" -Context "Retrieving tasks" -ScriptBlock {
        $tasks = $script:Data.Tasks
        if ($PSBoundParameters.ContainsKey('Completed')) { $tasks = $tasks | Where-Object { $_.Completed -eq $Completed } }
        if ($Priority) { $priorityEnum = [TaskPriority]::$Priority; $tasks = $tasks | Where-Object { $_.Priority -eq $priorityEnum } }
        if ($Category) { $tasks = $tasks | Where-Object { $_.ProjectKey -eq $Category -or $_.Category -eq $Category } }
        return @($tasks)
    }
}

#endregion

#region Project Management Functions

function Get-PmcProjects { [CmdletBinding()] param() return @($script:Data.Projects) }
function Get-PmcProject { [CmdletBinding()] param([Parameter(Mandatory)] [string]$Key) return $script:Data.Projects.Find({$_.Key -eq $Key}) }

function Add-PmcProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PmcProject]$Project)
    
    return Invoke-WithErrorHandling -Component "DataManager.AddProject" -Context "Adding project" -ScriptBlock {
        if ($script:Data.Projects.Exists({$_.Key -eq $Project.Key})) { throw [StateMutationException]::new("Project with key '$($Project.Key)' already exists", @{ ProjectKey = $Project.Key }) }
        
        $script:Data.Projects.Add($Project); $script:DataModified = $true
        Write-Log -Level Info -Message "Created project '$($Project.Name)' with key $($Project.Key)"
        if ($script:Data.Settings.AutoSave) { Save-UnifiedData }
        Publish-Event -EventName "Projects.Changed" -Data @{ Action = "Created"; ProjectKey = $Project.Key; Project = $Project }
        return $Project
    }
}

#endregion

#region DataManager Class Definition

class DataManager {
    hidden [hashtable] $DataStore
    hidden [string] $DataFilePath
    hidden [bool] $AutoSaveEnabled = $true
    
    DataManager() {
        $this.DataStore = $script:Data
        $global:Data = $script:Data
        $this.DataFilePath = $script:DataPath
        $this.AutoSaveEnabled = $this.DataStore.Settings.AutoSave
    }

    [void] LoadData() { Load-UnifiedData }
    [void] SaveData() { Save-UnifiedData }
    [PmcTask] AddTask([string]$Title, [string]$Description, [TaskPriority]$Priority, [string]$ProjectKey) { return Add-PmcTask -Title $Title -Description $Description -Priority $Priority.ToString() -Category $ProjectKey }
    [PmcTask[]] GetTasks() { return @($this.DataStore.Tasks) }
    [PmcProject[]] GetProjects() { return @($this.DataStore.Projects) }
}

#endregion

#region Private Helper Functions

function Initialize-DataEventHandlers {
    Invoke-WithErrorHandling -Component "DataManager.InitializeEventHandlers" -Context "Initializing data event handlers" -ScriptBlock {
        $null = Subscribe-Event -EventName "Tasks.RefreshRequested" -Handler {
            Publish-Event -EventName "Tasks.Changed" -Data @{ Action = "Refreshed"; Tasks = @($script:Data.Tasks) }
        }
        Write-Log -Level Debug -Message "Data event handlers initialized"
    }
}

#endregion

Export-ModuleMember -Function 'Initialize-DataManager', 'Add-PmcTask', 'Update-PmcTask', 'Remove-PmcTask', 'Get-PmcTasks', 'Get-PmcProjects', 'Get-PmcProject', 'Add-PmcProject', 'Save-UnifiedData', 'Load-UnifiedData'
