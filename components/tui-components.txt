# TUI Component Library
# Stateful component factories following the canonical architecture

#region Basic Components

function New-TuiLabel {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Label"
        IsFocusable = $false
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 10
        Height = $Props.Height ?? 1
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Text = $Props.Text ?? ""
        ForegroundColor = $Props.ForegroundColor
        Name = $Props.Name
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                $fg = $self.ForegroundColor ?? (Get-ThemeColor "Primary")
                Write-BufferString -X $self.X -Y $self.Y -Text $self.Text -ForegroundColor $fg
            } catch { Write-Log -Level Error -Message "Label Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = { param($self, $Key) return $false }
    }
}

function New-TuiButton {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Button"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 10
        Height = $Props.Height ?? 3
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Text = $Props.Text ?? "Button"
        Name = $Props.Name
        IsPressed = $false
        OnClick = $Props.OnClick
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Primary")
                $bgColor = $self.IsPressed ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Background")
                $fgColor = $self.IsPressed ? (Get-ThemeColor "Background") : $borderColor
                
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height -BorderColor $borderColor -BackgroundColor $bgColor
                $textX = $self.X + [Math]::Floor(($self.Width - $self.Text.Length) / 2)
                Write-BufferString -X $textX -Y ($self.Y + 1) -Text $self.Text -ForegroundColor $fgColor -BackgroundColor $bgColor
            } catch { Write-Log -Level Error -Message "Button Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
                    if ($self.OnClick) { Invoke-WithErrorHandling -Component "$($self.Name).OnClick" -ScriptBlock { & $self.OnClick } }
                    Request-TuiRefresh
                    return $true
                }
            } catch { Write-Log -Level Error -Message "Button HandleInput error for '$($self.Name)': $_" }
            return $false
        }
    }
}

function New-TuiTextBox {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "TextBox"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 20
        Height = $Props.Height ?? 3
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Text = $Props.Text ?? ""
        Placeholder = $Props.Placeholder ?? ""
        MaxLength = $Props.MaxLength ?? 100
        Name = $Props.Name
        CursorPosition = $Props.CursorPosition ?? 0
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height 3 -BorderColor $borderColor
                
                $displayText = $self.Text ?? ""
                if ([string]::IsNullOrEmpty($displayText) -and -not $self.IsFocused) { $displayText = $self.Placeholder ?? "" }
                
                $maxDisplayLength = $self.Width - 4
                if ($displayText.Length -gt $maxDisplayLength) { $displayText = $displayText.Substring(0, $maxDisplayLength) }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $displayText
                
                if ($self.IsFocused -and $self.CursorPosition -le $displayText.Length) {
                    $cursorX = $self.X + 2 + $self.CursorPosition
                    Write-BufferString -X $cursorX -Y ($self.Y + 1) -Text "_" -BackgroundColor (Get-ThemeColor "Accent")
                }
            } catch { Write-Log -Level Error -Message "TextBox Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $text = $self.Text ?? ""
                $cursorPos = $self.CursorPosition ?? 0
                $oldText = $text
                
                switch ($Key.Key) {
                    ([ConsoleKey]::Backspace) { if ($cursorPos -gt 0) { $text = $text.Remove($cursorPos - 1, 1); $cursorPos-- } }
                    ([ConsoleKey]::Delete) { if ($cursorPos -lt $text.Length) { $text = $text.Remove($cursorPos, 1) } }
                    ([ConsoleKey]::LeftArrow) { if ($cursorPos -gt 0) { $cursorPos-- } }
                    ([ConsoleKey]::RightArrow) { if ($cursorPos -lt $text.Length) { $cursorPos++ } }
                    ([ConsoleKey]::Home) { $cursorPos = 0 }
                    ([ConsoleKey]::End) { $cursorPos = $text.Length }
                    ([ConsoleKey]::V) {
                        if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                            try {
                                $clipboardText = Get-Clipboard -Format Text -ErrorAction SilentlyContinue
                                if ($clipboardText) {
                                    $clipboardText = $clipboardText -replace '[\r\n]+', ' '
                                    $remainingSpace = $self.MaxLength - $text.Length
                                    if ($remainingSpace -gt 0) {
                                        $toInsert = $clipboardText.Length -gt $remainingSpace ? $clipboardText.Substring(0, $remainingSpace) : $clipboardText
                                        $text = $text.Insert($cursorPos, $toInsert)
                                        $cursorPos += $toInsert.Length
                                    }
                                }
                            } catch { Write-Log -Level Warning -Message "TextBox clipboard paste error for '$($self.Name)': $_" }
                        } else {
                            if (-not [char]::IsControl($Key.KeyChar) -and $text.Length -lt $self.MaxLength) { $text = $text.Insert($cursorPos, $Key.KeyChar); $cursorPos++ } 
                            else { return $false }
                        }
                    }
                    default {
                        if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar) -and $text.Length -lt $self.MaxLength) { $text = $text.Insert($cursorPos, $Key.KeyChar); $cursorPos++ } 
                        else { return $false }
                    }
                }
                
                if ($text -ne $oldText -or $cursorPos -ne $self.CursorPosition) {
                    $self.Text = $text
                    $self.CursorPosition = $cursorPos
                    if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewValue $text } }
                    Request-TuiRefresh
                }
                return $true
            } catch { Write-Log -Level Error -Message "TextBox HandleInput error for '$($self.Name)': $_"; return $false }
        }
    }
}

function New-TuiCheckBox {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "CheckBox"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 20
        Height = $Props.Height ?? 1
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Text = $Props.Text ?? "Checkbox"
        Checked = $Props.Checked ?? $false
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                $fg = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Primary")
                $checkbox = $self.Checked ? "[X]" : "[ ]"
                Write-BufferString -X $self.X -Y $self.Y -Text "$checkbox $($self.Text)" -ForegroundColor $fg
            } catch { Write-Log -Level Error -Message "CheckBox Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
                    $self.Checked = -not $self.Checked
                    if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewValue $self.Checked } }
                    Request-TuiRefresh
                    return $true
                }
            } catch { Write-Log -Level Error -Message "CheckBox HandleInput error for '$($self.Name)': $_" }
            return $false
        }
    }
}

function New-TuiDropdown {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Dropdown"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 20
        Height = $Props.Height ?? 3
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 10
        Options = $Props.Options ?? @()
        Value = $Props.Value
        Placeholder = $Props.Placeholder ?? "Select..."
        Name = $Props.Name
        IsOpen = $false
        SelectedIndex = 0
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height 3 -BorderColor $borderColor
                
                $displayText = $self.Placeholder
                if ($self.Value -and $self.Options) {
                    $selected = $self.Options | Where-Object { $_.Value -eq $self.Value } | Select-Object -First 1
                    if ($selected) { $displayText = $selected.Display }
                }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $displayText
                $indicator = $self.IsOpen ? "▲" : "▼"
                Write-BufferString -X ($self.X + $self.Width - 3) -Y ($self.Y + 1) -Text $indicator
                
                if ($self.IsOpen -and $self.Options.Count -gt 0) {
                    $listHeight = [Math]::Min($self.Options.Count + 2, 8)
                    Write-BufferBox -X $self.X -Y ($self.Y + 3) -Width $self.Width -Height $listHeight -BorderColor $borderColor -BackgroundColor (Get-ThemeColor "Background")
                    
                    $displayCount = [Math]::Min($self.Options.Count, 6)
                    for ($i = 0; $i -lt $displayCount; $i++) {
                        $option = $self.Options[$i]
                        $y = $self.Y + 4 + $i
                        $fg = ($i -eq $self.SelectedIndex) ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Primary")
                        $bg = ($i -eq $self.SelectedIndex) ? (Get-ThemeColor "Secondary") : (Get-ThemeColor "Background")
                        $text = $option.Display
                        if ($text.Length -gt ($self.Width - 4)) { $text = $text.Substring(0, $self.Width - 7) + "..." }
                        Write-BufferString -X ($self.X + 2) -Y $y -Text $text -ForegroundColor $fg -BackgroundColor $bg
                    }
                }
            } catch { Write-Log -Level Error -Message "Dropdown Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if (-not $self.IsOpen) {
                    if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar, [ConsoleKey]::DownArrow)) {
                        $self.IsOpen = $true
                        Request-TuiRefresh
                        return $true
                    }
                } else {
                    switch ($Key.Key) {
                        ([ConsoleKey]::UpArrow) { if ($self.SelectedIndex -gt 0) { $self.SelectedIndex--; Request-TuiRefresh }; return $true }
                        ([ConsoleKey]::DownArrow) { if ($self.SelectedIndex -lt ($self.Options.Count - 1)) { $self.SelectedIndex++; Request-TuiRefresh }; return $true }
                        ([ConsoleKey]::Enter) {
                            if ($self.Options.Count -gt 0) {
                                $selected = $self.Options[$self.SelectedIndex]
                                $self.Value = $selected.Value
                                if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewValue $selected.Value } }
                            }
                            $self.IsOpen = $false
                            Request-TuiRefresh
                            return $true
                        }
                        ([ConsoleKey]::Escape) { $self.IsOpen = $false; Request-TuiRefresh; return $true }
                    }
                }
            } catch { Write-Log -Level Error -Message "Dropdown HandleInput error for '$($self.Name)': $_" }
            return $false
        }
    }
}

function New-TuiProgressBar {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "ProgressBar"
        IsFocusable = $false
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 20
        Height = $Props.Height ?? 1
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Value = $Props.Value ?? 0
        Max = $Props.Max ?? 100
        ShowPercent = $Props.ShowPercent ?? $false
        Name = $Props.Name
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $percent = [Math]::Min(100, [Math]::Max(0, ($self.Value / $self.Max) * 100))
                $filled = [Math]::Floor(($self.Width - 2) * ($percent / 100))
                $empty = ($self.Width - 2) - $filled
                
                $bar = "█" * $filled + "░" * $empty
                Write-BufferString -X $self.X -Y $self.Y -Text "[$bar]" -ForegroundColor (Get-ThemeColor "Accent")
                
                if ($self.ShowPercent) {
                    $percentText = "$([Math]::Round($percent))%"
                    $textX = $self.X + [Math]::Floor(($self.Width - $percentText.Length) / 2)
                    Write-BufferString -X $textX -Y $self.Y -Text $percentText -ForegroundColor (Get-ThemeColor "Primary")
                }
            } catch { Write-Log -Level Error -Message "ProgressBar Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = { param($self, $Key) return $false }
    }
}

function New-TuiTextArea {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "TextArea"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 40
        Height = $Props.Height ?? 6
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Text = $Props.Text ?? ""
        Placeholder = $Props.Placeholder ?? "Enter text..."
        WrapText = $Props.WrapText ?? $true
        Name = $Props.Name
        Lines = ($Props.Text ?? "") -split "`n"
        CursorX = 0
        CursorY = 0
        ScrollOffset = 0
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height -BorderColor $borderColor
                
                $innerWidth = $self.Width - 4
                $innerHeight = $self.Height - 2
                $displayLines = if ($self.WrapText) {
                    $self.Lines | ForEach-Object { Get-WordWrappedLines -Text $_ -MaxWidth $innerWidth }
                } else {
                    $self.Lines
                }
                
                if ($displayLines.Count -eq 1 -and $displayLines[0] -eq "" -and -not $self.IsFocused) {
                    Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $self.Placeholder
                    return
                }
                
                $startLine = $self.ScrollOffset
                $endLine = [Math]::Min($displayLines.Count - 1, $startLine + $innerHeight - 1)
                
                for ($i = $startLine; $i -le $endLine; $i++) {
                    $y = $self.Y + 1 + ($i - $startLine)
                    $line = $displayLines[$i]
                    Write-BufferString -X ($self.X + 2) -Y $y -Text $line
                }
                
                if ($self.IsFocused -and $self.CursorY -ge $startLine -and $self.CursorY -le $endLine) {
                    $cursorScreenY = $self.Y + 1 + ($self.CursorY - $startLine)
                    $cursorX = [Math]::Min($self.CursorX, $displayLines[$self.CursorY].Length)
                    Write-BufferString -X ($self.X + 2 + $cursorX) -Y $cursorScreenY -Text "_" -BackgroundColor (Get-ThemeColor "Accent")
                }
                
                if ($displayLines.Count -gt $innerHeight) {
                    $scrollbarHeight = $innerHeight
                    $scrollPosition = [Math]::Floor(($self.ScrollOffset / ($displayLines.Count - $innerHeight)) * ($scrollbarHeight - 1))
                    for ($i = 0; $i -lt $scrollbarHeight; $i++) {
                        $char = ($i -eq $scrollPosition) ? "█" : "│"
                        $color = ($i -eq $scrollPosition) ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Subtle")
                        Write-BufferString -X ($self.X + $self.Width - 2) -Y ($self.Y + 1 + $i) -Text $char -ForegroundColor $color
                    }
                }
            } catch { Write-Log -Level Error -Message "TextArea Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $lines = $self.Lines
                $cursorY = $self.CursorY
                $cursorX = $self.CursorX
                $innerHeight = $self.Height - 2
                
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow) { if ($cursorY -gt 0) { $cursorY--; $cursorX = [Math]::Min($cursorX, $lines[$cursorY].Length); if ($cursorY -lt $self.ScrollOffset) { $self.ScrollOffset = $cursorY } } }
                    ([ConsoleKey]::DownArrow) { if ($cursorY -lt $lines.Count - 1) { $cursorY++; $cursorX = [Math]::Min($cursorX, $lines[$cursorY].Length); if ($cursorY -ge $self.ScrollOffset + $innerHeight) { $self.ScrollOffset = $cursorY - $innerHeight + 1 } } }
                    ([ConsoleKey]::LeftArrow) { if ($cursorX -gt 0) { $cursorX-- } elseif ($cursorY -gt 0) { $cursorY--; $cursorX = $lines[$cursorY].Length } }
                    ([ConsoleKey]::RightArrow) { if ($cursorX -lt $lines[$cursorY].Length) { $cursorX++ } elseif ($cursorY -lt $lines.Count - 1) { $cursorY++; $cursorX = 0 } }
                    ([ConsoleKey]::Home) { $cursorX = 0 }
                    ([ConsoleKey]::End) { $cursorX = $lines[$cursorY].Length }
                    ([ConsoleKey]::Enter) {
                        $currentLine = $lines[$cursorY]
                        $beforeCursor = $currentLine.Substring(0, $cursorX)
                        $afterCursor = $currentLine.Substring($cursorX)
                        $lines[$cursorY] = $beforeCursor
                        $lines = @($lines[0..$cursorY]) + @($afterCursor) + @($lines[($cursorY + 1)..($lines.Count - 1)])
                        $cursorY++; $cursorX = 0
                        if ($cursorY -ge $self.ScrollOffset + $innerHeight) { $self.ScrollOffset = $cursorY - $innerHeight + 1 }
                    }
                    ([ConsoleKey]::Backspace) {
                        if ($cursorX -gt 0) { $lines[$cursorY] = $lines[$cursorY].Remove($cursorX - 1, 1); $cursorX-- } 
                        elseif ($cursorY -gt 0) {
                            $prevLineLength = $lines[$cursorY - 1].Length; $lines[$cursorY - 1] += $lines[$cursorY]
                            $lines = @($lines | Where-Object { $_ -ne $lines[$cursorY] }); $cursorY--; $cursorX = $prevLineLength
                        }
                    }
                    ([ConsoleKey]::Delete) {
                        if ($cursorX -lt $lines[$cursorY].Length) { $lines[$cursorY] = $lines[$cursorY].Remove($cursorX, 1) } 
                        elseif ($cursorY -lt $lines.Count - 1) {
                            $lines[$cursorY] += $lines[$cursorY + 1]; $lines = @($lines | Where-Object { $_ -ne $lines[$cursorY + 1] })
                        }
                    }
                    ([ConsoleKey]::V) {
                        if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                            try {
                                $clipboardText = Get-Clipboard -Format Text -ErrorAction SilentlyContinue
                                if ($clipboardText) {
                                    $clipboardLines = $clipboardText -split '[\r\n]+'
                                    if ($clipboardLines.Count -eq 1) {
                                        $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $clipboardLines[0]); $cursorX += $clipboardLines[0].Length
                                    } else {
                                        $currentLine = $lines[$cursorY]; $beforeCursor = $currentLine.Substring(0, $cursorX); $afterCursor = $currentLine.Substring($cursorX)
                                        $lines[$cursorY] = $beforeCursor + $clipboardLines[0]
                                        $insertLines = $clipboardLines[1..($clipboardLines.Count - 2)] + ($clipboardLines[-1] + $afterCursor)
                                        $newLines = @($lines[0..$cursorY]) + $insertLines + @($lines[($cursorY + 1)..($lines.Count - 1)])
                                        $lines = $newLines; $cursorY += $clipboardLines.Count - 1; $cursorX = $clipboardLines[-1].Length
                                    }
                                    if ($cursorY -ge $self.ScrollOffset + $innerHeight) { $self.ScrollOffset = $cursorY - $innerHeight + 1 }
                                }
                            } catch { Write-Log -Level Warning -Message "TextArea clipboard paste error for '$($self.Name)': $_" }
                        } else {
                            if (-not [char]::IsControl($Key.KeyChar)) { $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $Key.KeyChar); $cursorX++ } 
                            else { return $false }
                        }
                    }
                    default {
                        if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) { $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $Key.KeyChar); $cursorX++ } 
                        else { return $false }
                    }
                }
                
                $self.Lines = $lines; $self.CursorX = $cursorX; $self.CursorY = $cursorY; $self.Text = $lines -join "`n"
                if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewValue $self.Text } }
                Request-TuiRefresh
                return $true
            } catch { Write-Log -Level Error -Message "TextArea HandleInput error for '$($self.Name)': $_"; return $false }
        }
    }
    
    return $component
}

#endregion

#region DateTime Components

function New-TuiDatePicker {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "DatePicker"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 20
        Height = $Props.Height ?? 3
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Value = $Props.Value ?? (Get-Date)
        Format = $Props.Format ?? "yyyy-MM-dd"
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height 3 -BorderColor $borderColor
                $dateStr = $self.Value.ToString($self.Format)
                
                $maxLength = $self.Width - 6
                if ($dateStr.Length -gt $maxLength) { $dateStr = $dateStr.Substring(0, $maxLength) }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $dateStr
                if ($self.IsFocused -and $self.Width -ge 6) { Write-BufferString -X ($self.X + $self.Width - 4) -Y ($self.Y + 1) -Text "📅" -ForegroundColor $borderColor }
            } catch { Write-Log -Level Error -Message "DatePicker Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $date = $self.Value
                $handled = $true
                
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow)   { $date = $date.AddDays(1) }
                    ([ConsoleKey]::DownArrow) { $date = $date.AddDays(-1) }
                    ([ConsoleKey]::PageUp)    { $date = $date.AddMonths(1) }
                    ([ConsoleKey]::PageDown)  { $date = $date.AddMonths(-1) }
                    ([ConsoleKey]::Home)      { $date = Get-Date }
                    ([ConsoleKey]::T) { if ($Key.Modifiers -band [ConsoleModifiers]::Control) { $date = Get-Date } else { $handled = $false } }
                    default { $handled = $false }
                }
                
                if ($handled) {
                    $self.Value = $date
                    if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewValue $date } }
                    Request-TuiRefresh
                }
                return $handled
            } catch { Write-Log -Level Error -Message "DatePicker HandleInput error for '$($self.Name)': $_"; return $false }
        }
    }
}

function New-TuiTimePicker {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "TimePicker"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 15
        Height = $Props.Height ?? 3
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Hour = $Props.Hour ?? 0
        Minute = $Props.Minute ?? 0
        Format24H = $Props.Format24H ?? $true
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height 3 -BorderColor $borderColor
                
                $timeStr = if ($self.Format24H) { 
                    "{0:D2}:{1:D2}" -f $self.Hour, $self.Minute 
                } else {
                    $displayHour = if ($self.Hour -eq 0) { 12 } elseif ($self.Hour -gt 12) { $self.Hour - 12 } else { $self.Hour }
                    $ampm = ($self.Hour -lt 12) ? "AM" : "PM"
                    "{0:D2}:{1:D2} {2}" -f $displayHour, $self.Minute, $ampm
                }
                
                $maxLength = $self.Width - 6
                if ($timeStr.Length -gt $maxLength) { $timeStr = $timeStr.Substring(0, $maxLength) }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $timeStr
                if ($self.IsFocused -and $self.Width -ge 6) { Write-BufferString -X ($self.X + $self.Width - 4) -Y ($self.Y + 1) -Text "⏰" -ForegroundColor $borderColor }
            } catch { Write-Log -Level Error -Message "TimePicker Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $handled = $true; $hour = $self.Hour; $minute = $self.Minute
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow) { $minute = ($minute + 15) % 60; if ($minute -eq 0) { $hour = ($hour + 1) % 24 } }
                    ([ConsoleKey]::DownArrow) { $minute = ($minute - 15 + 60) % 60; if ($minute -eq 45) { $hour = ($hour - 1 + 24) % 24 } }
                    ([ConsoleKey]::LeftArrow)  { $hour = ($hour - 1 + 24) % 24 }
                    ([ConsoleKey]::RightArrow) { $hour = ($hour + 1) % 24 }
                    default { $handled = $false }
                }
                if ($handled) {
                    $self.Hour = $hour; $self.Minute = $minute
                    if ($self.OnChange) { Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock { & $self.OnChange -NewHour $hour -NewMinute $minute } }
                    Request-TuiRefresh
                }
                return $handled
            } catch { Write-Log -Level Error -Message "TimePicker HandleInput error for '$($self.Name)': $_"; return $false }
        }
    }
}

#endregion

#region Data Display Components

function New-TuiTable {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Table"
        IsFocusable = $true
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 60
        Height = $Props.Height ?? 15
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        Columns = $Props.Columns ?? @()
        Rows = $Props.Rows ?? @()
        Name = $Props.Name
        SelectedRow = 0
        ScrollOffset = 0
        SortColumn = $null
        SortAscending = $true
        OnRowSelect = $Props.OnRowSelect
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible -or $self.Columns.Count -eq 0) { return }
                
                $borderColor = $self.IsFocused ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Secondary")
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height -BorderColor $borderColor
                
                $totalWidth = $self.Width - 4; $colWidth = [Math]::Floor($totalWidth / $self.Columns.Count); $headerY = $self.Y + 1; $currentX = $self.X + 2
                
                foreach ($col in $self.Columns) {
                    $header = $col.Header
                    if ($col.Name -eq $self.SortColumn) { $header += $self.SortAscending ? " ▲" : " ▼" }
                    if ($header.Length -gt $colWidth - 1) { $header = $header.Substring(0, $colWidth - 4) + "..." }
                    Write-BufferString -X $currentX -Y $headerY -Text $header -ForegroundColor (Get-ThemeColor "Header"); $currentX += $colWidth
                }
                
                Write-BufferString -X ($self.X + 1) -Y ($headerY + 1) -Text ("─" * ($self.Width - 2)) -ForegroundColor $borderColor
                
                $visibleRows = $self.Height - 5; $startIdx = $self.ScrollOffset; $endIdx = [Math]::Min($self.Rows.Count - 1, $startIdx + $visibleRows - 1)
                
                for ($i = $startIdx; $i -le $endIdx; $i++) {
                    $row = $self.Rows[$i]; $rowY = ($headerY + 2) + ($i - $startIdx); $currentX = $self.X + 2
                    $isSelected = ($i -eq $self.SelectedRow -and $self.IsFocused)
                    $bgColor = $isSelected ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Background")
                    $fgColor = $isSelected ? (Get-ThemeColor "Background") : (Get-ThemeColor "Primary")
                    
                    if ($isSelected) { Write-BufferString -X ($self.X + 1) -Y $rowY -Text (" " * ($self.Width - 2)) -BackgroundColor $bgColor }
                    
                    foreach ($col in $self.Columns) {
                        $value = $row.($col.Name) ?? ""; $text = $value.ToString()
                        if ($text.Length -gt $colWidth - 1) { $text = $text.Substring(0, $colWidth - 4) + "..." }
                        Write-BufferString -X $currentX -Y $rowY -Text $text -ForegroundColor $fgColor -BackgroundColor $bgColor; $currentX += $colWidth
                    }
                }
                
                if ($self.Rows.Count -gt $visibleRows) {
                    $scrollbarHeight = $visibleRows; $scrollPosition = [Math]::Floor(($self.ScrollOffset / ($self.Rows.Count - $visibleRows)) * ($scrollbarHeight - 1))
                    for ($i = 0; $i -lt $scrollbarHeight; $i++) {
                        $char = ($i -eq $scrollPosition) ? "█" : "│"
                        $color = ($i -eq $scrollPosition) ? (Get-ThemeColor "Accent") : (Get-ThemeColor "Subtle")
                        Write-BufferString -X ($self.X + $self.Width - 2) -Y ($headerY + 2 + $i) -Text $char -ForegroundColor $color
                    }
                }
            } catch { Write-Log -Level Error -Message "Table Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if ($self.Rows.Count -eq 0) { return $false }
                $visibleRows = $self.Height - 5; $handled = $true
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow) { if ($self.SelectedRow -gt 0) { $self.SelectedRow--; if ($self.SelectedRow -lt $self.ScrollOffset) { $self.ScrollOffset = $self.SelectedRow }; Request-TuiRefresh } }
                    ([ConsoleKey]::DownArrow) { if ($self.SelectedRow -lt $self.Rows.Count - 1) { $self.SelectedRow++; if ($self.SelectedRow -ge $self.ScrollOffset + $visibleRows) { $self.ScrollOffset = $self.SelectedRow - $visibleRows + 1 }; Request-TuiRefresh } }
                    ([ConsoleKey]::PageUp) { $self.SelectedRow = [Math]::Max(0, $self.SelectedRow - $visibleRows); $self.ScrollOffset = [Math]::Max(0, $self.ScrollOffset - $visibleRows); Request-TuiRefresh }
                    ([ConsoleKey]::PageDown) { $self.SelectedRow = [Math]::Min($self.Rows.Count - 1, $self.SelectedRow + $visibleRows); $maxScroll = [Math]::Max(0, $self.Rows.Count - $visibleRows); $self.ScrollOffset = [Math]::Min($maxScroll, $self.ScrollOffset + $visibleRows); Request-TuiRefresh }
                    ([ConsoleKey]::Home) { $self.SelectedRow = 0; $self.ScrollOffset = 0; Request-TuiRefresh }
                    ([ConsoleKey]::End) { $self.SelectedRow = $self.Rows.Count - 1; $self.ScrollOffset = [Math]::Max(0, $self.Rows.Count - $visibleRows); Request-TuiRefresh }
                    ([ConsoleKey]::Enter) { if ($self.OnRowSelect) { Invoke-WithErrorHandling -Component "$($self.Name).OnRowSelect" -ScriptBlock { & $self.OnRowSelect -Row $self.Rows[$self.SelectedRow] -Index $self.SelectedRow } } }
                    default {
                        if ($Key.KeyChar -match '\d') {
                            $colIndex = [int]$Key.KeyChar.ToString() - 1
                            if ($colIndex -ge 0 -and $colIndex -lt $self.Columns.Count) {
                                $colName = $self.Columns[$colIndex].Name
                                if ($self.SortColumn -eq $colName) { $self.SortAscending = -not $self.SortAscending } 
                                else { $self.SortColumn = $colName; $self.SortAscending = $true }
                                $self.Rows = $self.Rows | Sort-Object -Property $colName -Descending:(-not $self.SortAscending)
                                Request-TuiRefresh
                            }
                        } else { $handled = $false }
                    }
                }
            } catch { Write-Log -Level Error -Message "Table HandleInput error for '$($self.Name)': $_" }
            return $handled
        }
    }
}

function New-TuiChart {
    param([hashtable]$Props = @{})
    
    return @{
        Type = "Chart"
        IsFocusable = $false
        X = $Props.X ?? 0
        Y = $Props.Y ?? 0
        Width = $Props.Width ?? 40
        Height = $Props.Height ?? 10
        Visible = $Props.Visible ?? $true
        ZIndex = $Props.ZIndex ?? 0
        ChartType = $Props.ChartType ?? "Bar"
        Data = $Props.Data ?? @()
        ShowValues = $Props.ShowValues ?? $true
        Name = $Props.Name
        
        Render = {
            param($self)
            try {
                if (-not $self.Visible -or $self.Data.Count -eq 0) { return }
                
                switch ($self.ChartType) {
    		   # "Bar" {
                                            "Bar" {
                        $maxValue = ($self.Data.Value | Measure-Object -Maximum).Maximum ?? 1
                        if ($maxValue -eq 0) { $maxValue = 1 }
                        $chartHeight = $self.Height - 2
                        $barWidth = [Math]::Floor(($self.Width - 4) / $self.Data.Count)
                        
                        for ($i = 0; $i -lt $self.Data.Count; $i++) {
                            $item = $self.Data[$i]
                            $barHeight = [Math]::Floor(($item.Value / $maxValue) * $chartHeight)
                            $barX = $self.X + 2 + ($i * $barWidth)
                            
                            for ($y = 0; $y -lt $barHeight; $y++) { 
                                Write-BufferString -X $barX -Y ($self.Y + $self.Height - 2 - $y) -Text ("█" * ($barWidth - 1)) -ForegroundColor (Get-ThemeColor "Accent") 
                            }
                            if ($item.Label -and $barWidth -gt 3) { 
                                $label = $item.Label
                                if ($label.Length -gt $barWidth - 1) { $label = $label.Substring(0, $barWidth - 2) }
                                Write-BufferString -X $barX -Y ($self.Y + $self.Height - 1) -Text $label -ForegroundColor (Get-ThemeColor "Subtle") 
                            }
                            if ($self.ShowValues -and $barHeight -gt 0) { 
                                $valueText = $item.Value.ToString()
                                Write-BufferString -X $barX -Y ($self.Y + $self.Height - 3 - $barHeight) -Text $valueText -ForegroundColor (Get-ThemeColor "Primary") 
                            }
                        }
                    }
                    "Sparkline" {
                        $width = $self.Width - 2; $height = $self.Height - 1; $maxValue = ($self.Data | Measure-Object -Maximum).Maximum ?? 1
                        if ($maxValue -eq 0) { $maxValue = 1 }
                        $sparkChars = " ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"
                        $sparkline = ""
                        foreach ($value in $self.Data) { $normalized = $value / $maxValue; $charIndex = [Math]::Floor($normalized * ($sparkChars.Count - 1)); $sparkline += $sparkChars[$charIndex] }
                        if ($sparkline.Length -gt $width) { $sparkline = $sparkline.Substring($sparkline.Length - $width) } else { $sparkline = $sparkline.PadLeft($width) }
                        Write-BufferString -X ($self.X + 1) -Y ($self.Y + [Math]::Floor($height / 2)) -Text $sparkline -ForegroundColor (Get-ThemeColor "Accent")
                    }
                }
            } catch { Write-Log -Level Error -Message "Chart Render error for '$($self.Name)': $_" }
        }
        
        HandleInput = { param($self, $Key) return $false }
    }
}

#endregion

Export-ModuleMember -Function 'New-TuiLabel', 'New-TuiButton', 'New-TuiTextBox', 'New-TuiCheckBox', 'New-TuiDropdown', 'New-TuiProgressBar', 'New-TuiTextArea', 'New-TuiDatePicker', 'New-TuiTimePicker', 'New-TuiTable', 'New-TuiChart'