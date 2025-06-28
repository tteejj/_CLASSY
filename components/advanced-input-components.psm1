# Advanced Input Components Module
# Enhanced input components from the TUI Upgrade Roadmap

#region DateTime Components with Calendar Grid

function global:New-TuiCalendarPicker {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "CalendarPicker"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 30 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 10 }
        Value = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        Mode = if ($null -ne $Props.Mode) { $Props.Mode } else { "Date" } # Date, DateTime, Time
        IsFocusable = $true
        CurrentView = "Day"  # Day, Month, Year
        SelectedDate = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        ViewDate = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        Name = $Props.Name
        OnChange = $Props.OnChange
        OnSelect = $Props.OnSelect
        
        Render = {
            param($self)
            try {
                $borderColor = if ($self.IsFocused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
                }
                
                # Main container
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -BorderColor $borderColor -Title " Calendar "
                
                # Header with navigation
                $headerY = $self.Y + 1
                $monthYear = $self.ViewDate.ToString("MMMM yyyy")
                $headerX = $self.X + [Math]::Floor(($self.Width - $monthYear.Length) / 2)
                
                Write-BufferString -X ($self.X + 2) -Y $headerY -Text "◄" -ForegroundColor $borderColor
                Write-BufferString -X $headerX -Y $headerY -Text $monthYear -ForegroundColor (Get-ThemeColor "Header")
                Write-BufferString -X ($self.X + $self.Width - 3) -Y $headerY -Text "►" -ForegroundColor $borderColor
                
                # Day headers
                $dayHeaderY = $headerY + 2
                $days = @("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa")
                $dayWidth = 4
                $startX = $self.X + 2
                
                for ($i = 0; $i -lt $days.Count; $i++) {
                    Write-BufferString -X ($startX + ($i * $dayWidth)) -Y $dayHeaderY `
                        -Text $days[$i] -ForegroundColor (Get-ThemeColor "Subtle")
                }
                
                # Calendar grid
                $firstDay = Get-Date -Year $self.ViewDate.Year -Month $self.ViewDate.Month -Day 1
                $startDayOfWeek = [int]$firstDay.DayOfWeek
                $daysInMonth = [DateTime]::DaysInMonth($self.ViewDate.Year, $self.ViewDate.Month)
                
                $currentDay = 1
                $calendarY = $dayHeaderY + 1
                
                for ($week = 0; $week -lt 6; $week++) {
                    if ($currentDay -gt $daysInMonth) { break }
                    
                    for ($dayOfWeek = 0; $dayOfWeek -lt 7; $dayOfWeek++) {
                        $x = $startX + ($dayOfWeek * $dayWidth)
                        
                        if ($week -eq 0 -and $dayOfWeek -lt $startDayOfWeek) {
                            continue
                        }
                        
                        if ($currentDay -le $daysInMonth) {
                            $isSelected = ($currentDay -eq $self.SelectedDate.Day -and 
                                         $self.ViewDate.Month -eq $self.SelectedDate.Month -and 
                                         $self.ViewDate.Year -eq $self.SelectedDate.Year)
                            
                            $isToday = ($currentDay -eq (Get-Date).Day -and 
                                      $self.ViewDate.Month -eq (Get-Date).Month -and 
                                      $self.ViewDate.Year -eq (Get-Date).Year)
                            
                            $fg = if ($isSelected) { 
                                Get-ThemeColor "Background" 
                            } elseif ($isToday) { 
                                Get-ThemeColor "Accent" 
                            } else { 
                                Get-ThemeColor "Primary" 
                            }
                            
                            $bg = if ($isSelected) { 
                                Get-ThemeColor "Accent" 
                            } else { 
                                Get-ThemeColor "Background" 
                            }
                            
                            $dayText = $currentDay.ToString().PadLeft(2)
                            Write-BufferString -X $x -Y ($calendarY + $week) -Text $dayText `
                                -ForegroundColor $fg -BackgroundColor $bg
                            
                            $currentDay++
                        }
                    }
                }
                
                # Time picker if in DateTime mode
                if ($self.Mode -eq "DateTime") {
                    $timeY = $self.Y + $self.Height - 2
                    $timeStr = $self.SelectedDate.ToString("HH:mm")
                    Write-BufferString -X ($self.X + 2) -Y $timeY -Text "Time: $timeStr" `
                        -ForegroundColor (Get-ThemeColor "Primary")
                }
            } catch {
                Write-Log -Level Error -Message "CalendarPicker Render error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Exception = $_ }
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $handled = $true
                $date = $self.SelectedDate
                $viewDate = $self.ViewDate
                
                switch ($Key.Key) {
                    ([ConsoleKey]::LeftArrow) {
                        if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                            # Previous month
                            $self.ViewDate = $viewDate.AddMonths(-1)
                        } else {
                            # Previous day
                            $date = $date.AddDays(-1)
                            if ($date.Month -ne $viewDate.Month) {
                                $self.ViewDate = $date
                            }
                        }
                    }
                    ([ConsoleKey]::RightArrow) {
                        if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                            # Next month
                            $self.ViewDate = $viewDate.AddMonths(1)
                        } else {
                            # Next day
                            $date = $date.AddDays(1)
                            if ($date.Month -ne $viewDate.Month) {
                                $self.ViewDate = $date
                            }
                        }
                    }
                    ([ConsoleKey]::UpArrow) {
                        $date = $date.AddDays(-7)
                        if ($date.Month -ne $viewDate.Month) {
                            $self.ViewDate = $date
                        }
                    }
                    ([ConsoleKey]::DownArrow) {
                        $date = $date.AddDays(7)
                        if ($date.Month -ne $viewDate.Month) {
                            $self.ViewDate = $date
                        }
                    }
                    ([ConsoleKey]::PageUp) {
                        $self.ViewDate = $viewDate.AddMonths(-1)
                        $date = Get-Date -Year $self.ViewDate.Year -Month $self.ViewDate.Month `
                            -Day ([Math]::Min($date.Day, [DateTime]::DaysInMonth($self.ViewDate.Year, $self.ViewDate.Month)))
                    }
                    ([ConsoleKey]::PageDown) {
                        $self.ViewDate = $viewDate.AddMonths(1)
                        $date = Get-Date -Year $self.ViewDate.Year -Month $self.ViewDate.Month `
                            -Day ([Math]::Min($date.Day, [DateTime]::DaysInMonth($self.ViewDate.Year, $self.ViewDate.Month)))
                    }
                    ([ConsoleKey]::Home) {
                        $date = Get-Date
                        $self.ViewDate = $date
                    }
                    ([ConsoleKey]::Enter) {
                        if ($self.OnSelect) {
                            Invoke-WithErrorHandling -Component "$($self.Name).OnSelect" -ScriptBlock {
                                & $self.OnSelect -Date $date
                            } -AdditionalData @{ Component = $self.Name; SelectedDate = $date }
                        }
                    }
                    default {
                        $handled = $false
                    }
                }
                
                if ($handled) {
                    $self.SelectedDate = $date
                    if ($self.OnChange) {
                        Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                            & $self.OnChange -NewValue $date
                        } -AdditionalData @{ Component = $self.Name; NewValue = $date }
                    }
                    Request-TuiRefresh
                }
                
                return $handled
            } catch {
                Write-Log -Level Error -Message "CalendarPicker HandleInput error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Key = $Key; Exception = $_ }
            }
            return $false
        }
    }
    
    return $component
}

#endregion

#region Enhanced Dropdown with Search

function global:New-TuiSearchableDropdown {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "SearchableDropdown"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 30 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 3 }
        Options = if ($null -ne $Props.Options) { $Props.Options } else { @() }
        Value = $Props.Value
        Placeholder = if ($null -ne $Props.Placeholder) { $Props.Placeholder } else { "Type to search..." }
        MaxDisplayItems = if ($null -ne $Props.MaxDisplayItems) { $Props.MaxDisplayItems } else { 5 }
        AllowCustomValue = if ($null -ne $Props.AllowCustomValue) { $Props.AllowCustomValue } else { $false }
        IsFocusable = $true
        IsOpen = $false
        SearchText = ""
        FilteredOptions = @()
        SelectedIndex = 0
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                $borderColor = if ($self.IsFocused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
                }
                
                # Main dropdown box
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -BorderColor $borderColor
                
                # Display text
                $displayText = ""
                if ($self.IsOpen) {
                    $displayText = $self.SearchText
                    if ([string]::IsNullOrEmpty($displayText) -and -not $self.IsFocused) {
                        $displayText = $self.Placeholder
                    }
                } else {
                    if ($self.Value) {
                        $selected = $self.Options | Where-Object { $_.Value -eq $self.Value } | Select-Object -First 1
                        if ($selected) {
                            $displayText = $selected.Display
                        } else {
                            $displayText = $self.Value.ToString()
                        }
                    } else {
                        $displayText = "Select..."
                    }
                }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $displayText
                
                # Dropdown indicator
                $indicator = if ($self.IsOpen) { "▲" } else { "▼" }
                Write-BufferString -X ($self.X + $self.Width - 3) -Y ($self.Y + 1) -Text $indicator `
                    -ForegroundColor $borderColor
                
                # Cursor for search mode
                if ($self.IsOpen -and $self.IsFocused) {
                    $cursorX = $self.X + 2 + $self.SearchText.Length
                    if ($cursorX -lt ($self.X + $self.Width - 3)) {
                        Write-BufferString -X $cursorX -Y ($self.Y + 1) -Text "_" `
                            -BackgroundColor (Get-ThemeColor "Accent")
                    }
                }
                
                # Options dropdown
                if ($self.IsOpen -and $self.FilteredOptions.Count -gt 0) {
                    $dropHeight = [Math]::Min($self.FilteredOptions.Count, $self.MaxDisplayItems) + 2
                    Write-BufferBox -X $self.X -Y ($self.Y + $self.Height) -Width $self.Width -Height $dropHeight `
                        -BorderColor $borderColor -BackgroundColor (Get-ThemeColor "Background")
                    
                    $startIdx = 0
                    if ($self.SelectedIndex -ge $self.MaxDisplayItems) {
                        $startIdx = $self.SelectedIndex - $self.MaxDisplayItems + 1
                    }
                    
                    $endIdx = [Math]::Min($startIdx + $self.MaxDisplayItems - 1, $self.FilteredOptions.Count - 1)
                    
                    for ($i = $startIdx; $i -le $endIdx; $i++) {
                        $option = $self.FilteredOptions[$i]
                        $y = $self.Y + $self.Height + 1 + ($i - $startIdx)
                        
                        $isSelected = ($i -eq $self.SelectedIndex)
                        $fg = if ($isSelected) { Get-ThemeColor "Background" } else { Get-ThemeColor "Primary" }
                        $bg = if ($isSelected) { Get-ThemeColor "Accent" } else { Get-ThemeColor "Background" }
                        
                        $text = $option.Display
                        if ($text.Length -gt ($self.Width - 4)) {
                            $text = $text.Substring(0, $self.Width - 7) + "..."
                        }
                        
                        # Highlight matching text
                        if ($self.SearchText.Length -gt 0 -and -not $isSelected) {
                            $matchIndex = $text.IndexOf($self.SearchText, [StringComparison]::OrdinalIgnoreCase)
                            if ($matchIndex -ge 0) {
                                # Draw text before match
                                if ($matchIndex -gt 0) {
                                    Write-BufferString -X ($self.X + 2) -Y $y `
                                        -Text $text.Substring(0, $matchIndex) -ForegroundColor $fg
                                }
                                
                                # Draw matching text highlighted
                                Write-BufferString -X ($self.X + 2 + $matchIndex) -Y $y `
                                    -Text $text.Substring($matchIndex, $self.SearchText.Length) `
                                    -ForegroundColor (Get-ThemeColor "Warning")
                                
                                # Draw text after match
                                $afterMatch = $matchIndex + $self.SearchText.Length
                                if ($afterMatch -lt $text.Length) {
                                    Write-BufferString -X ($self.X + 2 + $afterMatch) -Y $y `
                                        -Text $text.Substring($afterMatch) -ForegroundColor $fg
                                }
                                
                                continue
                            }
                        }
                        
                        Write-BufferString -X ($self.X + 2) -Y $y -Text $text `
                            -ForegroundColor $fg -BackgroundColor $bg
                    }
                    
                    # Scrollbar if needed
                    if ($self.FilteredOptions.Count -gt $self.MaxDisplayItems) {
                        $scrollHeight = $self.MaxDisplayItems
                        $scrollPos = [Math]::Floor(($self.SelectedIndex / ($self.FilteredOptions.Count - 1)) * ($scrollHeight - 1))
                        
                        for ($i = 0; $i -lt $scrollHeight; $i++) {
                            $char = if ($i -eq $scrollPos) { "█" } else { "│" }
                            $color = if ($i -eq $scrollPos) { Get-ThemeColor "Accent" } else { Get-ThemeColor "Subtle" }
                            Write-BufferString -X ($self.X + $self.Width - 2) -Y ($self.Y + $self.Height + 1 + $i) `
                                -Text $char -ForegroundColor $color
                        }
                    }
                }
            } catch {
                Write-Log -Level Error -Message "SearchableDropdown Render error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Exception = $_ }
            }
        }
        
        FilterOptions = {
            try {
                if ([string]::IsNullOrEmpty($this.SearchText)) {
                    $this.FilteredOptions = $this.Options
                } else {
                    $this.FilteredOptions = @($this.Options | Where-Object {
                        $_.Display -like "*$($this.SearchText)*"
                    })
                    
                    # Add custom value option if allowed and no exact match
                    if ($this.AllowCustomValue) {
                        $exactMatch = $this.FilteredOptions | Where-Object { $_.Display -eq $this.SearchText }
                        if (-not $exactMatch) {
                            $this.FilteredOptions = @(@{
                                Display = $this.SearchText
                                Value = $this.SearchText
                                IsCustom = $true
                            }) + $this.FilteredOptions
                        }
                    }
                }
                
                # Reset selection to first item
                $this.SelectedIndex = 0
            } catch {
                Write-Log -Level Error -Message "SearchableDropdown FilterOptions error for '$($this.Name)': $_" -Data @{ Component = $this.Name; Exception = $_ }
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if (-not $self.IsOpen) {
                    switch ($Key.Key) {
                        { $_ -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar, [ConsoleKey]::DownArrow) } {
                            $self.IsOpen = $true
                            $self.SearchText = ""
                            & $self.FilterOptions
                            Request-TuiRefresh
                            return $true
                        }
                    }
                    return $false
                }
                
                # Handle open dropdown
                switch ($Key.Key) {
                    ([ConsoleKey]::Escape) {
                        $self.IsOpen = $false
                        $self.SearchText = ""
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::Enter) {
                        if ($self.FilteredOptions.Count -gt 0) {
                            $selected = $self.FilteredOptions[$self.SelectedIndex]
                            if ($self.OnChange) {
                                Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                                    & $self.OnChange -NewValue $selected.Value -Option $selected
                                } -AdditionalData @{ Component = $self.Name; NewValue = $selected.Value; Option = $selected }
                            }
                            $self.Value = $selected.Value
                            $self.IsOpen = $false
                            $self.SearchText = ""
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::UpArrow) {
                        if ($self.SelectedIndex -gt 0) {
                            $self.SelectedIndex--
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::DownArrow) {
                        if ($self.SelectedIndex -lt ($self.FilteredOptions.Count - 1)) {
                            $self.SelectedIndex++
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::Backspace) {
                        if ($self.SearchText.Length -gt 0) {
                            $self.SearchText = $self.SearchText.Substring(0, $self.SearchText.Length - 1)
                            & $self.FilterOptions
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    default {
                        if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) {
                            $self.SearchText += $Key.KeyChar
                            & $self.FilterOptions
                            Request-TuiRefresh
                            return $true
                        }
                    }
                }
            } catch {
                Write-Log -Level Error -Message "SearchableDropdown HandleInput error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Key = $Key; Exception = $_ }
            }
            return $false
        }
    }
    
    return $component
}

#endregion

#region Multi-Select Components

function global:New-TuiMultiSelect {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "MultiSelect"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 30 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 10 }
        Options = if ($null -ne $Props.Options) { $Props.Options } else { @() }
        SelectedValues = if ($null -ne $Props.SelectedValues) { $Props.SelectedValues } else { @() }
        Title = if ($null -ne $Props.Title) { $Props.Title } else { "Select items" }
        AllowSelectAll = if ($null -ne $Props.AllowSelectAll) { $Props.AllowSelectAll } else { $true }
        IsFocusable = $true
        SelectedIndex = 0
        ScrollOffset = 0
        Name = $Props.Name
        OnChange = $Props.OnChange
        OnSubmit = $Props.OnSubmit
        
        Render = {
            param($self)
            try {
                $borderColor = if ($self.IsFocused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
                }
                
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -BorderColor $borderColor -Title " $($self.Title) "
                
                # Select all option
                $currentY = $self.Y + 1
                if ($self.AllowSelectAll) {
                    $allSelected = $self.Options.Count -eq $self.SelectedValues.Count
                    $checkbox = if ($allSelected) { "[X]" } else { "[ ]" }
                    $fg = if ($self.SelectedIndex -eq -1) { Get-ThemeColor "Accent" } else { Get-ThemeColor "Secondary" }
                    Write-BufferString -X ($self.X + 2) -Y $currentY -Text "$checkbox Select All" `
                        -ForegroundColor $fg
                    $currentY += 2
                }
                
                # Options
                $visibleHeight = $self.Height - 4
                if ($self.AllowSelectAll) { $visibleHeight -= 2 }
                
                $startIdx = $self.ScrollOffset
                $endIdx = [Math]::Min($self.Options.Count - 1, $startIdx + $visibleHeight - 1)
                
                for ($i = $startIdx; $i -le $endIdx; $i++) {
                    $option = $self.Options[$i]
                    $isChecked = $self.SelectedValues -contains $option.Value
                    $isHighlighted = ($i -eq $self.SelectedIndex)
                    
                    $checkbox = if ($isChecked) { "[X]" } else { "[ ]" }
                    $fg = if ($isHighlighted) { Get-ThemeColor "Accent" } else { Get-ThemeColor "Primary" }
                    
                    $text = "$checkbox $($option.Display)"
                    if ($text.Length -gt ($self.Width - 4)) {
                        $text = $text.Substring(0, $self.Width - 7) + "..."
                    }
                    
                    Write-BufferString -X ($self.X + 2) -Y $currentY -Text $text -ForegroundColor $fg
                    $currentY++
                }
                
                # Status line
                $statusY = $self.Y + $self.Height - 2
                $statusText = "$($self.SelectedValues.Count) of $($self.Options.Count) selected"
                Write-BufferString -X ($self.X + 2) -Y $statusY -Text $statusText `
                    -ForegroundColor (Get-ThemeColor "Subtle")
            } catch {
                Write-Log -Level Error -Message "MultiSelect Render error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Exception = $_ }
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $maxIndex = $self.Options.Count - 1
                if ($self.AllowSelectAll) { $maxIndex++ }
                
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow) {
                        if ($self.AllowSelectAll -and $self.SelectedIndex -eq 0) {
                            $self.SelectedIndex = -1
                        } elseif ($self.SelectedIndex -gt 0 -or ($self.AllowSelectAll -and $self.SelectedIndex -gt -1)) {
                            $self.SelectedIndex--
                            if ($self.SelectedIndex -ge 0 -and $self.SelectedIndex -lt $self.ScrollOffset) {
                                $self.ScrollOffset = $self.SelectedIndex
                            }
                        }
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::DownArrow) {
                        if ($self.SelectedIndex -lt ($self.Options.Count - 1)) {
                            $self.SelectedIndex++
                            $visibleHeight = $self.Height - 4
                            if ($self.AllowSelectAll) { $visibleHeight -= 2 }
                            if ($self.SelectedIndex -ge ($self.ScrollOffset + $visibleHeight)) {
                                $self.ScrollOffset = $self.SelectedIndex - $visibleHeight + 1
                            }
                        }
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::Spacebar) {
                        if ($self.SelectedIndex -eq -1 -and $self.AllowSelectAll) {
                            # Toggle all
                            if ($self.SelectedValues.Count -eq $self.Options.Count) {
                                $self.SelectedValues = @()
                            } else {
                                $self.SelectedValues = @($self.Options | ForEach-Object { $_.Value })
                            }
                        } elseif ($self.SelectedIndex -ge 0) {
                            # Toggle individual
                            $option = $self.Options[$self.SelectedIndex]
                            if ($self.SelectedValues -contains $option.Value) {
                                $self.SelectedValues = @($self.SelectedValues | Where-Object { $_ -ne $option.Value })
                            } else {
                                $self.SelectedValues += $option.Value
                            }
                        }
                        
                        if ($self.OnChange) {
                            Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                                & $self.OnChange -SelectedValues $self.SelectedValues
                            } -AdditionalData @{ Component = $self.Name; SelectedValues = $self.SelectedValues }
                        }
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::Enter) {
                        if ($self.OnSubmit) {
                            Invoke-WithErrorHandling -Component "$($self.Name).OnSubmit" -ScriptBlock {
                                & $self.OnSubmit -SelectedValues $self.SelectedValues
                            } -AdditionalData @{ Component = $self.Name; SelectedValues = $self.SelectedValues }
                        }
                        return $true
                    }
                }
            } catch {
                Write-Log -Level Error -Message "MultiSelect HandleInput error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Key = $Key; Exception = $_ }
            }
            return $false
        }
    }
    
    return $component
}

#endregion

#region Numeric Input Components

function global:New-TuiNumberInput {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "NumberInput"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 20 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 3 }
        Value = if ($null -ne $Props.Value) { $Props.Value } else { 0 }
        Min = if ($null -ne $Props.Min) { $Props.Min } else { 0 }
        Max = if ($null -ne $Props.Max) { $Props.Max } else { 100 }
        Step = if ($null -ne $Props.Step) { $Props.Step } else { 1 }
        DecimalPlaces = if ($null -ne $Props.DecimalPlaces) { $Props.DecimalPlaces } else { 0 }
        IsFocusable = $true
        TextValue = (if ($null -ne $Props.Value) { $Props.Value } else { 0 }).ToString()
        CursorPosition = 0
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                $borderColor = if ($self.IsFocused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
                }
                
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -BorderColor $borderColor
                
                # Value display
                $displayValue = $self.TextValue
                if ($displayValue.Length -gt ($self.Width - 6)) {
                    $displayValue = $displayValue.Substring(0, $self.Width - 9) + "..."
                }
                
                Write-BufferString -X ($self.X + 2) -Y ($self.Y + 1) -Text $displayValue
                
                # Cursor
                if ($self.IsFocused -and $self.CursorPosition -le $displayValue.Length) {
                    $cursorX = $self.X + 2 + $self.CursorPosition
                    if ($cursorX -lt ($self.X + $self.Width - 4)) {
                        Write-BufferString -X $cursorX -Y ($self.Y + 1) -Text "_" `
                            -BackgroundColor (Get-ThemeColor "Accent")
                    }
                }
                
                # Spinner buttons
                Write-BufferString -X ($self.X + $self.Width - 3) -Y ($self.Y + 1) -Text "▲" `
                    -ForegroundColor $borderColor
                Write-BufferString -X ($self.X + $self.Width - 3) -Y ($self.Y + 1) -Text "▼" `
                    -ForegroundColor $borderColor
                
                # Min/Max indicators
                if ($self.Value -le $self.Min) {
                    Write-BufferString -X ($self.X + 1) -Y ($self.Y + 1) -Text "⊥" `
                        -ForegroundColor (Get-ThemeColor "Warning")
                }
                if ($self.Value -ge $self.Max) {
                    Write-BufferString -X ($self.X + $self.Width - 2) -Y ($self.Y + 1) -Text "⊤" `
                        -ForegroundColor (Get-ThemeColor "Warning")
                }
            } catch {
                Write-Log -Level Error -Message "NumberInput Render error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Exception = $_ }
            }
        }
        
        ValidateAndUpdate = {
            try {
                $newValue = [double]$this.TextValue
                $newValue = [Math]::Max($this.Min, [Math]::Min($this.Max, $newValue))
                
                if ($this.DecimalPlaces -eq 0) {
                    $newValue = [Math]::Floor($newValue)
                } else {
                    $newValue = [Math]::Round($newValue, $this.DecimalPlaces)
                }
                
                $this.Value = $newValue
                $this.TextValue = $newValue.ToString("F$($this.DecimalPlaces)")
                
                if ($this.OnChange) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                        & $this.OnChange -NewValue $newValue
                    } -AdditionalData @{ Component = $this.Name; NewValue = $newValue }
                }
                
                return $true
            } catch {
                # Invalid input, restore previous value
                $this.TextValue = $this.Value.ToString("F$($this.DecimalPlaces)")
                Write-Log -Level Warning -Message "NumberInput ValidateAndUpdate error for '$($this.Name)': $_" -Data @{ Component = $this.Name; InputText = $this.TextValue; Exception = $_ }
                return $false
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                switch ($Key.Key) {
                    ([ConsoleKey]::UpArrow) {
                        $self.Value = [Math]::Min($self.Max, $self.Value + $self.Step)
                        $self.TextValue = $self.Value.ToString("F$($self.DecimalPlaces)")
                        $self.CursorPosition = $self.TextValue.Length
                        if ($self.OnChange) {
                            Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                                & $self.OnChange -NewValue $self.Value
                            } -AdditionalData @{ Component = $self.Name; NewValue = $self.Value }
                        }
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::DownArrow) {
                        $self.Value = [Math]::Max($self.Min, $self.Value - $self.Step)
                        $self.TextValue = $self.Value.ToString("F$($self.DecimalPlaces)")
                        $self.CursorPosition = $self.TextValue.Length
                        if ($self.OnChange) {
                            Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                                & $self.OnChange -NewValue $self.Value
                            } -AdditionalData @{ Component = $self.Name; NewValue = $self.Value }
                        }
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::LeftArrow) {
                        if ($self.CursorPosition -gt 0) {
                            $self.CursorPosition--
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::RightArrow) {
                        if ($self.CursorPosition -lt $self.TextValue.Length) {
                            $self.CursorPosition++
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::Home) {
                        $self.CursorPosition = 0
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::End) {
                        $self.CursorPosition = $self.TextValue.Length
                        Request-TuiRefresh
                        return $true
                    }
                    ([ConsoleKey]::Backspace) {
                        if ($self.CursorPosition -gt 0) {
                            $self.TextValue = $self.TextValue.Remove($self.CursorPosition - 1, 1)
                            $self.CursorPosition--
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::Delete) {
                        if ($self.CursorPosition -lt $self.TextValue.Length) {
                            $self.TextValue = $self.TextValue.Remove($self.CursorPosition, 1)
                            Request-TuiRefresh
                        }
                        return $true
                    }
                    ([ConsoleKey]::Enter) {
                        & $self.ValidateAndUpdate -self $self
                        Request-TuiRefresh
                        return $true
                    }
                    default {
                        if ($Key.KeyChar -and ($Key.KeyChar -match '[\d\.\-]')) {
                            $self.TextValue = $self.TextValue.Insert($self.CursorPosition, $Key.KeyChar)
                            $self.CursorPosition++
                            Request-TuiRefresh
                            return $true
                        }
                    }
                }
            } catch {
                Write-Log -Level Error -Message "NumberInput HandleInput error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Key = $Key; Exception = $_ }
            }
            return $false
        }
    }
    
    return $component
}

function global:New-TuiSlider {
    param([hashtable]$Props = @{})
    
    $component = @{
        Type = "Slider"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 30 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 1 }
        Value = if ($null -ne $Props.Value) { $Props.Value } else { 50 }
        Min = if ($null -ne $Props.Min) { $Props.Min } else { 0 }
        Max = if ($null -ne $Props.Max) { $Props.Max } else { 100 }
        Step = if ($null -ne $Props.Step) { $Props.Step } else { 1 }
        ShowValue = if ($null -ne $Props.ShowValue) { $Props.ShowValue } else { $true }
        IsFocusable = $true
        Name = $Props.Name
        OnChange = $Props.OnChange
        
        Render = {
            param($self)
            try {
                $fg = if ($self.IsFocused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
                }
                
                # Calculate position
                $range = $self.Max - $self.Min
                $percent = ($self.Value - $self.Min) / $range
                $trackWidth = $self.Width - 2
                $thumbPos = [Math]::Floor($trackWidth * $percent)
                
                # Draw track
                $track = "─" * $trackWidth
                Write-BufferString -X ($self.X + 1) -Y $self.Y -Text $track -ForegroundColor (Get-ThemeColor "Subtle")
                
                # Draw filled portion
                if ($thumbPos -gt 0) {
                    $filled = "═" * $thumbPos
                    Write-BufferString -X ($self.X + 1) -Y $self.Y -Text $filled -ForegroundColor $fg
                }
                
                # Draw thumb
                Write-BufferString -X ($self.X + 1 + $thumbPos) -Y $self.Y -Text "●" -ForegroundColor $fg
                
                # Draw bounds
                Write-BufferString -X $self.X -Y $self.Y -Text "[" -ForegroundColor $fg
                Write-BufferString -X ($self.X + $self.Width - 1) -Y $self.Y -Text "]" -ForegroundColor $fg
                
                # Show value
                if ($self.ShowValue) {
                    $valueText = $self.Value.ToString()
                    $valueX = $self.X + [Math]::Floor(($self.Width - $valueText.Length) / 2)
                    Write-BufferString -X $valueX -Y ($self.Y + 1) -Text $valueText -ForegroundColor $fg
                }
            } catch {
                Write-Log -Level Error -Message "Slider Render error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Exception = $_ }
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                $handled = $true
                $oldValue = $self.Value
                
                switch ($Key.Key) {
                    ([ConsoleKey]::LeftArrow) {
                        $self.Value = [Math]::Max($self.Min, $self.Value - $self.Step)
                    }
                    ([ConsoleKey]::RightArrow) {
                        $self.Value = [Math]::Min($self.Max, $self.Value + $self.Step)
                    }
                    ([ConsoleKey]::Home) {
                        $self.Value = $self.Min
                    }
                    ([ConsoleKey]::End) {
                        $self.Value = $self.Max
                    }
                    ([ConsoleKey]::PageDown) {
                        $largeStep = [Math]::Max($self.Step, ($self.Max - $self.Min) / 10)
                        $self.Value = [Math]::Max($self.Min, $self.Value - $largeStep)
                    }
                    ([ConsoleKey]::PageUp) {
                        $largeStep = [Math]::Max($self.Step, ($self.Max - $self.Min) / 10)
                        $self.Value = [Math]::Min($self.Max, $self.Value + $largeStep)
                    }
                    default {
                        $handled = $false
                    }
                }
                
                if ($handled -and $self.Value -ne $oldValue) {
                    if ($self.OnChange) {
                        Invoke-WithErrorHandling -Component "$($self.Name).OnChange" -ScriptBlock {
                            & $self.OnChange -NewValue $self.Value
                        } -AdditionalData @{ Component = $self.Name; NewValue = $self.Value }
                    }
                    Request-TuiRefresh
                }
                
                return $handled
            } catch {
                Write-Log -Level Error -Message "Slider HandleInput error for '$($self.Name)': $_" -Data @{ Component = $self.Name; Key = $Key; Exception = $_ }
            }
            return $false
        }
    }
    
    return $component
}

#endregion

Export-ModuleMember -Function @(
    'New-TuiCalendarPicker',
    'New-TuiSearchableDropdown',
    'New-TuiMultiSelect',
    'New-TuiNumberInput',
    'New-TuiSlider'
)