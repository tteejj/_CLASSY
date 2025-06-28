# ==============================================================================
# PMC Terminal v5 - Core Data Models
# Defines all core business entity classes with built-in validation.
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Enums

enum TaskStatus {
    Pending
    InProgress
    Completed
    Cancelled
}

enum TaskPriority {
    Low
    Medium
    High
}

enum BillingType {
    Billable
    NonBillable
}

#endregion

#region Base Validation Class
class ValidationBase {
    static [void] ValidateNotEmpty([string]$value, [string]$parameterName) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw [System.ArgumentException]::new("Parameter '$($parameterName)' cannot be null or empty.")
        }
    }
}
#endregion

#region Core Model Classes

class PmcTask : ValidationBase {
    # --- Properties ---
    [string]$Id
    [string]$Title
    [string]$Description
    [TaskStatus]$Status = [TaskStatus]::Pending
    [TaskPriority]$Priority = [TaskPriority]::Medium
    [string]$ProjectKey = "General"
    [string]$Category  # For backward compatibility with older data formats
    [datetime]$CreatedAt
    [datetime]$UpdatedAt
    [Nullable[datetime]]$DueDate
    [string[]]$Tags = @()
    [int]$Progress = 0
    [bool]$Completed = $false

    # --- Constructors ---
    PmcTask() {
        $this.Id = [Guid]::NewGuid().ToString()
        $this.CreatedAt = [datetime]::Now
        $this.UpdatedAt = [datetime]::Now
    }

    PmcTask([string]$title) : base() {
        [ValidationBase]::ValidateNotEmpty($title, "Title")
        $this.Title = $title
    }

    PmcTask([string]$title, [string]$description, [TaskPriority]$priority, [string]$projectKey) : base() {
        [ValidationBase]::ValidateNotEmpty($title, "Title")
        $this.Title = $title
        $this.Description = $description
        $this.Priority = $priority
        $this.ProjectKey = $projectKey
        $this.Category = $projectKey # Set for backward compatibility
    }

    # --- Methods ---
    [void] Complete() {
        $this.Status = [TaskStatus]::Completed
        $this.Completed = $true
        $this.Progress = 100
        $this.UpdatedAt = [datetime]::Now
    }

    [void] UpdateProgress([int]$newProgress) {
        if ($newProgress -lt 0 -or $newProgress -gt 100) {
            throw "Progress must be between 0 and 100."
        }
        $this.Progress = $newProgress
        $this.Status = if ($newProgress -eq 100) { [TaskStatus]::Completed }
                      elseif ($newProgress -gt 0) { [TaskStatus]::InProgress }
                      else { [TaskStatus]::Pending }
        $this.Completed = ($this.Status -eq [TaskStatus]::Completed)
        $this.UpdatedAt = [datetime]::Now
    }
    
    [string] GetDueDateString() {
        return if ($this.DueDate) { $this.DueDate.ToString("yyyy-MM-dd") } else { "N/A" }
    }

    # --- Serialization & Deserialization ---
    
    # Converts the object to a simple hashtable for JSON serialization
    [hashtable] ToLegacyFormat() {
        return @{
            id = $this.Id
            title = $this.Title
            description = $this.Description
            completed = $this.Completed
            priority = $this.Priority.ToString().ToLower()
            project = $this.ProjectKey
            due_date = if ($this.DueDate) { $this.GetDueDateString() } else { $null }
            created_at = $this.CreatedAt.ToString("o")
            updated_at = $this.UpdatedAt.ToString("o")
        }
    }

    # AI: Creates a PmcTask instance from an older, unstructured hashtable format.
    # This logic is now part of the class, centralizing all Task-related knowledge.
    static [PmcTask] FromLegacyFormat([hashtable]$legacyData) {
        $task = [PmcTask]::new()
        
        if ($legacyData.id) { $task.Id = $legacyData.id }
        if ($legacyData.title) { $task.Title = $legacyData.title }
        if ($legacyData.description) { $task.Description = $legacyData.description }
        
        if ($legacyData.priority) {
            $task.Priority = try { [TaskPriority]::$($legacyData.priority) } catch { [TaskPriority]::Medium }
        }
        
        # AI: PowerShell 5.1 compatible null-coalescing
        $projectKey = if ($legacyData.project) { $legacyData.project } 
                      elseif ($legacyData.Category) { $legacyData.Category } 
                      else { "General" }
        $task.ProjectKey = $projectKey
        $task.Category = $projectKey
        
        if ($legacyData.created_at) { $task.CreatedAt = try { [datetime]::Parse($legacyData.created_at) } catch { [datetime]::Now } }
        if ($legacyData.updated_at) { $task.UpdatedAt = try { [datetime]::Parse($legacyData.updated_at) } catch { [datetime]::Now } }
        if ($legacyData.due_date -and $legacyData.due_date -ne "N/A") { $task.DueDate = try { [datetime]::Parse($legacyData.due_date) } catch { $null } }
        
        if ($legacyData.completed -is [bool] -and $legacyData.completed) {
            $task.Complete()
        }
        
        return $task
    }
}

class PmcProject : ValidationBase {
    # --- Properties ---
    [string]$Key
    [string]$Name
    [string]$Client
    [BillingType]$BillingType = [BillingType]::NonBillable
    [double]$Rate = 0.0
    [double]$Budget = 0.0
    [bool]$Active = $true
    [datetime]$CreatedAt
    [datetime]$UpdatedAt

    # --- Constructors ---
    PmcProject() {
        $this.Key = ([Guid]::NewGuid().ToString().Split('-')[0]).ToUpper()
        $this.CreatedAt = [datetime]::Now
        $this.UpdatedAt = [datetime]::Now
    }

    PmcProject([string]$key, [string]$name) : base() {
        [ValidationBase]::ValidateNotEmpty($key, "Key")
        [ValidationBase]::ValidateNotEmpty($name, "Name")
        $this.Key = $key
        $this.Name = $name
    }
    
    # --- Serialization & Deserialization ---

    # Converts the object to a simple hashtable for JSON serialization
    [hashtable] ToLegacyFormat() {
        return @{
            Key = $this.Key
            Name = $this.Name
            Client = $this.Client
            BillingType = $this.BillingType.ToString()
            Rate = $this.Rate
            Budget = $this.Budget
            Active = $this.Active
            CreatedAt = $this.CreatedAt.ToString("o")
        }
    }

    # AI: Creates a PmcProject instance from an older, unstructured hashtable format.
    static [PmcProject] FromLegacyFormat([hashtable]$legacyData) {
        $project = [PmcProject]::new()
        
        if ($legacyData.Key) { $project.Key = $legacyData.Key }
        if ($legacyData.Name) { $project.Name = $legacyData.Name }
        if ($legacyData.Client) { $project.Client = $legacyData.Client }
        if ($legacyData.Rate) { $project.Rate = [double]$legacyData.Rate }
        if ($legacyData.Budget) { $project.Budget = [double]$legacyData.Budget }
        if ($legacyData.Active -is [bool]) { $project.Active = $legacyData.Active }
        
        if ($legacyData.BillingType) {
            $project.BillingType = try { [BillingType]::$($legacyData.BillingType) } catch { [BillingType]::NonBillable }
        }
        
        if ($legacyData.CreatedAt) { $project.CreatedAt = try { [datetime]::Parse($legacyData.CreatedAt) } catch { [datetime]::Now } }
        
        $project.UpdatedAt = $project.CreatedAt
        
        return $project
    }
}

#endregion

# --- Export Section ---
# AI: Classes and enums are automatically exported in PowerShell modules
# We only need to export any helper functions if they exist
Export-ModuleMember -Function * -Variable *