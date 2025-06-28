# Data Manager Module
# Unified data persistence and CRUD operations with event integration
# AI: Refactored from dispatch-based actions to direct function calls
# AI: Now uses strongly-typed PmcTask and PmcProject classes from models module
# AI: FIX - Added explicit Import-Module for models to make class types available during parsing

# AI: CRITICAL - Import models module for PowerShell 5.1 class type resolution
Import-Module (Join-Path $PSScriptRoot "models.psm1") -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Module-level state variables
# AI: FIX - Use generic object lists to avoid class type parsing errors
$script:Data = @{
    Projects = [System.Collections.Generic.List[object]]::new()
    Tasks = [System.Collections.Generic.List[object]]::new()
    TimeEntries = @()
    ActiveTimers = @{}
    TodoTemplates = @{}
    Settings = @{
        DefaultView = "Dashboard"
        Theme = "Modern"
        AutoSave = $true
        BackupCount = 5
    }
    # AI: Maintaining compatibility with legacy underscore format
    time_entries = @()    # underscore format for action compatibility
    timers = @()          # for action compatibility
}

$script:DataPath = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PMCTerminal\pmc-data.json"
$script:BackupPath = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PMCTerminal\backups"
$script:LastSaveTime = $null
$script:DataModified = $false

function Initialize-DataManager {
    <#
    .SYNOPSIS
    Initializes the data management system
    
    .DESCRIPTION
    Sets up the data directory, loads existing data, and configures event handlers
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.Initialize" -Context "DataManager initialization" -ScriptBlock {
        # Ensure data directory exists
        $dataDirectory = Split-Path $script:DataPath -Parent
        if (-not (Test-Path $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
            Write-Log -Level Info -Message "Created data directory: $dataDirectory"
        }
        
        # Ensure backup directory exists
        if (-not (Test-Path $script:BackupPath)) {
            New-Item -ItemType Directory -Path $script:BackupPath -Force | Out-Null
            Write-Log -Level Info -Message "Created backup directory: $script:BackupPath"
        }
        
        # Load existing data
        Load-UnifiedData
        
        # Initialize event handlers
        Initialize-DataEventHandlers
        
        Write-Log -Level Info -Message "DataManager initialized successfully"
        
        # AI: Return both service object with methods and class-based DataManager
        $serviceObject = [PSCustomObject]@{
            AddTask = Get-Command Add-PmcTask
            UpdateTask = Get-Command Update-PmcTask
            RemoveTask = Get-Command Remove-PmcTask
            GetTasks = Get-Command Get-PmcTasks
            GetProjects = Get-Command Get-PmcProjects
            SaveData = Get-Command Save-UnifiedData
            LoadData = Get-Command Load-UnifiedData
        }
        
        # Also provide class-based interface for compatibility
        $dataManager = [DataManager]::new()
        return $dataManager
    }
}

function Load-UnifiedData {
    <#
    .SYNOPSIS
    Loads application data from disk
    
    .DESCRIPTION
    Loads the unified data file and populates the global data structure with strongly-typed objects
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.LoadData" -Context "Loading unified data from disk" -ScriptBlock {
        if (Test-Path $script:DataPath) {
            try {
                $content = Get-Content -Path $script:DataPath -Raw
                $loadedData = $content | ConvertFrom-Json -AsHashtable
                
                # AI: Defensive validation of loaded data structure
                if ($loadedData -and $loadedData -is [hashtable]) {
                    # AI: Re-hydrate Tasks as PmcTask objects
                    if ($loadedData.ContainsKey('Tasks') -and $loadedData.Tasks) {
                        $script:Data.Tasks.Clear()
                        foreach ($taskData in $loadedData.Tasks) {
                            if ($taskData -is [hashtable]) {
                                # AI: Use static method to create from legacy format
                                $task = [PmcTask]::FromLegacyFormat($taskData)
                                $script:Data.Tasks.Add($task)
                            }
                        }
                        Write-Log -Level Debug -Message "Re-hydrated $($script:Data.Tasks.Count) tasks as PmcTask objects"
                    }
                    
                    # AI: Re-hydrate Projects as PmcProject objects
                    if ($loadedData.ContainsKey('Projects') -and $loadedData.Projects) {
                        $script:Data.Projects.Clear()
                        # AI: Projects were stored as hashtable, need to convert each value
                        if ($loadedData.Projects -is [hashtable]) {
                            foreach ($projectKey in $loadedData.Projects.Keys) {
                                $projectData = $loadedData.Projects[$projectKey]
                                if ($projectData -is [hashtable]) {
                                    $project = [PmcProject]::FromLegacyFormat($projectData)
                                    $script:Data.Projects.Add($project)
                                }
                            }
                        }
                        Write-Log -Level Debug -Message "Re-hydrated $($script:Data.Projects.Count) projects as PmcProject objects"
                    }
                    
                    # AI: Load other data structures as-is for now
                    foreach ($key in @('TimeEntries', 'ActiveTimers', 'TodoTemplates', 'Settings', 'time_entries', 'timers')) {
                        if ($loadedData.ContainsKey($key)) {
                            $script:Data[$key] = $loadedData[$key]
                        }
                    }
                    
                    # Update global data reference
                    $global:Data = $script:Data
                    
                    Write-Log -Level Info -Message "Data loaded successfully from disk"
                } else {
                    Write-Log -Level Warning -Message "Invalid data format in file, using defaults"
                    $global:Data = $script:Data
                }
            } catch {
                Write-Log -Level Error -Message "Failed to parse data file: $_"
                Write-Log -Level Info -Message "Using default data structure"
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
    Saves application data to disk
    
    .DESCRIPTION
    Persists the current data state to disk with automatic backup rotation
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.SaveData" -Context "Saving unified data to disk" -ScriptBlock {
        # Create backup if file exists
        if (Test-Path $script:DataPath) {
            $backupName = "pmc-data_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date)
            $backupFilePath = Join-Path $script:BackupPath $backupName
            Copy-Item -Path $script:DataPath -Destination $backupFilePath -Force
            
            # Rotate backups
            $backups = Get-ChildItem -Path $script:BackupPath -Filter "pmc-data_*.json" | 
                       Sort-Object LastWriteTime -Descending
            
            if ($backups.Count -gt $script:Data.Settings.BackupCount) {
                $backups | Select-Object -Skip $script:Data.Settings.BackupCount | Remove-Item -Force
            }
        }
        
        # AI: Convert strongly-typed objects to legacy format for JSON serialization
        $dataToSave = @{
            Tasks = @($script:Data.Tasks | ForEach-Object { $_.ToLegacyFormat() })
            Projects = @{}  # AI: Convert back to hashtable format for compatibility
            TimeEntries = $script:Data.TimeEntries
            ActiveTimers = $script:Data.ActiveTimers
            TodoTemplates = $script:Data.TodoTemplates
            Settings = $script:Data.Settings
            time_entries = $script:Data.time_entries
            timers = $script:Data.timers
        }
        
        # AI: Rebuild Projects hashtable keyed by project key
        foreach ($project in $script:Data.Projects) {
            $dataToSave.Projects[$project.Key] = $project.ToLegacyFormat()
        }
        
        # Save current data
        $dataToSave | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:DataPath -Encoding UTF8
        $script:LastSaveTime = Get-Date
        $script:DataModified = $false
        
        Write-Log -Level Debug -Message "Data saved successfully"
    }
}

#region Task Management Functions

function Add-PmcTask {
    <#
    .SYNOPSIS
    Creates a new task
    
    .DESCRIPTION
    Adds a new task to the data store and publishes a Tasks.Changed event
    
    .PARAMETER Title
    The title of the task (required)
    
    .PARAMETER Description
    The task description
    
    .PARAMETER Priority
    Task priority: low, medium, or high
    
    .PARAMETER Category
    Task category/project name
    
    .PARAMETER DueDate
    Task due date
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,
        
        [string]$Description = "",
        
        [ValidateSet("low", "medium", "high")]
        [string]$Priority = "medium",
        
        [string]$Category = "General",
        
        [string]$DueDate = ""
    )
    
    Invoke-WithErrorHandling -Component "DataManager.AddTask" -Context "Adding new task to data store" -ScriptBlock {
        # AI: Input validation
        if ([string]::IsNullOrWhiteSpace($Title)) {
            throw [StateMutationException]::new("Task title cannot be empty", @{ Title = $Title })
        }
        
        # AI: Convert string priority to enum
        $taskPriority = switch ($Priority.ToLower()) {
            "low" { [TaskPriority]::Low }
            "medium" { [TaskPriority]::Medium }
            "high" { [TaskPriority]::High }
            default { [TaskPriority]::Medium }
        }
        
        # AI: Create new task using class constructor
        $newTask = [PmcTask]::new($Title, $Description, $taskPriority, $Category)
        
        # AI: Set due date if provided
        if ($DueDate -and $DueDate -ne "N/A") {
            try {
                $newTask.DueDate = [datetime]::Parse($DueDate)
            } catch {
                Write-Log -Level Warning -Message "Invalid due date format: $DueDate"
                $newTask.DueDate = $null
            }
        }
        
        # AI: Add to strongly-typed task list
        $script:Data.Tasks.Add($newTask)
        $script:DataModified = $true
        
        Write-Log -Level Info -Message "Created task '$($newTask.Title)' with ID $($newTask.Id)"
        
        # Auto-save if enabled
        if ($script:Data.Settings.AutoSave) {
            Save-UnifiedData
        }
        
        # AI: Publish event for UI refresh
        Publish-Event -EventName "Tasks.Changed" -Data @{
            Action = "Created"
            TaskId = $newTask.Id
            Task = $newTask
        }
        
        return $newTask
    }
}

function Update-PmcTask {
    <#
    .SYNOPSIS
    Updates an existing task
    
    .DESCRIPTION
    Modifies task properties and publishes a Tasks.Changed event
    
    .PARAMETER Task
    The PmcTask object to update (required)
    
    .PARAMETER Title
    New task title
    
    .PARAMETER Description
    New task description
    
    .PARAMETER Priority
    New task priority
    
    .PARAMETER Category
    New task category
    
    .PARAMETER DueDate
    New due date
    
    .PARAMETER Completed
    Task completion status
    
    .PARAMETER Progress
    Task progress percentage (0-100)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Task,
        
        [string]$Title,
        
        [string]$Description,
        
        [ValidateSet("low", "medium", "high")]
        [string]$Priority,
        
        [string]$Category,
        
        [string]$DueDate,
        
        [bool]$Completed,
        
        [ValidateRange(0, 100)]
        [int]$Progress
    )
    
    Invoke-WithErrorHandling -Component "DataManager.UpdateTask" -Context "Updating existing task" -ScriptBlock {
        # AI: FIX - Runtime type validation since we removed compile-time type checking
        if (-not ($Task.PSObject.TypeNames -contains 'PmcTask')) {
            throw [ArgumentException]::new("Task parameter must be a PmcTask object")
        }
        
        # AI: Find task in list to ensure we're updating the managed instance
        $managedTask = $script:Data.Tasks | Where-Object { $_.Id -eq $Task.Id } | Select-Object -First 1
        
        if (-not $managedTask) {
            throw [StateMutationException]::new("Task not found in data store", @{ TaskId = $Task.Id })
        }
        
        $updatedFields = @()
        
        # AI: Update task properties using proper object properties
        if ($PSBoundParameters.ContainsKey('Title') -and $Title) { 
            $managedTask.Title = $Title.Trim()
            $updatedFields += "Title"
        }
        if ($PSBoundParameters.ContainsKey('Description')) { 
            $managedTask.Description = $Description
            $updatedFields += "Description"
        }
        if ($PSBoundParameters.ContainsKey('Priority')) {
            $managedTask.Priority = switch ($Priority.ToLower()) {
                "low" { [TaskPriority]::Low }
                "medium" { [TaskPriority]::Medium }
                "high" { [TaskPriority]::High }
                default { [TaskPriority]::Medium }
            }
            $updatedFields += "Priority"
        }
        if ($PSBoundParameters.ContainsKey('Category')) { 
            $managedTask.ProjectKey = $Category
            $managedTask.Category = $Category  # AI: Maintain backward compatibility
            $updatedFields += "Category"
        }
        if ($PSBoundParameters.ContainsKey('DueDate')) {
            if ($DueDate -and $DueDate -ne "N/A") {
                try {
                    $managedTask.DueDate = [datetime]::Parse($DueDate)
                } catch {
                    Write-Log -Level Warning -Message "Invalid due date format: $DueDate"
                    $managedTask.DueDate = $null
                }
            } else {
                $managedTask.DueDate = $null
            }
            $updatedFields += "DueDate"
        }
        if ($PSBoundParameters.ContainsKey('Progress')) {
            # AI: Use class method which handles status updates
            $managedTask.UpdateProgress($Progress)
            $updatedFields += "Progress"
        }
        if ($PSBoundParameters.ContainsKey('Completed')) {
            if ($Completed) {
                $managedTask.Complete()
            } else {
                $managedTask.Status = [TaskStatus]::Pending
                $managedTask.Completed = $false
                $managedTask.Progress = 0
            }
            $updatedFields += "Completed"
        }
        
        $managedTask.UpdatedAt = [datetime]::Now
        $script:DataModified = $true
        
        Write-Log -Level Info -Message "Updated task $($managedTask.Id) - Fields: $($updatedFields -join ', ')"
        
        # Auto-save if enabled
        if ($script:Data.Settings.AutoSave) {
            Save-UnifiedData
        }
        
        # AI: Publish event for UI refresh
        Publish-Event -EventName "Tasks.Changed" -Data @{
            Action = "Updated"
            TaskId = $managedTask.Id
            Task = $managedTask
            UpdatedFields = $updatedFields
        }
        
        return $managedTask
    }
}

function Remove-PmcTask {
    <#
    .SYNOPSIS
    Removes a task from the data store
    
    .DESCRIPTION
    Deletes a task and publishes a Tasks.Changed event
    
    .PARAMETER Task
    The PmcTask object to remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Task
    )
    
    Invoke-WithErrorHandling -Component "DataManager.RemoveTask" -Context "Removing task from data store" -ScriptBlock {
        # AI: FIX - Runtime type validation since we removed compile-time type checking
        if (-not ($Task.PSObject.TypeNames -contains 'PmcTask')) {
            throw [ArgumentException]::new("Task parameter must be a PmcTask object")
        }
        
        # AI: Find and remove task from strongly-typed list
        $taskToRemove = $script:Data.Tasks | Where-Object { $_.Id -eq $Task.Id } | Select-Object -First 1
        
        if ($taskToRemove) {
            $script:Data.Tasks.Remove($taskToRemove) | Out-Null
            $script:DataModified = $true
            
            Write-Log -Level Info -Message "Deleted task $($Task.Id)"
            
            # Auto-save if enabled
            if ($script:Data.Settings.AutoSave) {
                Save-UnifiedData
            }
            
            # AI: Publish event for UI refresh
            Publish-Event -EventName "Tasks.Changed" -Data @{
                Action = "Deleted"
                TaskId = $Task.Id
                Task = $Task
            }
            
            return $true
        } else {
            Write-Log -Level Warning -Message "Task not found with ID $($Task.Id)"
            return $false
        }
    }
}

function Get-PmcTasks {
    <#
    .SYNOPSIS
    Retrieves tasks from the data store
    
    .DESCRIPTION
    Returns all tasks or filtered tasks based on criteria
    
    .PARAMETER Completed
    Filter by completion status
    
    .PARAMETER Priority
    Filter by priority level
    
    .PARAMETER Category
    Filter by category/project
    #>
    [CmdletBinding()]
    param(
        [bool]$Completed,
        
        [ValidateSet("low", "medium", "high")]
        [string]$Priority,
        
        [string]$Category
    )
    
    Invoke-WithErrorHandling -Component "DataManager.GetTasks" -Context "Retrieving tasks from data store" -ScriptBlock {
        # AI: Start with all tasks from strongly-typed list
        $tasks = $script:Data.Tasks
        
        # Apply filters if specified
        if ($PSBoundParameters.ContainsKey('Completed')) {
            $tasks = $tasks | Where-Object { $_.Completed -eq $Completed }
        }
        
        if ($Priority) {
            # AI: Convert string to enum for comparison
            $priorityEnum = switch ($Priority.ToLower()) {
                "low" { [TaskPriority]::Low }
                "medium" { [TaskPriority]::Medium }
                "high" { [TaskPriority]::High }
            }
            $tasks = $tasks | Where-Object { $_.Priority -eq $priorityEnum }
        }
        
        if ($Category) {
            $tasks = $tasks | Where-Object { $_.ProjectKey -eq $Category -or $_.Category -eq $Category }
        }
        
        # AI: Return as array to maintain compatibility
        return @($tasks)
    }
}

#endregion

#region Project Management Functions

function Get-PmcProjects {
    <#
    .SYNOPSIS
    Retrieves all projects from the data store
    
    .DESCRIPTION
    Returns all PmcProject objects as an array
    #>
    [CmdletBinding()]
    param()
    
    # AI: Return projects from strongly-typed list as array
    return @($script:Data.Projects)
}

function Get-PmcProject {
    <#
    .SYNOPSIS
    Retrieves a specific project by key
    
    .PARAMETER Key
    The project key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    # AI: Find project in list by key
    return $script:Data.Projects | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
}

function Add-PmcProject {
    <#
    .SYNOPSIS
    Adds a new project to the data store
    
    .PARAMETER Project
    The PmcProject object to add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Project
    )
    
    Invoke-WithErrorHandling -Component "DataManager.AddProject" -Context "Adding new project to data store" -ScriptBlock {
        # AI: FIX - Runtime type validation since we removed compile-time type checking
        if (-not ($Project.PSObject.TypeNames -contains 'PmcProject')) {
            throw [ArgumentException]::new("Project parameter must be a PmcProject object")
        }
        
        # AI: Check if project with same key already exists
        $existing = $script:Data.Projects | Where-Object { $_.Key -eq $Project.Key } | Select-Object -First 1
        
        if ($existing) {
            throw [StateMutationException]::new("Project with key '$($Project.Key)' already exists", @{ ProjectKey = $Project.Key })
        }
        
        # AI: Add to strongly-typed project list
        $script:Data.Projects.Add($Project)
        $script:DataModified = $true
        
        Write-Log -Level Info -Message "Created project '$($Project.Name)' with key $($Project.Key)"
        
        # Auto-save if enabled
        if ($script:Data.Settings.AutoSave) {
            Save-UnifiedData
        }
        
        # AI: Publish event for UI refresh
        Publish-Event -EventName "Projects.Changed" -Data @{
            Action = "Created"
            ProjectKey = $Project.Key
            Project = $Project
        }
        
        return $Project
    }
}

#endregion

#region DataManager Class Definition

# AI: FIX - Maintain class-based interface for compatibility with existing code
# AI: Removed type annotations from method signatures to avoid PowerShell 5.1 parsing issues
class DataManager {
    hidden [hashtable] $DataStore
    hidden [string] $DataFilePath
    hidden [bool] $AutoSaveEnabled = $true
    
    DataManager() {
        $this.DataStore = $script:Data
        $global:Data = $script:Data # Ensure global state is set
        $this.DataFilePath = $script:DataPath
        $this.AutoSaveEnabled = $this.DataStore.Settings.AutoSave
    }

    [void] LoadData() {
        Load-UnifiedData
    }

    [void] SaveData() {
        Save-UnifiedData
    }

    # AI: FIX - Removed [PmcTask] and [TaskPriority] type annotations to fix parsing errors
    [object] AddTask([string]$Title, [string]$Description, [object]$Priority, [string]$ProjectKey) {
        $priorityString = if ($Priority -is [string]) { $Priority } else { $Priority.ToString() }
        return Add-PmcTask -Title $Title -Description $Description -Priority $priorityString -Category $ProjectKey
    }
    
    # AI: FIX - Removed [PmcTask[]] type annotation
    [object[]] GetTasks() {
        return @($this.DataStore.Tasks)
    }
    
    # AI: FIX - Removed [PmcProject[]] type annotation
    [object[]] GetProjects() {
        return @($this.DataStore.Projects)
    }
}

#endregion

#region Private Helper Functions

function Initialize-DataEventHandlers {
    <#
    .SYNOPSIS
    Sets up event handlers for data operations
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.InitializeEventHandlers" -Context "Initializing data event handlers" -ScriptBlock {
        # AI: Subscribe to refresh request events for backward compatibility
        $null = Subscribe-Event -EventName "Tasks.RefreshRequested" -Handler {
            param($EventData)
            
            # Simply publish the current task data
            Publish-Event -EventName "Tasks.Changed" -Data @{
                Action = "Refreshed"
                Tasks = @($script:Data.Tasks)
            }
        }
        
        Write-Log -Level Debug -Message "Data event handlers initialized"
    }
}

#endregion

#region Public Initialization Function

function Initialize-DataManager {
    <#
    .SYNOPSIS
    Initializes the data manager service and returns a DataManager instance
    
    .DESCRIPTION
    This function loads existing data, sets up event handlers, and returns
    a DataManager service instance for use by the application.
    #>
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component "DataManager.Initialize" -Context "Initializing data manager service" -ScriptBlock {
        Write-Log -Level Info -Message "Initializing DataManager service"
        
        # Load existing data
        Load-UnifiedData
        
        # Initialize event handlers
        Initialize-DataEventHandlers
        
        # Create and return DataManager instance
        $dataManager = [DataManager]::new()
        
        Write-Log -Level Info -Message "DataManager service initialized successfully"
        
        return $dataManager
    }
}

#endregion

# Export public functions and classes
Export-ModuleMember -Function @(
    'Initialize-DataManager',
    'Add-PmcTask',
    'Update-PmcTask', 
    'Remove-PmcTask',
    'Get-PmcTasks',
    'Get-PmcProjects',
    'Get-PmcProject',
    'Add-PmcProject',
    'Save-UnifiedData',
    'Load-UnifiedData'
) -Variable @() -Alias @()