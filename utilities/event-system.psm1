# Event System Module for PMC Terminal v5
# Provides a centralized event publishing and subscription system
# AI: Implements the event-driven architecture for loose coupling between components

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import error handling utilities
Import-Module -Name "$PSScriptRoot\error-handling.psm1" -Force

# Script-level variables for event management
$script:EventSubscriptions = @{}
$script:EventHistory = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:MaxEventHistorySize = 1000
$script:EventQueueEnabled = $false
$script:EventQueue = [System.Collections.Generic.Queue[PSCustomObject]]::new()

# Publish-Event - Broadcast an event to all subscribers
function Publish-Event {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $false)]
        [object]$Data = $null,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{}
    )
    
    Invoke-WithErrorHandling -Component "EventSystem" -Context "PublishEvent:$EventName" -ScriptBlock {
        $eventInfo = [PSCustomObject]@{
            EventName = $EventName
            Data = $Data
            Metadata = $Metadata
            Timestamp = [DateTime]::Now
            PublisherId = [System.Diagnostics.Process]::GetCurrentProcess().Id
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
        }
        
        Write-Log -Level Debug -Message "Publishing event: $EventName" -Component "EventSystem"
        
        # Add to event history
        $script:EventHistory.Add($eventInfo)
        
        # Trim history if needed
        if ($script:EventHistory.Count -gt $script:MaxEventHistorySize) {
            $script:EventHistory.RemoveAt(0)
        }
        
        # Queue event if queuing is enabled
        if ($script:EventQueueEnabled) {
            $script:EventQueue.Enqueue($eventInfo)
            Write-Log -Level Debug -Message "Event queued: $EventName (Queue size: $($script:EventQueue.Count))" -Component "EventSystem"
            return
        }
        
        # Trigger PowerShell engine event
        New-Event -SourceIdentifier $EventName -MessageData $Data
        
        # Call direct subscribers if any
        if ($script:EventSubscriptions.ContainsKey($EventName)) {
            $subscribers = @($script:EventSubscriptions[$EventName])
            Write-Log -Level Debug -Message "Found $($subscribers.Count) subscribers for event: $EventName" -Component "EventSystem"
            
            foreach ($subscriber in $subscribers) {
                try {
                    Write-Log -Level Debug -Message "Invoking subscriber: $($subscriber.Id)" -Component "EventSystem"
                    
                    # Create event args
                    $eventArgs = [PSCustomObject]@{
                        EventName = $EventName
                        Data = $Data
                        Metadata = $Metadata
                        Timestamp = $eventInfo.Timestamp
                    }
                    
                    # Invoke subscriber
                    & $subscriber.Action $eventArgs
                }
                catch {
                    Write-Log -Level Error -Message "Subscriber failed for event '$EventName': $_" -Component "EventSystem"
                    
                    # Optionally remove failed subscriber if configured
                    if ($subscriber.RemoveOnError) {
                        Unsubscribe-Event -EventName $EventName -SubscriberId $subscriber.Id
                    }
                }
            }
        }
    }
}

# Subscribe-Event - Register a handler for an event
function Subscribe-Event {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        
        [Parameter(Mandatory = $false)]
        [string]$SubscriberId = [Guid]::NewGuid().ToString(),
        
        [Parameter(Mandatory = $false)]
        [bool]$RemoveOnError = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$Priority = 0
    )
    
    Invoke-WithErrorHandling -Component "EventSystem" -Context "SubscribeEvent:$EventName" -ScriptBlock {
        Write-Log -Level Debug -Message "Subscribing to event: $EventName (ID: $SubscriberId)" -Component "EventSystem"
        
        # Initialize subscription list if needed
        if (-not $script:EventSubscriptions.ContainsKey($EventName)) {
            $script:EventSubscriptions[$EventName] = @()
        }
        
        # Check if subscriber already exists
        $existingSubscriber = $script:EventSubscriptions[$EventName] | 
            Where-Object { $_.Id -eq $SubscriberId } | 
            Select-Object -First 1
            
        if ($null -ne $existingSubscriber) {
            Write-Log -Level Warning -Message "Subscriber '$SubscriberId' already exists for event '$EventName'. Updating." -Component "EventSystem"
            Unsubscribe-Event -EventName $EventName -SubscriberId $SubscriberId
        }
        
        # Create subscriber object
        $subscriber = [PSCustomObject]@{
            Id = $SubscriberId
            Action = $Action
            Priority = $Priority
            RemoveOnError = $RemoveOnError
            SubscribedAt = [DateTime]::Now
            EventName = $EventName
        }
        
        # Add subscriber to list (sorted by priority)
        $script:EventSubscriptions[$EventName] = @($script:EventSubscriptions[$EventName] + $subscriber) | 
            Sort-Object -Property Priority -Descending
        
        Write-Log -Level Info -Message "Successfully subscribed to event: $EventName" -Component "EventSystem"
        
        return $SubscriberId
    }
}

# Unsubscribe-Event - Remove an event handler
function Unsubscribe-Event {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriberId
    )
    
    Invoke-WithErrorHandling -Component "EventSystem" -Context "UnsubscribeEvent:$EventName" -ScriptBlock {
        Write-Log -Level Debug -Message "Unsubscribing from event: $EventName (ID: $SubscriberId)" -Component "EventSystem"
        
        if (-not $script:EventSubscriptions.ContainsKey($EventName)) {
            Write-Log -Level Warning -Message "No subscriptions found for event: $EventName" -Component "EventSystem"
            return
        }
        
        $initialCount = $script:EventSubscriptions[$EventName].Count
        $script:EventSubscriptions[$EventName] = @($script:EventSubscriptions[$EventName] | 
            Where-Object { $_.Id -ne $SubscriberId })
        
        $removed = $initialCount - $script:EventSubscriptions[$EventName].Count
        
        if ($removed -gt 0) {
            Write-Log -Level Info -Message "Successfully unsubscribed from event: $EventName" -Component "EventSystem"
            
            # Clean up empty subscription lists
            if ($script:EventSubscriptions[$EventName].Count -eq 0) {
                $script:EventSubscriptions.Remove($EventName)
            }
        }
        else {
            Write-Log -Level Warning -Message "Subscriber '$SubscriberId' not found for event '$EventName'" -Component "EventSystem"
        }
    }
}

# Clear-EventSubscriptions - Remove all subscriptions for an event or all events
function Clear-EventSubscriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventName = $null
    )
    
    if ([string]::IsNullOrWhiteSpace($EventName)) {
        Write-Log -Level Info -Message "Clearing all event subscriptions" -Component "EventSystem"
        $script:EventSubscriptions.Clear()
    }
    else {
        Write-Log -Level Info -Message "Clearing subscriptions for event: $EventName" -Component "EventSystem"
        if ($script:EventSubscriptions.ContainsKey($EventName)) {
            $script:EventSubscriptions.Remove($EventName)
        }
    }
}

# Get-EventSubscriptions - Get current subscriptions
function Get-EventSubscriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventName = $null
    )
    
    if ([string]::IsNullOrWhiteSpace($EventName)) {
        return $script:EventSubscriptions
    }
    else {
        if ($script:EventSubscriptions.ContainsKey($EventName)) {
            return $script:EventSubscriptions[$EventName]
        }
        return @()
    }
}

# Get-EventHistory - Retrieve event history
function Get-EventHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventName = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$Last = 0,
        
        [Parameter(Mandatory = $false)]
        [DateTime]$Since = [DateTime]::MinValue
    )
    
    $history = $script:EventHistory
    
    # Filter by event name
    if (-not [string]::IsNullOrWhiteSpace($EventName)) {
        $history = $history | Where-Object { $_.EventName -eq $EventName }
    }
    
    # Filter by time
    if ($Since -ne [DateTime]::MinValue) {
        $history = $history | Where-Object { $_.Timestamp -ge $Since }
    }
    
    # Get last N events
    if ($Last -gt 0) {
        $history = $history | Select-Object -Last $Last
    }
    
    return $history
}

# Clear-EventHistory - Clear the event history
function Clear-EventHistory {
    [CmdletBinding()]
    param()
    
    Write-Log -Level Info -Message "Clearing event history" -Component "EventSystem"
    $script:EventHistory.Clear()
}

# Enable-EventQueue - Enable event queuing
function Enable-EventQueue {
    [CmdletBinding()]
    param()
    
    $script:EventQueueEnabled = $true
    Write-Log -Level Info -Message "Event queuing enabled" -Component "EventSystem"
}

# Disable-EventQueue - Disable event queuing and process queued events
function Disable-EventQueue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$ProcessQueue = $true
    )
    
    $script:EventQueueEnabled = $false
    Write-Log -Level Info -Message "Event queuing disabled" -Component "EventSystem"
    
    if ($ProcessQueue) {
        Process-EventQueue
    }
    else {
        $script:EventQueue.Clear()
    }
}

# Process-EventQueue - Process all queued events
function Process-EventQueue {
    [CmdletBinding()]
    param()
    
    $queueSize = $script:EventQueue.Count
    Write-Log -Level Info -Message "Processing event queue (Size: $queueSize)" -Component "EventSystem"
    
    $processed = 0
    while ($script:EventQueue.Count -gt 0) {
        $eventInfo = $script:EventQueue.Dequeue()
        
        # Re-publish the event
        Publish-Event -EventName $eventInfo.EventName -Data $eventInfo.Data -Metadata $eventInfo.Metadata
        $processed++
    }
    
    Write-Log -Level Info -Message "Processed $processed queued events" -Component "EventSystem"
}

# Wait-Event - Wait for a specific event to occur
function Wait-Event {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter(Mandatory = $false)]
        [scriptblock]$Condition = $null
    )
    
    $receivedEvent = $null
    $waitHandle = [System.Threading.ManualResetEvent]::new($false)
    
    # Subscribe to the event
    $subscriberId = Subscribe-Event -EventName $EventName -Action {
        param($eventArgs)
        
        # Check condition if provided
        if ($null -eq $Condition -or (& $Condition $eventArgs)) {
            $script:receivedEvent = $eventArgs
            [void]$waitHandle.Set()
        }
    }
    
    try {
        # Wait for event or timeout
        $signaled = $waitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
        
        if ($signaled) {
            return $script:receivedEvent
        }
        else {
            Write-Log -Level Warning -Message "Timeout waiting for event: $EventName" -Component "EventSystem"
            return $null
        }
    }
    finally {
        # Clean up
        Unsubscribe-Event -EventName $EventName -SubscriberId $subscriberId
        $waitHandle.Dispose()
    }
}

# Initialize-EventSystem - Set up the event system
function Initialize-EventSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxHistorySize = 1000
    )
    
    $script:MaxEventHistorySize = $MaxHistorySize
    
    Write-Log -Level Info -Message "Event system initialized (Max history: $MaxHistorySize)" -Component "EventSystem"
}

# Export all functions
Export-ModuleMember -Function @(
    'Publish-Event',
    'Subscribe-Event',
    'Unsubscribe-Event',
    'Clear-EventSubscriptions',
    'Get-EventSubscriptions',
    'Get-EventHistory',
    'Clear-EventHistory',
    'Enable-EventQueue',
    'Disable-EventQueue',
    'Process-EventQueue',
    'Wait-Event',
    'Initialize-EventSystem'
)