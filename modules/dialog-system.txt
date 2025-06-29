# Dialog System Module
# Uses engine's word wrap helper and respects the framework

$script:DialogState = @{
    CurrentDialog = $null
    DialogStack   = [System.Collections.Stack]::new()
}

#region --- Public API & Factory Functions ---

function Show-TuiDialog {
    <# .SYNOPSIS Internal function to display a dialog component. #>
    param([hashtable]$DialogComponent)
    Invoke-WithErrorHandling -Component "DialogSystem.ShowDialog" -ScriptBlock {
        if ($script:DialogState.CurrentDialog) {
            $script:DialogState.DialogStack.Push($script:DialogState.CurrentDialog)
        }
        $script:DialogState.CurrentDialog = $DialogComponent
        Request-TuiRefresh
    } -Context "Showing dialog: $($DialogComponent.Title)"
}

function Close-TuiDialog {
    <# .SYNOPSIS Closes the current dialog and restores the previous one, if any. #>
    Invoke-WithErrorHandling -Component "DialogSystem.CloseDialog" -ScriptBlock {
        $script:DialogState.CurrentDialog = ($script:DialogState.DialogStack.Count -gt 0) ? $script:DialogState.DialogStack.Pop() : $null
        Request-TuiRefresh
    } -Context "Closing current dialog"
}

function Show-ConfirmDialog {
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
                }
            }
            OnCancel      = { Invoke-WithErrorHandling -Component "ConfirmDialog.OnCancel" -ScriptBlock { Close-TuiDialog; & $OnCancel } }
        }
        Show-TuiDialog -DialogComponent $dialog
    } -Context "Creating confirm dialog: $Title"
}

function Show-AlertDialog {
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
            OnButtonClick = { Invoke-WithErrorHandling -Component "AlertDialog.OnButtonClick" -ScriptBlock { Close-TuiDialog } }
            OnCancel      = { Invoke-WithErrorHandling -Component "AlertDialog.OnCancel" -ScriptBlock { Close-TuiDialog } }
        }
        Show-TuiDialog -DialogComponent $dialog
    } -Context "Creating alert dialog: $Title"
}

function Show-InputDialog {
    <# .SYNOPSIS Displays a dialog to get text input from the user. #>
    param(
        [string]$Title = "Input",
        [string]$Prompt,
        [string]$DefaultValue = "",
        [scriptblock]$OnSubmit,
        [scriptblock]$OnCancel = {}
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowInputDialog" -ScriptBlock {
        $inputScreen = @{
            Name = "InputDialog"
            State = @{ InputValue = $DefaultValue; FocusedIndex = 0 }
            _focusedIndex = 0
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Name).Render" -ScriptBlock {
                    $dialogWidth = [Math]::Min(70, [Math]::Max(50, $Prompt.Length + 10))
                    $dialogHeight = 10
                    $dialogX = [Math]::Floor(($global:TuiState.BufferWidth - $dialogWidth) / 2)
                    $dialogY = [Math]::Floor(($global:TuiState.BufferHeight - $dialogHeight) / 2)
                    
                    Write-BufferBox -X $dialogX -Y $dialogY -Width $dialogWidth -Height $dialogHeight -Title " $Title " -BorderColor (Get-ThemeColor "Accent")
                    
                    $promptX = $dialogX + 2; $promptY = $dialogY + 2
                    Write-BufferString -X $promptX -Y $promptY -Text $Prompt
                    
                    $inputY = $promptY + 2; $inputWidth = $dialogWidth - 4
                    $isFocused = ($self._focusedIndex -eq 0)
                    $borderColor = $isFocused ? (Get-ThemeColor "Warning") : (Get-ThemeColor "Primary")
                    
                    Write-BufferBox -X $promptX -Y $inputY -Width $inputWidth -Height 3 -BorderColor $borderColor
                    
                    $displayText = $self.State.InputValue
                    if ($displayText.Length -gt ($inputWidth - 3)) { $displayText = $displayText.Substring(0, $inputWidth - 3) }
                    Write-BufferString -X ($promptX + 1) -Y ($inputY + 1) -Text $displayText
                    
                    if ($isFocused) {
                        $cursorPos = [Math]::Min($self.State.InputValue.Length, $inputWidth - 3)
                        Write-BufferString -X ($promptX + 1 + $cursorPos) -Y ($inputY + 1) -Text "_" -ForegroundColor (Get-ThemeColor "Warning")
                    }
                    
                    $buttonY = $dialogY + $dialogHeight - 2; $buttonSpacing = 15; $buttonsWidth = $buttonSpacing * 2
                    $buttonX = $dialogX + [Math]::Floor(($dialogWidth - $buttonsWidth) / 2)
                    
                    $okFocused = ($self._focusedIndex -eq 1)
                    $okText = $okFocused ? "[ OK ]" : "  OK  "
                    $okColor = $okFocused ? (Get-ThemeColor "Warning") : (Get-ThemeColor "Primary")
                    Write-BufferString -X $buttonX -Y $buttonY -Text $okText -ForegroundColor $okColor
                    
                    $cancelFocused = ($self._focusedIndex -eq 2)
                    $cancelText = $cancelFocused ? "[ Cancel ]" : "  Cancel  "
                    $cancelColor = $cancelFocused ? (Get-ThemeColor "Warning") : (Get-ThemeColor "Primary")
                    Write-BufferString -X ($buttonX + $buttonSpacing) -Y $buttonY -Text $cancelText -ForegroundColor $cancelColor
                }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Name).HandleInput" -ScriptBlock {
                    if ($Key.Key -eq [ConsoleKey]::Tab) {
                        $direction = $Key.Modifiers -band [ConsoleModifiers]::Shift ? -1 : 1
                        $self._focusedIndex = ($self._focusedIndex + $direction + 3) % 3
                        Request-TuiRefresh; return $true
                    }
                    if ($Key.Key -eq [ConsoleKey]::Escape) { Close-TuiDialog; Invoke-WithErrorHandling -Component "InputDialog.OnCancel" -ScriptBlock { & $OnCancel }; return $true }
                    
                    switch ($self._focusedIndex) {
                        0 { # TextBox
                            switch ($Key.Key) {
                                ([ConsoleKey]::Enter) { Close-TuiDialog; Invoke-WithErrorHandling -Component "InputDialog.OnSubmit" -ScriptBlock { & $OnSubmit -Value $self.State.InputValue }; return $true }
                                ([ConsoleKey]::Backspace) { if ($self.State.InputValue.Length -gt 0) { $self.State.InputValue = $self.State.InputValue.Substring(0, $self.State.InputValue.Length - 1); Request-TuiRefresh }; return $true }
                                default { if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) { $self.State.InputValue += $Key.KeyChar; Request-TuiRefresh; return $true } }
                            }
                        }
                        1 { # OK Button
                            if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) { Close-TuiDialog; Invoke-WithErrorHandling -Component "InputDialog.OnSubmit" -ScriptBlock { & $OnSubmit -Value $self.State.InputValue }; return $true }
                        }
                        2 { # Cancel Button
                            if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) { Close-TuiDialog; Invoke-WithErrorHandling -Component "InputDialog.OnCancel" -ScriptBlock { & $OnCancel }; return $true }
                        }
                    }
                    return $false
                }
            }
        }
        $script:DialogState.CurrentDialog = $inputScreen
        Request-TuiRefresh
    } -Context "Creating input dialog: $Title"
}

#endregion

#region --- Engine Integration & Initialization ---

function Initialize-DialogSystem {
    Invoke-WithErrorHandling -Component "DialogSystem.Initialize" -ScriptBlock {
        Subscribe-Event -EventName "Confirm.Request" -Handler { param($EventData) Invoke-WithErrorHandling -Component "DialogSystem.ConfirmEventHandler" -ScriptBlock { Show-ConfirmDialog @$EventData.Data } }
        Subscribe-Event -EventName "Alert.Show" -Handler { param($EventData) Invoke-WithErrorHandling -Component "DialogSystem.AlertEventHandler" -ScriptBlock { Show-AlertDialog @$EventData.Data } }
        Subscribe-Event -EventName "Input.Request" -Handler { param($EventData) Invoke-WithErrorHandling -Component "DialogSystem.InputEventHandler" -ScriptBlock { Show-InputDialog @$EventData.Data } }
        Write-Verbose "Dialog System initialized and event handlers registered."
    } -Context "Initializing Dialog System"
}

function Render-Dialogs {
    Invoke-WithErrorHandling -Component "DialogSystem.RenderDialogs" -ScriptBlock {
        if ($script:DialogState.CurrentDialog -and $script:DialogState.CurrentDialog.Render) {
            & $script:DialogState.CurrentDialog.Render -self $script:DialogState.CurrentDialog
        }
    } -Context "Rendering current dialog"
}

function Handle-DialogInput {
    param($Key)
    return Invoke-WithErrorHandling -Component "DialogSystem.HandleDialogInput" -ScriptBlock {
        if ($script:DialogState.CurrentDialog -and $script:DialogState.CurrentDialog.HandleInput) {
            return & $script:DialogState.CurrentDialog.HandleInput -self $script:DialogState.CurrentDialog -Key $Key
        }
        return $false
    } -Context "Handling dialog input"
}

function Update-DialogSystem {
    Invoke-WithErrorHandling -Component "DialogSystem.UpdateDialogSystem" -ScriptBlock {
        # Placeholder for periodic updates
    } -Context "Updating dialog system"
}

function New-TuiDialog {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Dialog"
        Title = $Props.Title ?? "Dialog"
        Message = $Props.Message ?? ""
        Buttons = $Props.Buttons ?? @("OK")
        SelectedButton = 0
        Width = $Props.Width ?? 50
        Height = $Props.Height ?? 10
        X = 0; Y = 0
        OnButtonClick = $Props.OnButtonClick ?? {}
        OnCancel = $Props.OnCancel ?? {}
        
        Render = {
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                $self.X = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2)
                $self.Y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height -Title $self.Title -BorderColor (Get-ThemeColor "Accent")
                
                $messageY = $self.Y + 2; $messageX = $self.X + 2; $maxWidth = $self.Width - 4
                $wrappedLines = Get-WordWrappedLines -Text $self.Message -MaxWidth $maxWidth
                
                foreach ($line in $wrappedLines) {
                    if ($messageY -ge ($self.Y + $self.Height - 3)) { break }
                    Write-BufferString -X $messageX -Y $messageY -Text $line -ForegroundColor (Get-ThemeColor "Primary")
                    $messageY++
                }
                
                $buttonY = $self.Y + $self.Height - 3
                $totalButtonWidth = ($self.Buttons.Count * 12) + (($self.Buttons.Count - 1) * 2)
                $buttonX = $self.X + [Math]::Floor(($self.Width - $totalButtonWidth) / 2)
                
                for ($i = 0; $i -lt $self.Buttons.Count; $i++) {
                    $button = $self.Buttons[$i]
                    $isSelected = ($i -eq $self.SelectedButton)
                    $buttonText = $isSelected ? "[ $($button) ]" : "  $($button)  "
                    $color = $isSelected ? (Get-ThemeColor "Warning") : (Get-ThemeColor "Primary")
                    Write-BufferString -X $buttonX -Y $buttonY -Text $buttonText -ForegroundColor $color
                    $buttonX += 14
                }
            }
        }
        
        HandleInput = {
            param($self, $Key)
            Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                switch ($Key.Key) {
                    ([ConsoleKey]::LeftArrow) { $self.SelectedButton = [Math]::Max(0, $self.SelectedButton - 1); Request-TuiRefresh; return $true }
                    ([ConsoleKey]::RightArrow) { $self.SelectedButton = [Math]::Min($self.Buttons.Count - 1, $self.SelectedButton + 1); Request-TuiRefresh; return $true }
                    ([ConsoleKey]::Tab) { $self.SelectedButton = ($self.SelectedButton + 1) % $self.Buttons.Count; Request-TuiRefresh; return $true }
                    ([ConsoleKey]::Enter) { & $self.OnButtonClick -Button $self.Buttons[$self.SelectedButton] -Index $self.SelectedButton; return $true }
                    ([ConsoleKey]::Spacebar) { & $self.OnButtonClick -Button $self.Buttons[$self.SelectedButton] -Index $self.SelectedButton; return $true }
                    ([ConsoleKey]::Escape) { & $self.OnCancel; return $true }
                }
                return $false
            }
        }
    }
}

function Show-ProgressDialog {
    param(
        [string]$Title = "Progress",
        [string]$Message = "Processing...",
        [int]$PercentComplete = 0,
        [switch]$ShowCancel
    )
    Invoke-WithErrorHandling -Component "DialogSystem.ShowProgressDialog" -ScriptBlock {
        $dialog = @{
            Type = "ProgressDialog"; Title = $Title; Message = $Message; PercentComplete = $PercentComplete
            Width = 60; Height = 8; ShowCancel = $ShowCancel; IsCancelled = $false
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                    $x = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2); $y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                    Write-BufferBox -X $x -Y $y -Width $self.Width -Height $self.Height -Title " $($self.Title) " -BorderColor (Get-ThemeColor "Accent")
                    Write-BufferString -X ($x + 2) -Y ($y + 2) -Text $self.Message
                    
                    $barY = $y + 4; $barWidth = $self.Width - 4; $filledWidth = [Math]::Floor($barWidth * ($self.PercentComplete / 100))
                    Write-BufferString -X ($x + 2) -Y $barY -Text ("─" * $barWidth) -ForegroundColor (Get-ThemeColor "Border")
                    if ($filledWidth -gt 0) { Write-BufferString -X ($x + 2) -Y $barY -Text ("█" * $filledWidth) -ForegroundColor (Get-ThemeColor "Success") }
                    
                    $percentText = "$($self.PercentComplete)%"; $percentX = $x + [Math]::Floor(($self.Width - $percentText.Length) / 2)
                    Write-BufferString -X $percentX -Y $barY -Text $percentText
                    
                    if ($self.ShowCancel) {
                        $buttonY = $y + $self.Height - 2; $buttonText = $self.IsCancelled ? "[ Cancelling... ]" : "[ Cancel ]"
                        $buttonX = $x + [Math]::Floor(($self.Width - $buttonText.Length) / 2)
                        Write-BufferString -X $buttonX -Y $buttonY -Text $buttonText -ForegroundColor (Get-ThemeColor "Warning")
                    }
                }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                    if ($self.ShowCancel -and -not $self.IsCancelled -and $Key.Key -in @([ConsoleKey]::Escape, [ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
                        $self.IsCancelled = $true; Request-TuiRefresh; return $true
                    }
                    return $false
                }
            }
            
            UpdateProgress = {
                param($self, [int]$PercentComplete, [string]$Message = $null)
                Invoke-WithErrorHandling -Component "$($self.Type).UpdateProgress" -ScriptBlock {
                    $self.PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                    if ($Message) { $self.Message = $Message }
                    Request-TuiRefresh
                }
            }
        }
        $script:DialogState.CurrentDialog = $dialog
        Request-TuiRefresh
        return $dialog
    } -Context "Creating progress dialog: $Title"
}

function Show-ListDialog {
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
            Type = "ListDialog"; Title = $Title; Prompt = $Prompt; Items = $Items; SelectedIndex = 0; SelectedItems = @()
            Width = 60; Height = [Math]::Min(20, $Items.Count + 8); AllowMultiple = $AllowMultiple
            
            Render = {
                param($self)
                Invoke-WithErrorHandling -Component "$($self.Type).Render" -ScriptBlock {
                    $x = [Math]::Floor(($global:TuiState.BufferWidth - $self.Width) / 2); $y = [Math]::Floor(($global:TuiState.BufferHeight - $self.Height) / 2)
                    Write-BufferBox -X $x -Y $y -Width $self.Width -Height $self.Height -Title " $($self.Title) " -BorderColor (Get-ThemeColor "Accent")
                    Write-BufferString -X ($x + 2) -Y ($y + 2) -Text $self.Prompt
                    
                    $listY = $y + 4; $listHeight = $self.Height - 7; $listWidth = $self.Width - 4
                    $startIndex = [Math]::Max(0, $self.SelectedIndex - [Math]::Floor($listHeight / 2))
                    $endIndex = [Math]::Min($self.Items.Count - 1, $startIndex + $listHeight - 1)
                    
                    for ($i = $startIndex; $i -le $endIndex; $i++) {
                        $itemY = $listY + ($i - $startIndex); $item = $self.Items[$i]
                        $isSelected = ($i -eq $self.SelectedIndex); $isChecked = $self.SelectedItems -contains $i
                        $prefix = $self.AllowMultiple ? ($isChecked ? "[X] " : "[ ] ") : ""
                        $itemText = "$prefix$item"
                        if ($itemText.Length -gt $listWidth - 2) { $itemText = $itemText.Substring(0, $listWidth - 5) + "..." }
                        
                        $bgColor = $isSelected ? (Get-ThemeColor "Selection") : $null
                        $fgColor = $isSelected ? (Get-ThemeColor "Background") : (Get-ThemeColor "Primary")
                        Write-BufferString -X ($x + 2) -Y $itemY -Text $itemText -ForegroundColor $fgColor -BackgroundColor $bgColor
                    }
                    
                    if ($self.Items.Count -gt $listHeight) {
                        $scrollbarX = $x + $self.Width - 2; $scrollbarHeight = $listHeight
                        $thumbSize = [Math]::Max(1, [Math]::Floor($scrollbarHeight * $listHeight / $self.Items.Count))
                        $thumbPos = [Math]::Floor($scrollbarHeight * $self.SelectedIndex / $self.Items.Count)
                        for ($i = 0; $i -lt $scrollbarHeight; $i++) { $char = ($i -ge $thumbPos -and $i -lt ($thumbPos + $thumbSize)) ? "█" : "│"; Write-BufferString -X $scrollbarX -Y ($listY + $i) -Text $char -ForegroundColor (Get-ThemeColor "Border") }
                    }
                    
                    if ($self.AllowMultiple) {
                        $buttonY = $y + $self.Height - 2; $okText = "[ OK ]"; $cancelText = "[ Cancel ]"; $buttonSpacing = 15; $totalWidth = 30; $startX = $x + [Math]::Floor(($self.Width - $totalWidth) / 2)
                        Write-BufferString -X $startX -Y $buttonY -Text $okText -ForegroundColor (Get-ThemeColor "Success")
                        Write-BufferString -X ($startX + $buttonSpacing) -Y $buttonY -Text $cancelText -ForegroundColor (Get-ThemeColor "Primary")
                    }
                }
            }
            
            HandleInput = {
                param($self, $Key)
                Invoke-WithErrorHandling -Component "$($self.Type).HandleInput" -ScriptBlock {
                    switch ($Key.Key) {
                        ([ConsoleKey]::UpArrow) { $self.SelectedIndex = [Math]::Max(0, $self.SelectedIndex - 1); Request-TuiRefresh; return $true }
                        ([ConsoleKey]::DownArrow) { $self.SelectedIndex = [Math]::Min($self.Items.Count - 1, $self.SelectedIndex + 1); Request-TuiRefresh; return $true }
                        ([ConsoleKey]::Spacebar) { if ($self.AllowMultiple) { if ($self.SelectedItems -contains $self.SelectedIndex) { $self.SelectedItems = $self.SelectedItems | Where-Object { $_ -ne $self.SelectedIndex } } else { $self.SelectedItems += $self.SelectedIndex }; Request-TuiRefresh; return $true } }
                        ([ConsoleKey]::Enter) {
                            Close-TuiDialog
                            if ($self.AllowMultiple) { $selectedValues = $self.SelectedItems | ForEach-Object { $self.Items[$_] }; & $OnSelect -Selected $selectedValues } 
                            else { & $OnSelect -Selected $self.Items[$self.SelectedIndex] }
                            return $true
                        }
                        ([ConsoleKey]::Escape) { Close-TuiDialog; & $OnCancel; return $true }
                    }
                    return $false
                }
            }
        }
        $script:DialogState.CurrentDialog = $dialog
        Request-TuiRefresh
    } -Context "Creating list dialog: $Title"
}

#endregion

Export-ModuleMember -Function 'Initialize-DialogSystem', 'Show-TuiDialog', 'Close-TuiDialog', 'Show-ConfirmDialog', 'Show-AlertDialog', 'Show-InputDialog', 'Show-ProgressDialog', 'Show-ListDialog', 'Render-Dialogs', 'Handle-DialogInput', 'Update-DialogSystem', 'New-TuiDialog'
