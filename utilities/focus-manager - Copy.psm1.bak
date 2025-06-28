# FILE: utilities/focus-manager.psm1
# PURPOSE: Provides the single source of truth for component focus management with scope support.

$script:Focus = @{
    FocusedComponent = $null 
    TabOrder = @()
    ActiveScope = $null
    History = @()  # Focus history for debugging
    ScopeStack = @()  # For nested focus scopes
}

function global:Request-Focus {
    param(
        [hashtable]$Component,
        [bool]$UpdateTabOrder = $false,
        [string]$Reason = "Direct"
    )
    
    # Validate component
    if ($Component -and -not $Component.IsFocusable) {
        Write-Log -Level Debug -Message "Cannot focus non-focusable component: $($Component.Name ?? $Component.Type)"
        return $false
    }
    
    if ($Component -and -not $Component.Visible) {
        Write-Log -Level Debug -Message "Cannot focus invisible component: $($Component.Name ?? $Component.Type)"
        return $false
    }
    
    # Handle losing focus on previous component
    $oldFocused = $script:Focus.FocusedComponent
    if ($oldFocused -and ($oldFocused -ne $Component)) {
        $oldFocused.IsFocused = $false
        
        if ($oldFocused.OnBlur) {
            try {
                & $oldFocused.OnBlur -self $oldFocused
            } catch {
                Write-Log -Level Error -Message "Error in OnBlur handler" -Data $_
            }
        }
        
        # Fire blur event
        if (Get-Command -Name "Publish-Event" -ErrorAction SilentlyContinue) {
            Publish-Event -EventName "Component.Blur" -Data @{ Component = $oldFocused }
        }
    }
    
    # Update focus scope if needed
    $newScope = if ($Component) { Get-FocusScope -Component $Component } else { $null }
    if ($newScope -ne $script:Focus.ActiveScope) {
        # Leave old scope
        if ($script:Focus.ActiveScope -and $script:Focus.ActiveScope.OnLeaveFocusScope) {
            try {
                & $script:Focus.ActiveScope.OnLeaveFocusScope -self $script:Focus.ActiveScope
            } catch {
                Write-Log -Level Error -Message "Error in OnLeaveFocusScope handler" -Data $_
            }
        }
        
        $script:Focus.ActiveScope = $newScope
        
        # Enter new scope
        if ($newScope -and $newScope.OnEnterFocusScope) {
            try {
                & $newScope.OnEnterFocusScope -self $newScope
            } catch {
                Write-Log -Level Error -Message "Error in OnEnterFocusScope handler" -Data $_
            }
        }
    }
    
    # Set new focus
    $script:Focus.FocusedComponent = $Component
    
    # Update global state if available
    if ($global:TuiState) {
        $global:TuiState.FocusedComponent = $Component
    }
    
    # Update history
    $script:Focus.History += @{
        Component = $Component
        Timestamp = [DateTime]::UtcNow
        Reason = $Reason
    }
    if ($script:Focus.History.Count -gt 50) {
        $script:Focus.History = $script:Focus.History[-50..-1]
    }
    
    if ($Component) {
        $Component.IsFocused = $true
        
        # Call focus handler
        if ($Component.OnFocus) {
            try {
                & $Component.OnFocus -self $Component
            } catch {
                Write-Log -Level Error -Message "Error in OnFocus handler" -Data $_
            }
        }
        
        # Fire focus event
        if (Get-Command -Name "Publish-Event" -ErrorAction SilentlyContinue) {
            Publish-Event -EventName "Component.Focus" -Data @{ Component = $Component }
        }
        
        # Update tab order if requested
        if ($UpdateTabOrder) {
            Update-TabOrder -FocusedComponent $Component
        }
    }
    
    # Request screen refresh
    if (Get-Command -Name "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
        Request-TuiRefresh
    }
    
    if ($Component) {
        Write-Log -Level Debug -Message "Focused: $($Component.Name ?? $Component.Type) (Reason: $Reason)"
    } else {
        Write-Log -Level Debug -Message "Cleared focus (Reason: $Reason)"
    }
    
    return $true
}

function global:Clear-Focus {
    Request-Focus -Component $null -Reason "Clear"
}

function global:Move-Focus {
    param(
        [bool]$Reverse = $false,
        [bool]$Wrap = $true
    )
    
    # Check if active scope handles its own focus movement
    if ($script:Focus.ActiveScope -and $script:Focus.ActiveScope.HandleScopedFocus) {
        $handled = & $script:Focus.ActiveScope.HandleScopedFocus -self $script:Focus.ActiveScope -Reverse $Reverse
        if ($handled) {
            return $true
        }
    }
    
    # No focusable components
    if ($script:Focus.TabOrder.Count -eq 0) {
        Write-Log -Level Debug -Message "No focusable components in tab order"
        return $false
    }
    
    # Find current index
    $currentIndex = [array]::IndexOf($script:Focus.TabOrder, $script:Focus.FocusedComponent)
    
    # If no current focus, focus first/last based on direction
    if ($currentIndex -eq -1) {
        $targetIndex = if ($Reverse) { $script:Focus.TabOrder.Count - 1 } else { 0 }
        Request-Focus -Component $script:Focus.TabOrder[$targetIndex] -Reason "TabNavigation"
        return $true
    }
    
    # Calculate next index
    if ($Reverse) {
        $nextIndex = $currentIndex - 1
        if ($nextIndex -lt 0) {
            $nextIndex = if ($Wrap) { $script:Focus.TabOrder.Count - 1 } else { 0 }
        }
    } else {
        $nextIndex = $currentIndex + 1
        if ($nextIndex -ge $script:Focus.TabOrder.Count) {
            $nextIndex = if ($Wrap) { 0 } else { $script:Focus.TabOrder.Count - 1 }
        }
    }
    
    # Skip invisible or disabled components
    $attempts = 0
    while ($attempts -lt $script:Focus.TabOrder.Count) {
        $candidate = $script:Focus.TabOrder[$nextIndex]
        
        if ($candidate.Visible -and $candidate.IsFocusable -and 
            (-not $candidate.PSObject.Properties['IsEnabled'] -or $candidate.IsEnabled)) {
            Request-Focus -Component $candidate -Reason "TabNavigation"
            return $true
        }
        
        # Move to next candidate
        if ($Reverse) {
            $nextIndex--
            if ($nextIndex -lt 0) {
                $nextIndex = if ($Wrap) { $script:Focus.TabOrder.Count - 1 } else { 0 }
            }
        } else {
            $nextIndex++
            if ($nextIndex -ge $script:Focus.TabOrder.Count) {
                $nextIndex = if ($Wrap) { 0 } else { $script:Focus.TabOrder.Count - 1 }
            }
        }
        
        $attempts++
    }
    
    Write-Log -Level Debug -Message "No valid focus target found"
    return $false
}

function global:Get-FocusedComponent {
    return $script:Focus.FocusedComponent
}

function global:Get-FocusHistory {
    return $script:Focus.History
}

function private:Get-FocusScope {
    param($Component)
    
    $current = $Component
    while ($current) {
        if ($current.IsFocusScope) {
            return $current
        }
        $current = $current.Parent
    }
    
    return $null
}

function global:Push-FocusScope {
    param([hashtable]$Scope)
    
    if (-not $Scope.IsFocusScope) {
        $Scope.IsFocusScope = $true
    }
    
    $script:Focus.ScopeStack += $Scope
    $script:Focus.ActiveScope = $Scope
    
    Write-Log -Level Debug -Message "Pushed focus scope: $($Scope.Name ?? $Scope.Type)"
}

function global:Pop-FocusScope {
    if ($script:Focus.ScopeStack.Count -eq 0) {
        return $null
    }
    
    $poppedScope = $script:Focus.ScopeStack[-1]
    $script:Focus.ScopeStack = $script:Focus.ScopeStack[0..($script:Focus.ScopeStack.Count - 2)]
    
    # Restore previous scope
    if ($script:Focus.ScopeStack.Count -gt 0) {
        $script:Focus.ActiveScope = $script:Focus.ScopeStack[-1]
    } else {
        $script:Focus.ActiveScope = $null
    }
    
    Write-Log -Level Debug -Message "Popped focus scope: $($poppedScope.Name ?? $poppedScope.Type)"
    
    return $poppedScope
}

function private:Update-TabOrder {
    param($FocusedComponent)
    
    # If component is already in tab order, no need to update
    if ($FocusedComponent -in $script:Focus.TabOrder) {
        return
    }
    
    # Rebuild tab order
    Register-ScreenForFocus -Screen $global:TuiState.CurrentScreen
}

function private:Register-ScreenForFocus {
    param($Screen)
    
    $script:Focus.TabOrder = @()
    $script:Focus.ActiveScope = $null
    
    if (-not $Screen) {
        Request-Focus -Component $null -Reason "NoScreen"
        return
    }
    
    # Find all focusable components
    $focusableComponents = @()
    
    $FindFocusable = $null
    $FindFocusable = {
        param($component, $depth = 0)
        
        if (-not $component) { return }
        
        # Add focusable components
        if ($component.IsFocusable -and $component.Visible) {
            $focusableComponents += @{
                Component = $component
                Depth = $depth
                TabIndex = $component.TabIndex ?? 0
                Position = @{
                    Y = $component.Y ?? 0
                    X = $component.X ?? 0
                }
            }
        }
        
        # Process panel children
        if ($component.Children) {
            foreach ($child in $component.Children) {
                & $FindFocusable -component $child -depth ($depth + 1)
            }
        }
        
        # Process named children (for backward compatibility)
        if ($component.Components) {
            foreach ($child in $component.Components.Values) {
                & $FindFocusable -component $child -depth ($depth + 1)
            }
        }
    }.GetNewClosure()
    
    # Start from screen components
    if ($Screen.Components) {
        foreach ($comp in $Screen.Components.Values) {
            & $FindFocusable -component $comp
        }
    }
    
    # Sort by TabIndex, then by position (top to bottom, left to right)
    $script:Focus.TabOrder = $focusableComponents | 
        Sort-Object { $_.TabIndex }, { $_.Position.Y }, { $_.Position.X } |
        ForEach-Object { $_.Component }
    
    Write-Log -Level Debug -Message "Registered $($script:Focus.TabOrder.Count) focusable components"
    
    # Focus first component if none focused
    if ($script:Focus.TabOrder.Count -gt 0 -and -not $script:Focus.FocusedComponent) {
        Request-Focus -Component $script:Focus.TabOrder[0] -Reason "InitialFocus"
    } elseif ($script:Focus.TabOrder.Count -eq 0) {
        Request-Focus -Component $null -Reason "NoFocusableComponents"
    }
}

function global:Initialize-FocusManager {
    # Subscribe to screen events
    if (Get-Command -Name "Subscribe-Event" -ErrorAction SilentlyContinue) {
        Subscribe-Event -EventName "Screen.Pushed" -Handler {
            param($Event)
            Register-ScreenForFocus -Screen $Event.Data.Screen
        }
        
        Subscribe-Event -EventName "Screen.Popped" -Handler {
            param($Event)
            # Clear focus scopes
            $script:Focus.ScopeStack = @()
            $script:Focus.ActiveScope = $null
            
            # Re-register for new top screen
            if ($global:TuiState -and $global:TuiState.CurrentScreen) {
                Register-ScreenForFocus -Screen $global:TuiState.CurrentScreen
            }
        }
        
        Subscribe-Event -EventName "Component.VisibilityChanged" -Handler {
            param($Event)
            $component = $Event.Data.Component
            
            # If hiding focused component, move focus
            if (-not $component.Visible -and $component -eq $script:Focus.FocusedComponent) {
                Move-Focus
            }
            
            # Update tab order if visibility changed
            if ($global:TuiState -and $global:TuiState.CurrentScreen) {
                Register-ScreenForFocus -Screen $global:TuiState.CurrentScreen
            }
        }
    }
    
    Write-Log -Level Info -Message "Focus Manager initialized"
}

# Utility functions for components
function global:Set-ComponentFocusable {
    param(
        [hashtable]$Component,
        [bool]$IsFocusable
    )
    
    $wasFocusable = $Component.IsFocusable
    $Component.IsFocusable = $IsFocusable
    
    # If making unfocusable and it's currently focused, clear focus
    if ($wasFocusable -and -not $IsFocusable -and $Component -eq $script:Focus.FocusedComponent) {
        Move-Focus
    }
    
    # Update tab order
    if ($global:TuiState -and $global:TuiState.CurrentScreen) {
        Register-ScreenForFocus -Screen $global:TuiState.CurrentScreen
    }
}

function global:Focus-NextInScope {
    param([hashtable]$Scope)
    
    if (-not $Scope -or -not $Scope.IsFocusScope) {
        return $false
    }
    
    # Find focusable children within scope
    $scopeFocusable = @()
    
    $FindScopeFocusable = {
        param($component)
        
        if ($component.IsFocusable -and $component.Visible) {
            $scopeFocusable += $component
        }
        
        if ($component.Children -and $component -ne $Scope) {
            foreach ($child in $component.Children) {
                & $FindScopeFocusable -component $child
            }
        }
    }
    
    & $FindScopeFocusable -component $Scope
    
    if ($scopeFocusable.Count -eq 0) {
        return $false
    }
    
    # Find current index
    $currentIndex = [array]::IndexOf($scopeFocusable, $script:Focus.FocusedComponent)
    $nextIndex = ($currentIndex + 1) % $scopeFocusable.Count
    
    Request-Focus -Component $scopeFocusable[$nextIndex] -Reason "ScopeNavigation"
    return $true
}

Export-ModuleMember -Function @(
    "Initialize-FocusManager",
    "Request-Focus", 
    "Clear-Focus",
    "Move-Focus",
    "Get-FocusedComponent",
    "Get-FocusHistory",
    "Push-FocusScope",
    "Pop-FocusScope",
    "Set-ComponentFocusable",
    "Focus-NextInScope"
)
