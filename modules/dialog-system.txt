# Dialog System Module - FIXED VERSION
# Uses engine's word wrap helper and respects the framework

$script:DialogState = @{
    CurrentDialog = $null
    DialogStack   = [System.Collections.Stack]::new()
}

#region --- Public API & Factory Functions ---

function global:Show-TuiDialog {
    <# .SYNOPSIS Internal function to display a dialog component. #>
    param([hashtable]$DialogComponent)
    Invoke-WithErrorHandling -Component "DialogSystem.ShowDialog" -ScriptBlock {
        if ($script:DialogState.CurrentDialog) {
            $script:DialogState.DialogStack.Push($script:DialogState.CurrentDialog)
        }
        $script:DialogState.CurrentDialog = $DialogComponent
        Request-TuiRefresh
    } -Context "Showing dialog: $($DialogComponent.Title)" -AdditionalData @{ DialogType = $DialogComponent.Type; DialogTitle = $DialogComponent.Title }
}

function global:Close-TuiDialog {
    <# .SYNOPSIS Closes the current dialog and restores the previous one, if any. #>
    Invoke-WithErrorHandling -Component "DialogSystem.CloseDialog" -ScriptBlock {
        if ($script:DialogState.DialogStack.Count -gt 0) {
            $script:DialogState.CurrentDialog = $script:DialogState.DialogStack.Pop()
        } else {
            $script:DialogState.CurrentDialog = $null
        }
        Request-TuiRefresh
    } -Context "Closing current dialog"
}

function global:Show-ConfirmDialog {
    <# .SYNOPSIS Displays a standard Yes/No confirmation dialog. #>
    param(
        [string]$Title = "Confirm",
        [string]$Message,
        [scriptblock]$OnConfirm,
        [scriptblock]$OnCancel = {}
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowConfirmDialog" -ScriptBlock {
        $dialog = New-TuiDialog -Props @{
            Title         = $Title
            Message       = $Message
            Buttons       = @("Yes", "No")
            Width         = [Math]::Min(80, [Math]::Max(50, $Message.Length + 10))
            Height        = 10
            OnButtonClick = {
                param($Button, $Index)
                Invoke-WithErrorHandling -Component "ConfirmDialog.OnButtonClick" -ScriptBlock {
                    Close-TuiDialog
                    if ($Index -eq 0) { & $OnConfirm } else { & $OnCancel }
                } -Context "Confirm dialog button click: $Button" -AdditionalData @{ Button = $Button; Index = $Index; DialogTitle = $Title }
            }
            OnCancel      = { 
                Invoke-WithErrorHandling -Component "ConfirmDialog.OnCancel" -ScriptBlock {
                    Close-TuiDialog; & $OnCancel 
                } -Context "Confirm dialog cancelled" -AdditionalData @{ DialogTitle = $Title }
            }
        }
        Show-TuiDialog -DialogComponent $dialog
    } -Context "Creating confirm dialog: $Title" -AdditionalData @{ Title = $Title; Message = $Message }
}

function global:Show-AlertDialog {
    <# .SYNOPSIS Displays a simple alert with an OK button. #>
    param(
        [string]$Title = "Alert",
        [string]$Message
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowAlertDialog" -ScriptBlock {
        $dialog = New-TuiDialog -Props @{
            Title         = $Title
            Message       = $Message
            Buttons       = @("OK")
            Width         = [Math]::Min(80, [Math]::Max(40, $Message.Length + 10))
            Height        = 10
            OnButtonClick = { 
                Invoke-WithErrorHandling -Component "AlertDialog.OnButtonClick" -ScriptBlock {
                    Close-TuiDialog 
                } -Context "Alert dialog OK clicked" -AdditionalData @{ DialogTitle = $Title }
            }
            OnCancel      = { 
                Invoke-WithErrorHandling -Component "AlertDialog.OnCancel" -ScriptBlock {
                    Close-TuiDialog 
                } -Context "Alert dialog cancelled" -AdditionalData @{ DialogTitle = $Title }
            }
        }
        Show-TuiDialog -DialogComponent $dialog
    } -Context "Creating alert dialog: $Title" -AdditionalData @{ Title = $Title; Message = $Message }
}

function global:Show-InputDialog {
    <# .SYNOPSIS Displays a dialog to get text input from the user. #>
    param(
        [string]$Title = "Input",
        [string]$Prompt,
        [string]$DefaultValue = "",
        [scriptblock]$OnSubmit,
        [scriptblock]$OnCancel = {}
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowInputDialog" -ScriptBlock {
        # Create a screen that contains the input components
        $inputScreen = @{
            Name = "InputDialog"
            State = @{
                InputValue = $DefaultValue
                FocusedIndex = 0  # Start with textbox focused
            }
            _focusableNames = @("InputTextBox", "OKButton", "CancelButton")
            _focusedIndex = 0
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Name).Render" -ScriptBlock {
                    # Calculate dialog dimensions
                    $dialogWidth = [Math]::Min(70, [Math]::Max(50, $Prompt.Length + 10))
                    $dialogHeight = 10
                    $dialogX = [Math]::Floor(($global:TuiState.BufferWidth - $dialogWidth) / 2)
                    $dialogY = [Math]::Floor(($global:TuiState.BufferHeight - $dialogHeight) / 2)
                    
                    # Draw dialog box
                    Write-BufferBox -X $dialogX -Y $dialogY -Width $dialogWidth -Height $dialogHeight `
                        -Title " $Title " -BorderColor (Get-ThemeColor "Accent")
                    
                    # Draw prompt
                    $promptX = $dialogX + 2
                    $promptY = $dialogY + 2
                    Write-BufferString -X $promptX -Y $promptY -Text $Prompt
                    
                    # Draw text input
                    $inputY = $promptY + 2
                    $inputWidth = $dialogWidth - 4
                    $isFocused = ($self._focusedIndex -eq 0)
                    $borderColor = if ($isFocused) { Get-ThemeColor "Warning" } else { Get-ThemeColor "Primary" }
                    
                    Write-BufferBox -X $promptX -Y $inputY -Width $inputWidth -Height 3 `
                        -BorderColor $borderColor
                    
                    # Draw input value
                    $displayText = $self.State.InputValue
                    if ($displayText.Length -gt ($inputWidth - 3)) {
                        $displayText = $displayText.Substring(0, $inputWidth - 3) # Ensure it fits
                    }
                    Write-BufferString -X ($promptX + 1) -Y ($inputY + 1) -Text $displayText
                    
                    # Draw cursor if textbox is focused
                    if ($isFocused) {
                        $cursorPos = [Math]::Min($self.State.InputValue.Length, $inputWidth - 3)
                        Write-BufferString -X ($promptX + 1 + $cursorPos) -Y ($inputY + 1) `
                            -Text "_" -ForegroundColor (Get-ThemeColor "Warning")
                    }
                    
                    # Draw buttons
                    $buttonY = $dialogY + $dialogHeight - 2
                    $buttonSpacing = 15
                    $buttonsWidth = $buttonSpacing * 2
                    $buttonX = $dialogX + [Math]::Floor(($dialogWidth - $buttonsWidth) / 2)
                    
                    # OK button
                    $okFocused = ($self._focusedIndex -eq 1)
                    $okText = if ($okFocused) { "[ OK ]" } else { "  OK  " }
                    $okColor = if ($okFocused) { Get-ThemeColor "Warning" } else { Get-ThemeColor "Primary" }
                    Write-BufferString -X $buttonX -Y $buttonY -Text $okText -ForegroundColor $okColor
                    
                    # Cancel button
                    $cancelFocused = ($self._focusedIndex -eq 2)
                    $cancelText = if ($cancelFocused) { "[ Cancel ]" } else { "  Cancel  " }
                    $cancelColor = if ($cancelFocused) { Get-ThemeColor "Warning" } else { Get-ThemeColor "Primary" }
                    Write-BufferString -X ($buttonX + $buttonSpacing) -Y $buttonY -Text $cancelText -ForegroundColor $cancelColor
                } -Context "Rendering input dialog" -AdditionalData @{ DialogName = $self.Name; Prompt = $Prompt; CurrentValue = $self.State.InputValue }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Name).HandleInput" -ScriptBlock {
                    # Handle Tab navigation
                    if ($Key.Key -eq [ConsoleKey]::Tab) {
                        $direction = if ($Key.Modifiers -band [ConsoleModifiers]::Shift) { -1 } else { 1 }
                        $self._focusedIndex = ($self._focusedIndex + $direction + 3) % 3
                        Request-TuiRefresh
                        return $true
                    }
                    
                    # Handle Escape
                    if ($Key.Key -eq [ConsoleKey]::Escape) {
                        Close-TuiDialog
                        Invoke-WithErrorHandling -Component "InputDialog.OnCancel" -ScriptBlock {
                            & $OnCancel
                        } -Context "Input dialog cancelled via Escape" -AdditionalData @{ DialogTitle = $Title }
                        return $true
                    }
                    
                    # Handle based on focused element
                    switch ($self._focusedIndex) {
                        0 {  # TextBox
                            switch ($Key.Key) {
                                ([ConsoleKey]::Enter) {
                                    Close-TuiDialog
                                    Invoke-WithErrorHandling -Component "InputDialog.OnSubmit" -ScriptBlock {
                                        & $OnSubmit -Value $self.State.InputValue
                                    } -Context "Input dialog submitted via Enter" -AdditionalData @{ DialogTitle = $Title; InputValue = $self.State.InputValue }
                                    return $true
                                }
                                ([ConsoleKey]::Backspace) {
                                    if ($self.State.InputValue.Length -gt 0) {
                                        $self.State.InputValue = $self.State.InputValue.Substring(0, $self.State.InputValue.Length - 1)
                                        Request-TuiRefresh
                                    }
                                    return $true
                                }
                                default {
                                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) {
                                        $self.State.InputValue += $Key.KeyChar
                                        Request-TuiRefresh
                                        return $true
                                    }
                                }
                            }
                        }
                        1 {  # OK Button
                            if ($Key.Key -eq [ConsoleKey]::Enter -or $Key.Key -eq [ConsoleKey]::Spacebar) {
                                Close-TuiDialog
                                Invoke-WithErrorHandling -Component "InputDialog.OnSubmit" -ScriptBlock {
                                    & $OnSubmit -Value $self.State.InputValue
                                } -Context "Input dialog submitted via OK button" -AdditionalData @{ DialogTitle = $Title; InputValue = $self.State.InputValue }
                                return $true
                            }
                        }
                        2 {  # Cancel Button
                            if ($Key.Key -eq [ConsoleKey]::Enter -or $Key.Key -eq [ConsoleKey]::Spacebar) {
                                Close-TuiDialog
                                Invoke-WithErrorHandling -Component "InputDialog.OnCancel" -ScriptBlock {
                                    & $OnCancel
                                } -Context "Input dialog cancelled via Cancel button" -AdditionalData @{ DialogTitle = $Title }
                                return $true
                            }
                        }
                    }
                    
                    return $false
                } -Context "Handling input dialog key press" -AdditionalData @{ DialogName = $self.Name; Key = $Key; FocusedIndex = $self._focusedIndex }
            }
        }
        
        $script:DialogState.CurrentDialog = $inputScreen
        Request-TuiRefresh
    } -Context "Creating input dialog: $Title" -AdditionalData @{ Title = $Title; Prompt = $Prompt; DefaultValue = $DefaultValue }
}

#endregion

#region --- Engine Integration & Initialization ---

function global:Initialize-DialogSystem {
    <# .SYNOPSIS Subscribes to high-level application events to show dialogs. #>
    Invoke-WithErrorHandling -Component "DialogSystem.Initialize" -ScriptBlock {
        Subscribe-Event -EventName "Confirm.Request" -Handler {
            param($EventData)
            Invoke-WithErrorHandling -Component "DialogSystem.ConfirmEventHandler" -ScriptBlock {
                $dialogParams = $EventData.Data
                Show-ConfirmDialog @dialogParams
            } -Context "Handling Confirm.Request event" -AdditionalData @{ EventData = $EventData }
        }
        
        Subscribe-Event -EventName "Alert.Show" -Handler {
            param($EventData)
            Invoke-WithErrorHandling -Component "DialogSystem.AlertEventHandler" -ScriptBlock {
                $dialogParams = $EventData.Data
                Show-AlertDialog @dialogParams
            } -Context "Handling Alert.Show event" -AdditionalData @{ EventData = $EventData }
        }
        
        Subscribe-Event -EventName "Input.Request" -Handler {
            param($EventData)
            Invoke-WithErrorHandling -Component "DialogSystem.InputEventHandler" -ScriptBlock {
                $dialogParams = $EventData.Data
                Show-InputDialog @dialogParams
            } -Context "Handling Input.Request event" -AdditionalData @{ EventData = $EventData }
        }
        
        Write-Verbose "Dialog System initialized and event handlers registered."
    } -Context "Initializing Dialog System"
}

function global:Render-Dialogs {
    <# .SYNOPSIS Engine Hook: Renders the current dialog over the screen. #>
    Invoke-WithErrorHandling -Component "DialogSystem.RenderDialogs" -ScriptBlock {
        if ($script:DialogState.CurrentDialog) {
            # If it's a component with its own render method
            if ($script:DialogState.CurrentDialog.Render) {
                & $script:DialogState.CurrentDialog.Render -self $script:DialogState.CurrentDialog
            }
        }
    } -Context "Rendering current dialog" -AdditionalData @{ CurrentDialog = $script:DialogState.CurrentDialog.Name }
}

function global:Handle-DialogInput {
    <# .SYNOPSIS Engine Hook: Intercepts input if a dialog is active. #>
    param($Key)
    Invoke-WithErrorHandling -Component "DialogSystem.HandleDialogInput" -ScriptBlock {
        if ($script:DialogState.CurrentDialog) {
            if ($script:DialogState.CurrentDialog.HandleInput) {
                return & $script:DialogState.CurrentDialog.HandleInput -self $script:DialogState.CurrentDialog -Key $Key
            }
        }
        return $false
    } -Context "Handling dialog input" -AdditionalData @{ CurrentDialog = $script:DialogState.CurrentDialog.Name; Key = $Key }
}

function global:Update-DialogSystem {
    <# .SYNOPSIS Engine Hook: Updates dialog system state. #>
    Invoke-WithErrorHandling -Component "DialogSystem.UpdateDialogSystem" -ScriptBlock {
        # Placeholder for any periodic updates needed
    } -Context "Updating dialog system"
}

function global:New-TuiDialog {
    <# .SYNOPSIS Creates a simple dialog component. #>
    param([hashtable]$Props = @{})
    
    $dialog = @{
        Type = "Dialog"
        Title = if ($Props.Title) { $Props.Title } else { "Dialog" }
        Message = if ($Props.Message) { $Props.Message } else { "" }
        Buttons = if ($Props.Buttons) { $Props.Buttons } else { @("OK") }
        SelectedButton = 0
        Width = if ($Props.Width) { $Props.Width } else { 50 }
        Height = if ($Props.Height) { $Props.Height } else { 10 }
        X = 0
        Y = 0
        OnButtonClick = if ($Props.OnButtonClick) { $Props.OnButtonClick } else { {} }
        OnCancel = if ($Props.OnCancel) { $Props.OnCancel } else { {} }
        
        Render = {
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                # Center the dialog
                $self.X = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2)
                $self.Y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                
                # Draw dialog box
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -Title $self.Title -BorderColor (Get-ThemeColor "Accent")
                
                # Use engine's word wrap helper
                $messageY = $self.Y + 2
                $messageX = $self.X + 2
                $maxWidth = $self.Width - 4
                
                $wrappedLines = Get-WordWrappedLines -Text $self.Message -MaxWidth $maxWidth
                
                foreach ($line in $wrappedLines) {
                    if ($messageY -ge ($self.Y + $self.Height - 3)) { break }  # Don't overwrite buttons
                    Write-BufferString -X $messageX -Y $messageY -Text $line -ForegroundColor (Get-ThemeColor "Primary")
                    $messageY++
                }
                
                # Buttons
                $buttonY = $self.Y + $self.Height - 3
                $totalButtonWidth = ($self.Buttons.Count * 12) + (($self.Buttons.Count - 1) * 2)
                $buttonX = $self.X + [Math]::Floor(($self.Width - $totalButtonWidth) / 2)
                
                for ($i = 0; $i -lt $self.Buttons.Count; $i++) {
                    $isSelected = ($i -eq $self.SelectedButton)
                    $buttonText = if ($isSelected) { "[ $($self.Buttons[$i]) ]" } else { "  $($self.Buttons[$i])  " }
                    $color = if ($isSelected) { Get-ThemeColor "Warning" } else { Get-ThemeColor "Primary" }
                    
                    Write-BufferString -X $buttonX -Y $buttonY -Text $buttonText -ForegroundColor $color
                    $buttonX += 14
                }
            } -Context "Rendering dialog: $($self.Title)" -AdditionalData @{ DialogTitle = $self.Title; DialogMessage = $self.Message }
        }
        
        HandleInput = {
            param($self, $Key)
            Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                switch ($Key.Key) {
                    ([ConsoleKey]::LeftArrow) {
                        $self.SelectedButton = [Math]::Max(0, $self.SelectedButton - 1)
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::RightArrow) {
                        $self.SelectedButton = [Math]::Min($self.Buttons.Count - 1, $self.SelectedButton + 1)
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::Tab) {
                        $self.SelectedButton = ($self.SelectedButton + 1) % $self.Buttons.Count
                        Request-TuiRefresh
                        return $true
                    }
                    
                    ([ConsoleKey]::Enter) {
                        Invoke-WithErrorHandling -Component "$($self.Type).OnButtonClick" -ScriptBlock {
                            & $self.OnButtonClick -Button $self.Buttons[$self.SelectedButton] -Index $self.SelectedButton
                        } -Context "Dialog button clicked: $($self.Buttons[$self.SelectedButton])" -AdditionalData @{ DialogTitle = $self.Title; Button = $self.Buttons[$self.SelectedButton]; Index = $self.SelectedButton }
                        return $true
                    }
                    ([ConsoleKey]::Spacebar) {
                        Invoke-WithErrorHandling -Component "$($self.Type).OnButtonClick" -ScriptBlock {
                            & $self.OnButtonClick -Button $self.Buttons[$self.SelectedButton] -Index $self.SelectedButton
                        } -Context "Dialog button activated: $($self.Buttons[$self.SelectedButton])" -AdditionalData @{ DialogTitle = $self.Title; Button = $self.Buttons[$self.SelectedButton]; Index = $self.SelectedButton }
                        return $true
                    }
                    ([ConsoleKey]::Escape) {
                        Invoke-WithErrorHandling -Component "$($self.Type).OnCancel" -ScriptBlock {
                            & $self.OnCancel
                        } -Context "Dialog cancelled via Escape" -AdditionalData @{ DialogTitle = $self.Title }
                        return $true
                    }
                }
                
                return $false
            } -Context "Handling dialog input" -AdditionalData @{ DialogTitle = $self.Title; Key = $Key; SelectedButton = $self.SelectedButton }
        }
    }
    
    return $dialog
}

function global:Show-ProgressDialog {
    <# .SYNOPSIS Shows a progress dialog with updating percentage. #>
    param(
        [string]$Title = "Progress",
        [string]$Message = "Processing...",
        [int]$PercentComplete = 0,
        [switch]$ShowCancel
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowProgressDialog" -ScriptBlock {
        $dialog = @{
            Type = "ProgressDialog"
            Title = $Title
            Message = $Message
            PercentComplete = $PercentComplete
            Width = 60
            Height = 8
            ShowCancel = $ShowCancel
            IsCancelled = $false
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                    # Center the dialog
                    $x = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2)
                    $y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                    
                    # Draw dialog box
                    Write-BufferBox -X $x -Y $y -Width $self.Width -Height $self.Height `
                        -Title " $($self.Title) " -BorderColor (Get-ThemeColor "Accent")
                    
                    # Draw message
                    Write-BufferString -X ($x + 2) -Y ($y + 2) -Text $self.Message
                    
                    # Draw progress bar
                    $barY = $y + 4
                    $barWidth = $self.Width - 4
                    $filledWidth = [Math]::Floor($barWidth * ($self.PercentComplete / 100))
                    
                    # Progress bar background
                    Write-BufferString -X ($x + 2) -Y $barY `
                        -Text ("─" * $barWidth) -ForegroundColor (Get-ThemeColor "Border")
                    
                    # Progress bar fill
                    if ($filledWidth -gt 0) {
                        Write-BufferString -X ($x + 2) -Y $barY `
                            -Text ("█" * $filledWidth) -ForegroundColor (Get-ThemeColor "Success")
                    }
                    
                    # Percentage text
                    $percentText = "$($self.PercentComplete)%"
                    $percentX = $x + [Math]::Floor(($self.Width - $percentText.Length) / 2)
                    Write-BufferString -X $percentX -Y $barY -Text $percentText
                    
                    # Cancel button if requested
                    if ($self.ShowCancel) {
                        $buttonY = $y + $self.Height - 2
                        $buttonText = if ($self.IsCancelled) { "[ Cancelling... ]" } else { "[ Cancel ]" }
                        $buttonX = $x + [Math]::Floor(($self.Width - $buttonText.Length) / 2)
                        Write-BufferString -X $buttonX -Y $buttonY -Text $buttonText `
                            -ForegroundColor (Get-ThemeColor "Warning")
                    }
                } -Context "Rendering progress dialog" -AdditionalData @{ DialogTitle = $self.Title; Percent = $self.PercentComplete }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                    if ($self.ShowCancel -and -not $self.IsCancelled) {
                        if ($Key.Key -eq [ConsoleKey]::Escape -or 
                            $Key.Key -eq [ConsoleKey]::Enter -or 
                            $Key.Key -eq [ConsoleKey]::Spacebar) {
                            $self.IsCancelled = $true
                            Request-TuiRefresh
                            return $true
                        }
                    }
                    
                    return $false
                } -Context "Handling progress dialog input" -AdditionalData @{ DialogTitle = $self.Title; Key = $Key }
            }
            
            UpdateProgress = {
                param($self, [int]$PercentComplete, [string]$Message = $null)
                Invoke-WithErrorHandling -Component "$($self.Type).UpdateProgress" -ScriptBlock {
                    $self.PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                    if ($Message) { $self.Message = $Message }
                    Request-TuiRefresh
                } -Context "Updating progress dialog" -AdditionalData @{ DialogTitle = $self.Title; NewPercent = $PercentComplete; NewMessage = $Message }
            }
        }
        
        $script:DialogState.CurrentDialog = $dialog
        Request-TuiRefresh
        return $dialog
    } -Context "Creating progress dialog: $Title" -AdditionalData @{ Title = $Title; Message = $Message; Percent = $PercentComplete }
}

function global:Show-ListDialog {
    <# .SYNOPSIS Shows a dialog with a selectable list of items. #>
    param(
        [string]$Title = "Select Item",
        [string]$Prompt = "Choose an item:",
        [array]$Items,
        [scriptblock]$OnSelect,
        [scriptblock]$OnCancel = {},
        [switch]$AllowMultiple
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowListDialog" -ScriptBlock {
        $dialog = @{
            Type = "ListDialog"
            Title = $Title
            Prompt = $Prompt
            Items = $Items
            SelectedIndex = 0
            SelectedItems = @()
            Width = 60
            Height = [Math]::Min(20, $Items.Count + 8)
            AllowMultiple = $AllowMultiple
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                    $x = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2)
                    $y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                    
                    # Draw dialog box
                    Write-BufferBox -X $x -Y $y -Width $self.Width -Height $self.Height `
                        -Title " $($self.Title) " -BorderColor (Get-ThemeColor "Accent")
                    
                    # Draw prompt
                    Write-BufferString -X ($x + 2) -Y ($y + 2) -Text $self.Prompt
                    
                    # Calculate list area
                    $listY = $y + 4
                    $listHeight = $self.Height - 7
                    $listWidth = $self.Width - 4
                    
                    # Draw scrollable list
                    $startIndex = [Math]::Max(0, $self.SelectedIndex - [Math]::Floor($listHeight / 2))
                    $endIndex = [Math]::Min($self.Items.Count - 1, $startIndex + $listHeight - 1)
                    
                    for ($i = $startIndex; $i -le $endIndex; $i++) {
                        $itemY = $listY + ($i - $startIndex)
                        $item = $self.Items[$i]
                        $isSelected = ($i -eq $self.SelectedIndex)
                        $isChecked = $self.SelectedItems -contains $i
                        
                        # Selection indicator
                        $prefix = ""
                        if ($self.AllowMultiple) {
                            $prefix = if ($isChecked) { "[X] " } else { "[ ] " }
                        }
                        
                        $itemText = "$prefix$item"
                        if ($itemText.Length -gt $listWidth - 2) {
                            $itemText = $itemText.Substring(0, $listWidth - 5) + "..."
                        }
                        
                        $bgColor = if ($isSelected) { Get-ThemeColor "Selection" } else { $null }
                        $fgColor = if ($isSelected) { Get-ThemeColor "Background" } else { Get-ThemeColor "Primary" }
                        
                        Write-BufferString -X ($x + 2) -Y $itemY -Text $itemText `
                            -ForegroundColor $fgColor -BackgroundColor $bgColor
                    }
                    
                    # Draw scrollbar if needed
                    if ($self.Items.Count -gt $listHeight) {
                        $scrollbarX = $x + $self.Width - 2
                        $scrollbarHeight = $listHeight
                        $thumbSize = [Math]::Max(1, [Math]::Floor($scrollbarHeight * $listHeight / $self.Items.Count))
                        $thumbPos = [Math]::Floor($scrollbarHeight * $self.SelectedIndex / $self.Items.Count)
                        
                        for ($i = 0; $i -lt $scrollbarHeight; $i++) {
                            $char = if ($i -ge $thumbPos -and $i -lt ($thumbPos + $thumbSize)) { "█" } else { "│" }
                            Write-BufferString -X $scrollbarX -Y ($listY + $i) -Text $char `
                                -ForegroundColor (Get-ThemeColor "Border")
                        }
                    }
                    
                    # Draw buttons
                    $buttonY = $y + $self.Height - 2
                    if ($self.AllowMultiple) {
                        $okText = "[ OK ]"
                        $cancelText = "[ Cancel ]"
                        $buttonSpacing = 15
                        $totalWidth = 30
                        $startX = $x + [Math]::Floor(($self.Width - $totalWidth) / 2)
                        
                        Write-BufferString -X $startX -Y $buttonY -Text $okText `
                            -ForegroundColor (Get-ThemeColor "Success")
                        Write-BufferString -X ($startX + $buttonSpacing) -Y $buttonY -Text $cancelText `
                            -ForegroundColor (Get-ThemeColor "Primary")
                    }
                } -Context "Rendering list dialog" -AdditionalData @{ DialogTitle = $self.Title; Prompt = $self.Prompt; SelectedIndex = $self.SelectedIndex }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                    switch ($Key.Key) {
                        ([ConsoleKey]::UpArrow) {
                            $self.SelectedIndex = [Math]::Max(0, $self.SelectedIndex - 1)
                            Request-TuiRefresh
                            return $true
                        }
                        ([ConsoleKey]::DownArrow) {
                            $self.SelectedIndex = [Math]::Min($self.Items.Count - 1, $self.SelectedIndex + 1)
                            Request-TuiRefresh
                            return $true
                        }
                        ([ConsoleKey]::Spacebar) {
                            if ($self.AllowMultiple) {
                                if ($self.SelectedItems -contains $self.SelectedIndex) {
                                    $self.SelectedItems = $self.SelectedItems | Where-Object { $_ -ne $self.SelectedIndex }
                                } else {
                                    $self.SelectedItems += $self.SelectedIndex
                                }
                                Request-TuiRefresh
                                return $true
                            }
                        }
                        ([ConsoleKey]::Enter) {
                            Close-TuiDialog
                            if ($self.AllowMultiple) {
                                $selectedValues = $self.SelectedItems | ForEach-Object { $self.Items[$_] }
                                Invoke-WithErrorHandling -Component "ListDialog.OnSelect" -ScriptBlock {
                                    & $OnSelect -Selected $selectedValues
                                } -Context "List dialog multi-select completed" -AdditionalData @{ DialogTitle = $self.Title; SelectedValues = $selectedValues }
                            } else {
                                Invoke-WithErrorHandling -Component "ListDialog.OnSelect" -ScriptBlock {
                                    & $OnSelect -Selected $self.Items[$self.SelectedIndex]
                                } -Context "List dialog selection completed" -AdditionalData @{ DialogTitle = $self.Title; SelectedValue = $self.Items[$self.SelectedIndex] }
                            }
                            return $true
                        }
                        ([ConsoleKey]::Escape) {
                            Close-TuiDialog
                            Invoke-WithErrorHandling -Component "ListDialog.OnCancel" -ScriptBlock {
                                & $OnCancel
                            } -Context "List dialog cancelled" -AdditionalData @{ DialogTitle = $self.Title }
                            return $true
                        }
                    }
                    
                    return $false
                } -Context "Handling list dialog input" -AdditionalData @{ DialogTitle = $self.Title; Key = $Key; SelectedIndex = $self.SelectedIndex }
            }
        }
        
        $script:DialogState.CurrentDialog = $dialog
        Request-TuiRefresh
    } -Context "Creating list dialog: $Title" -AdditionalData @{ Title = $Title; Prompt = $Prompt; ItemsCount = $Items.Count }
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Initialize-DialogSystem',
    'Show-TuiDialog',
    'Close-TuiDialog',
    'Show-ConfirmDialog',
    'Show-AlertDialog',
    'Show-InputDialog',
    'Show-ProgressDialog',
    'Show-ListDialog',
    'Render-Dialogs',
    'Handle-DialogInput',
    'Update-DialogSystem',
    'New-TuiDialog'
)
