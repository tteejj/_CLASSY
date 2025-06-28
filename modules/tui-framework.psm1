# TUI Framework Integration Module - FIXED VERSION
# Contains fixed utility functions with resolved parameter binding issues.

$script:TuiAsyncJobs = @()

function global:Invoke-TuiMethod {
    <#
    .SYNOPSIS
    Safely invokes a method on a TUI component.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Component,

        [Parameter(Mandatory = $true)]
        [string]$MethodName,

        [Parameter()]
        [hashtable]$Arguments = @{}
    )

    # AI: Defensive check for null component to prevent errors.
    if ($null -eq $Component) { return }
    
    # AI: Check if the method key exists and is a scriptblock before attempting invocation.
    # This prevents "The term '...' is not recognized" errors for optional methods.
    if (-not $Component.ContainsKey($MethodName)) { return }
    $method = $Component[$MethodName]
    if ($null -eq $method -or $method -isnot [scriptblock]) {
        return
    }

    # Add the component itself as the 'self' parameter for convenience within the method.
    $Arguments['self'] = $Component

    Invoke-WithErrorHandling -Component "$($Component.Name ?? $Component.Type).$MethodName" -Context "Invoking component method" -ScriptBlock {
        # Use splatting with the @ operator for robust parameter passing.
        & $method @Arguments
    } -AdditionalData @{ Component = $Component.Name; Method = $MethodName } -ErrorHandler {
        param($Exception)
        # Log the error but do not re-throw, allowing the UI to remain responsive.
        Write-Log -Level Error -Message "Error invoking method '$($Exception.Context.Method)' on component '$($Exception.Context.Component)': $($Exception.Message)" -Data $Exception.Context
        Request-TuiRefresh
    }
}

function global:Initialize-TuiFramework {
    <#
    .SYNOPSIS
    Initializes the TUI framework.
    #>
    Invoke-WithErrorHandling -Component "TuiFramework.Initialize" -Context "Initializing framework" -ScriptBlock {
        # Ensure engine is initialized before the framework.
        if (-not $global:TuiState) {
            throw "TUI Engine must be initialized before the TUI Framework."
        }
        Write-Log -Level Info -Message "TUI Framework initialized." -Data @{ Component = "TuiFramework.Initialize" }
    }
}

function global:Invoke-TuiAsync {
    <#
    .SYNOPSIS
    Executes a script block asynchronously with proper job management.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [string]$JobName = "TuiAsyncJob_$(Get-Random)",
        
        [Parameter()]
        [hashtable]$ArgumentList = @{}
    )
    
    Invoke-WithErrorHandling -Component "TuiFramework.Async" -Context "Starting async job: $JobName" -ScriptBlock {
        # Start the job
        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Name $JobName
        
        # Track the job
        $script:TuiAsyncJobs += $job
        
        Write-Log -Level Debug -Message "Started async job: $JobName" -Data @{ 
            Component = "TuiFramework.Async"; 
            JobId = $job.Id; 
            JobName = $JobName 
        }
        
        return $job
    }
}

function global:Get-TuiAsyncResults {
    <#
    .SYNOPSIS
    Checks for completed async jobs and returns their results.
    #>
    param(
        [Parameter()]
        [switch]$RemoveCompleted = $true
    )
    
    Invoke-WithErrorHandling -Component "TuiFramework.AsyncResults" -Context "Checking async job results" -ScriptBlock {
        $results = @()
        $completedJobs = @()
        
        foreach ($job in $script:TuiAsyncJobs) {
            if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
                $result = @{
                    JobId = $job.Id
                    JobName = $job.Name
                    State = $job.State
                    Output = if ($job.State -eq 'Completed') { Receive-Job -Job $job } else { $null }
                    Error = if ($job.State -eq 'Failed') { $job.ChildJobs[0].JobStateInfo.Reason } else { $null }
                }
                
                $results += $result
                $completedJobs += $job
                
                Write-Log -Level Debug -Message "Async job completed: $($job.Name)" -Data @{ 
                    Component = "TuiFramework.AsyncResults"; 
                    JobId = $job.Id; 
                    State = $job.State 
                }
            }
        }
        
        # Remove completed jobs if requested
        if ($RemoveCompleted -and $completedJobs.Count -gt 0) {
            foreach ($job in $completedJobs) {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                $script:TuiAsyncJobs = $script:TuiAsyncJobs | Where-Object { $_.Id -ne $job.Id }
            }
        }
        
        return $results
    }
}

function global:Stop-AllTuiAsyncJobs {
    <#
    .SYNOPSIS
    Stops and removes all running TUI async jobs.
    #>
    Invoke-WithErrorHandling -Component "TuiFramework.StopAsync" -Context "Stopping all async jobs" -ScriptBlock {
        foreach ($job in $script:TuiAsyncJobs) {
            try {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                Write-Log -Level Debug -Message "Stopped async job: $($job.Name)" -Data @{ 
                    Component = "TuiFramework.StopAsync"; 
                    JobId = $job.Id 
                }
            }
            catch {
                Write-Log -Level Warning -Message "Failed to stop job $($job.Name): $_" -Data @{ 
                    Component = "TuiFramework.StopAsync"; 
                    JobId = $job.Id; 
                    Error = $_.Exception.Message 
                }
            }
        }
        
        $script:TuiAsyncJobs = @()
        Write-Log -Level Info -Message "All TUI async jobs stopped" -Data @{ Component = "TuiFramework.StopAsync" }
    }
}

function global:Request-TuiRefresh {
    <#
    .SYNOPSIS
    Requests a UI refresh to update the display.
    #>
    if ($global:TuiState -and $global:TuiState.RequestRefresh) {
        & $global:TuiState.RequestRefresh
    }
    else {
        # Publish event as fallback
        Publish-Event -EventName "TUI.RefreshRequested" -Data @{ Timestamp = Get-Date }
    }
}

function global:Get-TuiState {
    <#
    .SYNOPSIS
    Gets the current TUI state object.
    #>
    return $global:TuiState
}

# AI: Helper function to safely validate TUI state
function global:Test-TuiState {
    <#
    .SYNOPSIS
    Validates that the TUI state is properly initialized.
    #>
    param(
        [Parameter()]
        [switch]$ThrowOnError
    )
    
    $isValid = $null -ne $global:TuiState -and 
               $null -ne $global:TuiState.IsRunning -and
               $null -ne $global:TuiState.CurrentScreen
    
    if (-not $isValid -and $ThrowOnError) {
        throw "TUI state is not properly initialized. Call Initialize-TuiEngine first."
    }
    
    return $isValid
}

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-TuiMethod',
    'Initialize-TuiFramework', 
    'Invoke-TuiAsync',
    'Get-TuiAsyncResults',
    'Stop-AllTuiAsyncJobs',
    'Request-TuiRefresh',
    'Get-TuiState',
    'Test-TuiState'
)