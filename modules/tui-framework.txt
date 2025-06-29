# TUI Framework Integration Module
# Contains utility functions for interacting with the TUI engine and components.

$script:TuiAsyncJobs = @()

function Invoke-TuiMethod {
    <# .SYNOPSIS Safely invokes a method on a TUI component. #>
    param(
        [Parameter(Mandatory)] [hashtable]$Component,
        [Parameter(Mandatory)] [string]$MethodName,
        [Parameter()] [hashtable]$Arguments = @{}
    )
    if (-not $Component) { return }
    $method = $Component[$MethodName]
    if (-not ($method -is [scriptblock])) { return }

    $Arguments['self'] = $Component
    Invoke-WithErrorHandling -Component "$($Component.Name ?? $Component.Type).$MethodName" -Context "Invoking component method" -ScriptBlock { & $method @Arguments }
}

function Initialize-TuiFramework {
    Invoke-WithErrorHandling -Component "TuiFramework.Initialize" -Context "Initializing framework" -ScriptBlock {
        if (-not $global:TuiState) { throw "TUI Engine must be initialized before the TUI Framework." }
        Write-Log -Level Info -Message "TUI Framework initialized."
    }
}

function Invoke-TuiAsync {
    <# .SYNOPSIS Executes a script block asynchronously with job management. #>
    param(
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [string]$JobName = "TuiAsyncJob_$(Get-Random)",
        [hashtable]$ArgumentList = @{}
    )
    Invoke-WithErrorHandling -Component "TuiFramework.Async" -Context "Starting async job: $JobName" -ScriptBlock {
        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Name $JobName
        $script:TuiAsyncJobs += $job
        Write-Log -Level Debug -Message "Started async job: $JobName" -Data @{ JobId = $job.Id }
        return $job
    }
}

function Get-TuiAsyncResults {
    <# .SYNOPSIS Checks for completed async jobs and returns their results. #>
    param([switch]$RemoveCompleted = $true)
    Invoke-WithErrorHandling -Component "TuiFramework.AsyncResults" -Context "Checking async job results" -ScriptBlock {
        $results = @()
        $completedJobs = $script:TuiAsyncJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
        
        foreach ($job in $completedJobs) {
            $results += @{
                JobId = $job.Id; JobName = $job.Name; State = $job.State
                Output = if ($job.State -eq 'Completed') { Receive-Job -Job $job } else { $null }
                Error = if ($job.State -eq 'Failed') { $job.ChildJobs[0].JobStateInfo.Reason } else { $null }
            }
            Write-Log -Level Debug -Message "Async job completed: $($job.Name)" -Data @{ JobId = $job.Id; State = $job.State }
        }
        
        if ($RemoveCompleted -and $completedJobs.Count -gt 0) {
            foreach ($job in $completedJobs) {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                $script:TuiAsyncJobs = $script:TuiAsyncJobs | Where-Object { $_.Id -ne $job.Id }
            }
        }
        return $results
    }
}

function Stop-AllTuiAsyncJobs {
    Invoke-WithErrorHandling -Component "TuiFramework.StopAsync" -Context "Stopping all async jobs" -ScriptBlock {
        foreach ($job in $script:TuiAsyncJobs) {
            try {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                Write-Log -Level Debug -Message "Stopped async job: $($job.Name)"
            } catch {
                Write-Log -Level Warning -Message "Failed to stop job $($job.Name): $_"
            }
        }
        $script:TuiAsyncJobs = @()
        Write-Log -Level Info -Message "All TUI async jobs stopped."
    }
}

function Request-TuiRefresh {
    if ($global:TuiState.RequestRefresh) { & $global:TuiState.RequestRefresh }
    else { Publish-Event -EventName "TUI.RefreshRequested" }
}

function Get-TuiState { return $global:TuiState }

function Test-TuiState {
    param([switch]$ThrowOnError)
    $isValid = $global:TuiState -and $global:TuiState.Running -and $global:TuiState.CurrentScreen
    if (-not $isValid -and $ThrowOnError) { throw "TUI state is not properly initialized. Call Initialize-TuiEngine first." }
    return $isValid
}

Export-ModuleMember -Function 'Invoke-TuiMethod', 'Initialize-TuiFramework', 'Invoke-TuiAsync', 'Get-TuiAsyncResults', 'Stop-AllTuiAsyncJobs', 'Request-TuiRefresh', 'Get-TuiState', 'Test-TuiState'