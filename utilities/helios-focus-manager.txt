#
# MODULE: modules/focus-manager.psm1
#
# PURPOSE:
#   Provides the single source of truth for component focus. It manages the tab order
#   and handles the logic for moving focus between UI components.
#
# ARCHITECTURE:
#   - This module maintains its state in a private [PSCustomObject] called $FocusManager.
#   - It initializes by subscribing to the 'PMC.Navigation.ScreenPushed' engine event.
#   - When a new screen is displayed, it automatically traverses the screen's component
#     tree to build a list of all focusable components (the tab order).
#   - It provides public functions (Request-Focus, Move-Focus) for explicitly setting
#     or moving the focus.
#

using module "$PSScriptRoot/logger.psm1"
using module "$PSScriptRoot/exceptions.psm1"

#region Private State
# ------------------------------------------------------------------------------
# Private state for the Focus Manager. This is not exposed outside the module.
# ------------------------------------------------------------------------------

$FocusManager = [PSCustomObject]@{
    # The component that currently has focus.
    FocusedComponent = $null

    # A sorted list of all components on the current screen that are focusable.
    TabOrder = [System.Collections.Generic.List[object]]::new()

    # The event subscriber object for the Screen.Pushed event.
    EventSubscription = $null
}

#endregion

#region Private Functions
# ------------------------------------------------------------------------------
# Internal helper functions used by the Focus Manager.
# ------------------------------------------------------------------------------

function Find-FocusableComponents {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RootComponent
    )

    $focusable = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue($RootComponent)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()

        if (-not $current) { continue }

        # A component is focusable if it's visible and has the IsFocusable property set to true.
        if ($current.PSObject.Properties['IsFocusable'] -and $current.IsFocusable -and $current.PSObject.Properties['Visible'] -and $current.Visible) {
            $focusable.Add($current)
        }

        # Recurse into children. The Helios layout system uses a 'Children' property.
        if ($current.PSObject.Properties['Children']) {
            foreach ($child in $current.Children) {
                $queue.Enqueue($child)
            }
        }
    }

    return $focusable
}

function Update-TabOrderAndFocus {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Screen
    )

    Invoke-WithErrorHandling -Component 'FocusManager.UpdateTabOrderAndFocus' -Context @{ ScreenName = $Screen.Name } -ScriptBlock {
        Write-Log -Level Trace -Message "Updating tab order for screen '$($Screen.Name)'"

        # Clear previous state
        $FocusManager.TabOrder.Clear()
        Request-Focus -Component $null -Reason 'ScreenChange'

        if (-not $Screen.RootPanel) {
            Write-Log -Level Warn -Message "Screen '$($Screen.Name)' has no RootPanel. Cannot establish focus."
            return
        }

        # Find all focusable components and establish the new tab order
        $focusableComponents = Find-FocusableComponents -RootComponent $Screen.RootPanel
        $FocusManager.TabOrder.AddRange($focusableComponents)

        Write-Log -Level Debug -Message "Found $($FocusManager.TabOrder.Count) focusable components on screen '$($Screen.Name)'"

        # Set focus to the first component in the new tab order
        if ($FocusManager.TabOrder.Count -gt 0) {
            Request-Focus -Component $FocusManager.TabOrder[0] -Reason 'InitialFocus'
        }
    }
}

#endregion

#region Public Functions
# ------------------------------------------------------------------------------
# Functions exported for use by other modules.
# ------------------------------------------------------------------------------

function Initialize-FocusManager {
    <#
    .SYNOPSIS
        Initializes the Focus Manager and subscribes to necessary application events.
    .DESCRIPTION
        This function must be called once at application startup. It registers an
        engine event handler for 'PMC.Navigation.ScreenPushed'. When this event is
        fired, the Focus Manager automatically rebuilds its tab order based on the
        new screen's components.
    #>
    [CmdletBinding()]
    param()

    Invoke-WithErrorHandling -Component 'FocusManager.Initialize' -Context @{} -ScriptBlock {
        Write-Log -Level Info -Message "Initializing Focus Manager..."

        # The Navigation service will broadcast this event when a screen is pushed.
        $sourceIdentifier = 'PMC.Navigation.ScreenPushed'

        # Unregister any previous subscription to prevent duplicates during development/reloading.
        if ($FocusManager.EventSubscription) {
            Unregister-Event -SubscriptionId $FocusManager.EventSubscription.Id
            Write-Log -Level Debug -Message "Unregistered existing Focus Manager event subscription."
        }

        # Create the handler scriptblock. It receives the event and updates the tab order.
        $handler = {
            param($Event)
            Invoke-WithErrorHandling -Component 'FocusManager.ScreenPushedHandler' -Context @{ EventData = $Event.MessageData } -ScriptBlock {
                $screen = $Event.MessageData.Screen
                if ($screen) {
                    Update-TabOrderAndFocus -Screen $screen
                }
                else {
                    Write-Log -Level Warn -Message 'Screen.Pushed event received without a screen object.'
                }
            }
        }

        # Register the event handler.
        $subscription = Register-EngineEvent -SourceIdentifier $sourceIdentifier -Action $handler
        $FocusManager.EventSubscription = $subscription

        Write-Log -Level Info -Message "Focus Manager initialized and subscribed to '$sourceIdentifier'."
    }
}

function Request-Focus {
    <#
    .SYNOPSIS
        Sets focus to a specific component.
    .DESCRIPTION
        This is the primary method for controlling focus. It handles blurring the
        previously focused component and focusing the new one, including calling
        their respective OnBlur and OnFocus methods.
    .PARAMETER Component
        The component to receive focus. If $null, focus is cleared.
    .PARAMETER Reason
        A string describing why the focus changed, for logging purposes.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [PSCustomObject]$Component,

        [string]$Reason = 'DirectRequest'
    )

    Invoke-WithErrorHandling -Component 'FocusManager.RequestFocus' -Context @{ TargetComponent = $Component.Name; Reason = $Reason } -ScriptBlock {
        # Defensively check if the target component is actually focusable.
        if ($Component -and $Component.PSObject.Properties['IsFocusable'] -and -not $Component.IsFocusable) {
            Write-Log -Level Debug -Message "Request-Focus ignored for non-focusable component '$($Component.Name)'"
            return
        }

        $oldFocused = $FocusManager.FocusedComponent

        # If focus is not changing, do nothing.
        if ($oldFocused -is [PSCustomObject] -and $oldFocused.Id -eq $Component.Id) {
            return
        }

        # 1. Blur the previously focused component
        if ($oldFocused) {
            $oldFocused.IsFocused = $false
            if ($oldFocused.PSObject.ScriptMethods['OnBlur']) {
                try {
                    $oldFocused.OnBlur()
                    Write-Log -Level Trace -Message "Called OnBlur for component '$($oldFocused.Name)'"
                }
                catch {
                    Write-Log -Level Error -Message "Error in OnBlur for component '$($oldFocused.Name)': $_" -Data $_
                }
            }
        }

        # 2. Update the state to the new component
        $FocusManager.FocusedComponent = $Component
        Write-Log -Level Debug -Message "Focus changed from '$($oldFocused.Name)' to '$($Component.Name)' (Reason: $Reason)"

        # 3. Focus the new component
        if ($Component) {
            $Component.IsFocused = $true
            if ($Component.PSObject.ScriptMethods['OnFocus']) {
                try {
                    $Component.OnFocus()
                    Write-Log -Level Trace -Message "Called OnFocus for component '$($Component.Name)'"
                }
                catch {
                    Write-Log -Level Error -Message "Error in OnFocus for component '$($Component.Name)': $_" -Data $_
                }
            }
        }
    }
}

function Move-Focus {
    <#
    .SYNOPSIS
        Moves focus to the next or previous component in the tab order.
    .DESCRIPTION
        Typically called in response to Tab or Shift+Tab key presses. It cycles
        through the list of focusable components on the current screen.
    .PARAMETER Reverse
        If $true, moves to the previous component instead of the next.
    #>
    [CmdletBinding()]
    param(
        [switch]$Reverse
    )

    Invoke-WithErrorHandling -Component 'FocusManager.MoveFocus' -Context @{ Reverse = $Reverse.IsPresent } -ScriptBlock {
        $tabOrder = $FocusManager.TabOrder
        if ($tabOrder.Count -eq 0) {
            Write-Log -Level Debug -Message "Move-Focus called, but there are no focusable components."
            return
        }

        $currentFocused = $FocusManager.FocusedComponent
        $currentIndex = -1
        if ($currentFocused) {
            $currentIndex = $tabOrder.IndexOf($currentFocused)
        }

        $nextIndex = 0
        if ($currentIndex -eq -1) {
            # No component is currently focused, so focus the first (or last if reversing).
            $nextIndex = if ($Reverse) { $tabOrder.Count - 1 } else { 0 }
        }
        else {
            # Calculate the next index, wrapping around the list.
            $increment = if ($Reverse) { -1 } else { 1 }
            $nextIndex = ($currentIndex + $increment + $tabOrder.Count) % $tabOrder.Count
        }

        $nextComponent = $tabOrder[$nextIndex]
        Request-Focus -Component $nextComponent -Reason ('TabNavigation' + $(if ($Reverse) { 'Reverse' } else { '' }))
    }
}

function Get-FocusedComponent {
    <#
    .SYNOPSIS
        Gets the component that currently has focus.
    .OUTPUTS
        [PSCustomObject] The focused component, or $null if none.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $FocusManager.FocusedComponent
}

#endregion

Export-ModuleMember -Function Initialize-FocusManager, Request-Focus, Move-Focus, Get-FocusedComponent