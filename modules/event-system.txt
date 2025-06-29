# Event System Module
# Provides pub/sub event functionality for decoupled communication

$script:EventHandlers = @{}
$script:EventHistory = [System.Collections.Generic.List[object]]::new()
$script:MaxEventHistory = 100

function Initialize-EventSystem {
    <# .SYNOPSIS Initializes the event system for the application #>
    Invoke-WithErrorHandling -Component "EventSystem.Initialize" -Context "Initializing event system" -ScriptBlock {
        $script:EventHandlers = @{}
        $script:EventHistory = [System.Collections.Generic.List[object]]::new()
        Write-Verbose "Event system initialized"
    }
}

function Publish-Event {
    <#
    .SYNOPSIS Publishes an event to all registered handlers
    .PARAMETER EventName The name of the event to publish
    .PARAMETER Data Optional data to pass to event handlers
    #>
    param(
        [Parameter(Mandatory)] [string]$EventName,
        [Parameter()] [hashtable]$Data = @{}
    )
    Invoke-WithErrorHandling -Component "EventSystem.PublishEvent" -Context "Publishing event '$EventName'" -ScriptBlock {
        $eventRecord = @{ EventName = $EventName; Data = $Data; Timestamp = Get-Date }
        
        $script:EventHistory.Add($eventRecord)
        if ($script:EventHistory.Count -gt $script:MaxEventHistory) { $script:EventHistory.RemoveAt(0) }
        
        if ($script:EventHandlers.ContainsKey($EventName)) {
            foreach ($handler in $script:EventHandlers[$EventName]) {
                try {
                    $eventData = @{ EventName = $EventName; Data = $Data; Timestamp = $eventRecord.Timestamp }
                    & $handler.ScriptBlock -EventData $eventData
                } catch {
                    Write-Log -Level Warning -Message "Error in event handler for '$EventName' (ID: $($handler.HandlerId)): $_"
                }
            }
        }
        Write-Verbose "Published event: $EventName"
    } -AdditionalData @{ EventName = $EventName; EventData = $Data }
}

function Subscribe-Event {
    <#
    .SYNOPSIS Subscribes to an event with a handler
    .PARAMETER EventName The name of the event to subscribe to
    .PARAMETER Handler The script block to execute
    .PARAMETER HandlerId Optional unique identifier for the handler
    .PARAMETER Source Optional source component ID for cleanup tracking
    #>
    param(
        [Parameter(Mandatory)] [string]$EventName,
        [Parameter(Mandatory)] [scriptblock]$Handler,
        [Parameter()] [string]$HandlerId = [Guid]::NewGuid().ToString(),
        [Parameter()] [string]$Source
    )
    return Invoke-WithErrorHandling -Component "EventSystem.SubscribeEvent" -Context "Subscribing to event '$EventName'" -ScriptBlock {
        if (-not $script:EventHandlers.ContainsKey($EventName)) { $script:EventHandlers[$EventName] = @() }
        
        $handlerInfo = @{ HandlerId = $HandlerId; ScriptBlock = $Handler; SubscribedAt = Get-Date; Source = $Source }
        $script:EventHandlers[$EventName] += $handlerInfo
        
        Write-Verbose "Subscribed to event: $EventName (Handler: $HandlerId)"
        return $HandlerId
    } -AdditionalData @{ EventName = $EventName; HandlerId = $HandlerId; Source = $Source }
}

function Unsubscribe-Event {
    <#
    .SYNOPSIS Unsubscribes from an event
    .PARAMETER EventName The name of the event (optional if HandlerId is provided)
    .PARAMETER HandlerId The unique identifier of the handler to remove
    #>
    param(
        [Parameter()] [string]$EventName,
        [Parameter(Mandatory)] [string]$HandlerId
    )
    Invoke-WithErrorHandling -Component "EventSystem.UnsubscribeEvent" -Context "Unsubscribing from event '$EventName' (Handler: $HandlerId)" -ScriptBlock {
        if ($EventName) {
            if ($script:EventHandlers.ContainsKey($EventName)) {
                $script:EventHandlers[$EventName] = @($script:EventHandlers[$EventName] | Where-Object { $_.HandlerId -ne $HandlerId })
                if ($script:EventHandlers[$EventName].Count -eq 0) { $script:EventHandlers.Remove($EventName) }
                Write-Verbose "Unsubscribed from event: $EventName (Handler: $HandlerId)"
            }
        } else {
            $found = $false
            foreach ($eventKey in @($script:EventHandlers.Keys)) {
                $handlers = $script:EventHandlers[$eventKey]
                $newHandlers = @($handlers | Where-Object { $_.HandlerId -ne $HandlerId })
                if ($newHandlers.Count -lt $handlers.Count) {
                    $found = $true
                    $script:EventHandlers[$eventKey] = if ($newHandlers.Count -eq 0) { $script:EventHandlers.Remove($eventKey) } else { $newHandlers }
                    Write-Verbose "Unsubscribed from event: $eventKey (Handler: $HandlerId)"; break
                }
            }
            if (-not $found) { Write-Warning "Handler ID not found: $HandlerId" }
        }
    } -AdditionalData @{ EventName = $EventName; HandlerId = $HandlerId }
}

function Get-EventHandlers {
    <# .SYNOPSIS Gets all registered event handlers #>
    param([Parameter()] [string]$EventName)
    return Invoke-WithErrorHandling -Component "EventSystem.GetEventHandlers" -Context "Getting event handlers for '$EventName'" -ScriptBlock {
        if ($EventName) { return $script:EventHandlers[$EventName] ?? @() }
        else { return $script:EventHandlers }
    }
}

function Clear-EventHandlers {
    <# .SYNOPSIS Clears all event handlers for a specific event or all events #>
    param([Parameter()] [string]$EventName)
    Invoke-WithErrorHandling -Component "EventSystem.ClearEventHandlers" -Context "Clearing event handlers for '$EventName'" -ScriptBlock {
        if ($EventName) { if ($script:EventHandlers.ContainsKey($EventName)) { $script:EventHandlers.Remove($EventName); Write-Verbose "Cleared handlers for event: $EventName" } } 
        else { $script:EventHandlers = @{}; Write-Verbose "Cleared all event handlers" }
    }
}

function Get-EventHistory {
    <# .SYNOPSIS Gets the event history #>
    param([Parameter()] [string]$EventName, [Parameter()] [int]$Last = 0)
    return Invoke-WithErrorHandling -Component "EventSystem.GetEventHistory" -Context "Getting event history for '$EventName'" -ScriptBlock {
        $history = $script:EventHistory
        if ($EventName) { $history = $history | Where-Object { $_.EventName -eq $EventName } }
        if ($Last -gt 0) { $history = $history | Select-Object -Last $Last }
        return $history
    }
}

function Remove-ComponentEventHandlers {
    <# .SYNOPSIS Removes all event handlers associated with a specific component #>
    param([Parameter(Mandatory)] [string]$ComponentId)
    Invoke-WithErrorHandling -Component "EventSystem.RemoveComponentEventHandlers" -Context "Removing event handlers for component '$ComponentId'" -ScriptBlock {
        $removedCount = 0
        foreach ($eventName in @($script:EventHandlers.Keys)) {
            $initialCount = $script:EventHandlers[$eventName].Count
            $script:EventHandlers[$eventName] = @($script:EventHandlers[$eventName] | Where-Object { $_.Source -ne $ComponentId })
            $removedCount += $initialCount - $script:EventHandlers[$eventName].Count
            if ($script:EventHandlers[$eventName].Count -eq 0) { $script:EventHandlers.Remove($eventName) }
        }
        Write-Verbose "Removed $removedCount event handlers for component: $ComponentId"
    }
}

Export-ModuleMember -Function 'Initialize-EventSystem', 'Publish-Event', 'Subscribe-Event', 'Unsubscribe-Event', 'Get-EventHandlers', 'Clear-EventHandlers', 'Get-EventHistory', 'Remove-ComponentEventHandlers'