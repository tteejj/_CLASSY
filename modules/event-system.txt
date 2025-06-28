# Event System Module
# Provides pub/sub event functionality for decoupled communication

$script:EventHandlers = @{}
$script:EventHistory = @()
$script:MaxEventHistory = 100

function global:Initialize-EventSystem {
    <#
    .SYNOPSIS
    Initializes the event system for the application
    #>
    Invoke-WithErrorHandling -Component "EventSystem.Initialize" -Context "Initializing event system" -ScriptBlock {
        $script:EventHandlers = @{}
        $script:EventHistory = @()
        Write-Verbose "Event system initialized"
    }
}

function global:Publish-Event {
    <#
    .SYNOPSIS
    Publishes an event to all registered handlers
    
    .PARAMETER EventName
    The name of the event to publish
    
    .PARAMETER Data
    Optional data to pass to event handlers
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter()]
        [hashtable]$Data = @{}
    )
    Invoke-WithErrorHandling -Component "EventSystem.PublishEvent" -Context "Publishing event '$EventName'" -ScriptBlock {
        # Record event in history
        $eventRecord = @{
            EventName = $EventName
            Data = $Data
            Timestamp = Get-Date
        }
        
        $script:EventHistory += $eventRecord
        if ($script:EventHistory.Count -gt $script:MaxEventHistory) {
            $script:EventHistory = $script:EventHistory[-$script:MaxEventHistory..-1]
        }
        
        # Execute handlers
        if ($script:EventHandlers.ContainsKey($EventName)) {
            foreach ($handler in $script:EventHandlers[$EventName]) {
                try { # Internal try/catch for handler execution
                    $eventData = @{
                        EventName = $EventName
                        Data = $Data
                        Timestamp = $eventRecord.Timestamp
                    }
                    
                    & $handler.ScriptBlock -EventData $eventData
                } catch {
                    Write-Log -Level Warning -Message "Error in event handler for '$EventName' (Handler ID: $($handler.HandlerId)): $_" -Data @{ EventName = $EventName; HandlerId = $handler.HandlerId; Exception = $_ }
                }
            }
        }
        
        Write-Verbose "Published event: $EventName"
    } -AdditionalData @{ EventName = $EventName; EventData = $Data }
}

function global:Subscribe-Event {
    <#
    .SYNOPSIS
    Subscribes to an event with a handler
    
    .PARAMETER EventName
    The name of the event to subscribe to
    
    .PARAMETER Handler
    The script block to execute when the event is published
    
    .PARAMETER HandlerId
    Optional unique identifier for the handler
    
    .PARAMETER Source
    Optional source component ID for cleanup tracking
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Handler,
        
        [Parameter()]
        [string]$HandlerId = [Guid]::NewGuid().ToString(),
        
        [Parameter()]
        [string]$Source = $null
    )
    Invoke-WithErrorHandling -Component "EventSystem.SubscribeEvent" -Context "Subscribing to event '$EventName'" -ScriptBlock {
        if (-not $script:EventHandlers.ContainsKey($EventName)) {
            $script:EventHandlers[$EventName] = @()
        }
        
        $handlerInfo = @{
            HandlerId = $HandlerId
            ScriptBlock = $Handler
            SubscribedAt = Get-Date
            Source = $Source
        }
        
        $script:EventHandlers[$EventName] += $handlerInfo
        
        Write-Verbose "Subscribed to event: $EventName (Handler: $HandlerId)"
        
        # Only return handler ID, don't print it
        return $HandlerId
    } -AdditionalData @{ EventName = $EventName; HandlerId = $HandlerId; Source = $Source }
}

function global:Unsubscribe-Event {
    <#
    .SYNOPSIS
    Unsubscribes from an event
    
    .PARAMETER EventName
    The name of the event to unsubscribe from (optional if HandlerId is provided)
    
    .PARAMETER HandlerId
    The unique identifier of the handler to remove
    #>
    param(
        [Parameter()]
        [string]$EventName,
        
        [Parameter(Mandatory = $true)]
        [string]$HandlerId
    )
    Invoke-WithErrorHandling -Component "EventSystem.UnsubscribeEvent" -Context "Unsubscribing from event '$EventName' (Handler: $HandlerId)" -ScriptBlock {
        if ($EventName) {
            # Fast path when event name is known
            if ($script:EventHandlers.ContainsKey($EventName)) {
                $script:EventHandlers[$EventName] = @($script:EventHandlers[$EventName] | Where-Object { $_.HandlerId -ne $HandlerId })
                
                if ($script:EventHandlers[$EventName].Count -eq 0) {
                    $script:EventHandlers.Remove($EventName)
                }
                
                Write-Verbose "Unsubscribed from event: $EventName (Handler: $HandlerId)"
            }
        } else {
            # Search all events for the handler ID
            $found = $false
            foreach ($eventKey in @($script:EventHandlers.Keys)) {
                $handlers = $script:EventHandlers[$eventKey]
                $newHandlers = @($handlers | Where-Object { $_.HandlerId -ne $HandlerId })
                
                if ($newHandlers.Count -lt $handlers.Count) {
                    $found = $true
                    if ($newHandlers.Count -eq 0) {
                        $script:EventHandlers.Remove($eventKey)
                    } else {
                        $script:EventHandlers[$eventKey] = $newHandlers
                    }
                    Write-Verbose "Unsubscribed from event: $eventKey (Handler: $HandlerId)"
                    break
                }
            }
            
            if (-not $found) {
                Write-Warning "Handler ID not found: $HandlerId"
            }
        }
    } -AdditionalData @{ EventName = $EventName; HandlerId = $HandlerId }
}

function global:Get-EventHandlers {
    <#
    .SYNOPSIS
    Gets all registered event handlers
    
    .PARAMETER EventName
    Optional event name to filter by
    #>
    param(
        [Parameter()]
        [string]$EventName
    )
    Invoke-WithErrorHandling -Component "EventSystem.GetEventHandlers" -Context "Getting event handlers for '$EventName'" -ScriptBlock {
        if ($EventName) {
            if ($script:EventHandlers.ContainsKey($EventName)) {
                return $script:EventHandlers[$EventName]
            } else {
                return @()
            }
        } else {
            return $script:EventHandlers
        }
    } -AdditionalData @{ EventName = $EventName }
}

function global:Clear-EventHandlers {
    <#
    .SYNOPSIS
    Clears all event handlers for a specific event or all events
    
    .PARAMETER EventName
    Optional event name to clear handlers for
    #>
    param(
        [Parameter()]
        [string]$EventName
    )
    Invoke-WithErrorHandling -Component "EventSystem.ClearEventHandlers" -Context "Clearing event handlers for '$EventName'" -ScriptBlock {
        if ($EventName) {
            if ($script:EventHandlers.ContainsKey($EventName)) {
                $script:EventHandlers.Remove($EventName)
                Write-Verbose "Cleared handlers for event: $EventName"
            }
        } else {
            $script:EventHandlers = @{}
            Write-Verbose "Cleared all event handlers"
        }
    } -AdditionalData @{ EventName = $EventName }
}

function global:Get-EventHistory {
    <#
    .SYNOPSIS
    Gets the event history
    
    .PARAMETER EventName
    Optional event name to filter by
    
    .PARAMETER Last
    Number of recent events to return
    #>
    param(
        [Parameter()]
        [string]$EventName,
        
        [Parameter()]
        [int]$Last = 0
    )
    Invoke-WithErrorHandling -Component "EventSystem.GetEventHistory" -Context "Getting event history for '$EventName'" -ScriptBlock {
        $history = $script:EventHistory
        
        if ($EventName) {
            $history = $history | Where-Object { $_.EventName -eq $EventName }
        }
        
        if ($Last -gt 0) {
            $history = $history | Select-Object -Last $Last
        }
        
        return $history
    } -AdditionalData @{ EventName = $EventName; LastCount = $Last }
}

function global:Remove-ComponentEventHandlers {
    <#
    .SYNOPSIS
    Removes all event handlers associated with a specific component
    
    .PARAMETER ComponentId
    The ID of the component whose handlers should be removed
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComponentId
    )
    Invoke-WithErrorHandling -Component "EventSystem.RemoveComponentEventHandlers" -Context "Removing event handlers for component '$ComponentId'" -ScriptBlock {
        $removedCount = 0
        
        # Iterate through all events and remove handlers with matching component ID
        foreach ($eventName in @($script:EventHandlers.Keys)) {
            $handlers = $script:EventHandlers[$eventName]
            $newHandlers = @()
            
            foreach ($handler in $handlers) {
                # Check if handler has Source property matching ComponentId
                if ($handler.Source -ne $ComponentId) {
                    $newHandlers += $handler
                } else {
                    $removedCount++
                }
            }
            
            if ($newHandlers.Count -eq 0) {
                $script:EventHandlers.Remove($eventName)
            } else {
                $script:EventHandlers[$eventName] = $newHandlers
            }
        }
        
        Write-Verbose "Removed $removedCount event handlers for component: $ComponentId"
    } -AdditionalData @{ ComponentId = $ComponentId }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-EventSystem',
    'Publish-Event',
    'Subscribe-Event',
    'Unsubscribe-Event',
    'Get-EventHandlers',
    'Clear-EventHandlers',
    'Get-EventHistory',
    'Remove-ComponentEventHandlers'
)