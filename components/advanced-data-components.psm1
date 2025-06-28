# Advanced Data Components Module for PMC Terminal v5
# Enhanced data display components with sorting, filtering, and pagination
# AI: FIX - Removed using module and Import-Module statements. Dependencies managed by _CLASSY-MAIN.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Advanced Data Table Class

class DataTableComponent : UIElement {
    [hashtable[]] $Data = @()
    [hashtable[]] $Columns = @()
    [int] $X = 0
    [int] $Y = 0
    [int] $Width = 80
    [int] $Height = 20
    [string] $Title = "Data Table"
    [bool] $ShowBorder = $true
    [bool] $IsFocusable = $true
    [int] $SelectedRow = 0
    [int] $ScrollOffset = 0
    [string] $SortColumn = $null
    [string] $SortDirection = "Ascending"
    [string] $FilterText = ""
    [string] $FilterColumn = $null
    [int] $PageSize = 0  # 0 = auto-calculate
    [int] $CurrentPage = 0
    [bool] $ShowHeader = $true
    [bool] $ShowFooter = $true
    [bool] $ShowRowNumbers = $false
    [bool] $AllowSort = $true
    [bool] $AllowFilter = $true
    [bool] $AllowSelection = $true
    [bool] $MultiSelect = $false
    [int[]] $SelectedRows = @()
    [hashtable[]] $FilteredData = @()
    [hashtable[]] $ProcessedData = @()
    [bool] $FilterMode = $false
    hidden [int] $_lastRenderedWidth = 0
    hidden [int] $_lastRenderedHeight = 0
    
    # Event handlers
    [scriptblock] $OnRowSelect = $null
    [scriptblock] $OnSelectionChange = $null
    
    DataTableComponent([string]$name) : base($name) {
        $this.IsFocusable = $true
    }
    
    DataTableComponent([string]$name, [hashtable[]]$data, [hashtable[]]$columns) : base($name) {
        $this.IsFocusable = $true
        $this.Data = $data
        $this.Columns = $columns
        $this.ProcessData()
    }
    
    [void] ProcessData() {
        Invoke-WithErrorHandling -Component "$($this.Name).ProcessData" -Context "Processing table data" -ScriptBlock {
            # Filter data
            if ([string]::IsNullOrWhiteSpace($this.FilterText)) {
                $this.FilteredData = $this.Data
            } else {
                if ($this.FilterColumn) {
                    # Filter specific column
                    $this.FilteredData = @($this.Data | Where-Object {
                        $value = $_."$($this.FilterColumn)"
                        $value -and $value.ToString() -like "*$($this.FilterText)*"
                    })
                } else {
                    # Filter all columns
                    $this.FilteredData = @($this.Data | Where-Object {
                        $row = $_
                        $matched = $false
                        foreach ($col in $this.Columns) {
                            if ($col.Filterable -ne $false) {
                                $value = $row."$($col.Name)"
                                if ($value -and $value.ToString() -like "*$($this.FilterText)*") {
                                    $matched = $true
                                    break
                                }
                            }
                        }
                        $matched
                    })
                }
            }
            
            # Sort data
            if ($this.SortColumn -and $this.AllowSort) {
                $this.ProcessedData = $this.FilteredData | Sort-Object -Property $this.SortColumn -Descending:($this.SortDirection -eq "Descending")
            } else {
                $this.ProcessedData = $this.FilteredData
            }
            
            # Reset selection if needed
            if ($this.SelectedRow -ge $this.ProcessedData.Count) {
                $this.SelectedRow = [Math]::Max(0, $this.ProcessedData.Count - 1)
            }
            
            # Calculate page size if auto
            if ($this.PageSize -eq 0) {
                $headerLines = if ($this.ShowHeader) { 3 } else { 0 }
                $footerLines = if ($this.ShowFooter) { 2 } else { 0 }
                $filterLines = if ($this.AllowFilter) { 2 } else { 0 }
                $borderAdjust = if ($this.ShowBorder) { 2 } else { 0 }
                $calculatedPageSize = $this.Height - $headerLines - $footerLines - $filterLines - $borderAdjust
                $this.PageSize = [Math]::Max(1, $calculatedPageSize)
            }
            
            # Adjust current page
            $totalPages = [Math]::Ceiling($this.ProcessedData.Count / [Math]::Max(1, $this.PageSize))
            if ($this.CurrentPage -ge $totalPages) {
                $this.CurrentPage = [Math]::Max(0, $totalPages - 1)
            }
        }
    }
    
    [hashtable] GetContentBounds() {
        $borderOffset = if ($this.ShowBorder) { 1 } else { 0 }
        return @{
            X = $this.X + $borderOffset
            Y = $this.Y + $borderOffset
            Width = $this.Width - (2 * $borderOffset)
            Height = $this.Height - (2 * $borderOffset)
        }
    }
    
    hidden [string] _RenderContent() {
        $renderedContent = [System.Text.StringBuilder]::new()
        
        # Force ProcessData if dimensions changed
        if ($this._lastRenderedWidth -ne $this.Width -or $this._lastRenderedHeight -ne $this.Height) {
            $this.ProcessData()
            $this._lastRenderedWidth = $this.Width
            $this._lastRenderedHeight = $this.Height
        }
        
        # Calculate content area based on border settings
        if ($this.ShowBorder) {
            $borderColor = if ($this.IsFocusable -and $this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
            }
            
            [void]$renderedContent.Append($this.MoveCursor($this.X, $this.Y))
            [void]$renderedContent.Append($this.SetColor($borderColor))
            [void]$renderedContent.Append($this.RenderBorder($this.Title))
            
            # Adjust content area for border
            $contentX = $this.X + 1
            $contentY = $this.Y + 1
            $contentWidth = $this.Width - 2
            $contentHeight = $this.Height - 2
        } else {
            # No border, use full dimensions
            $contentX = $this.X
            $contentY = $this.Y
            $contentWidth = $this.Width
            $contentHeight = $this.Height
        }
        
        $currentY = $contentY
        
        # Filter bar
        if ($this.AllowFilter) {
            [void]$renderedContent.Append($this.MoveCursor($contentX + 1, $currentY))
            [void]$renderedContent.Append($this.SetColor([ConsoleColor]::White))
            [void]$renderedContent.Append("Filter: ")
            
            $filterDisplayText = if ($this.FilterText) { $this.FilterText } else { "Type to filter..." }
            $filterColor = if ($this.FilterText) { [ConsoleColor]::Yellow } else { [ConsoleColor]::DarkGray }
            [void]$renderedContent.Append($this.SetColor($filterColor))
            [void]$renderedContent.Append($filterDisplayText)
            
            $currentY += 2
        }
        
        # Calculate column widths
        $totalDefinedWidth = ($this.Columns | Where-Object { $_.Width } | Measure-Object -Property Width -Sum).Sum
        if ($null -eq $totalDefinedWidth) { $totalDefinedWidth = 0 }
        $flexColumns = @($this.Columns | Where-Object { -not $_.Width })
        $columnSeparators = if ($this.Columns.Count -gt 1) { $this.Columns.Count - 1 } else { 0 }
        $rowNumberWidth = if ($this.ShowRowNumbers) { 5 } else { 0 }
        $remainingWidth = $contentWidth - $totalDefinedWidth - $rowNumberWidth - $columnSeparators
        
        $flexWidth = 0
        if ($flexColumns.Count -gt 0) {
            $flexWidth = [Math]::Floor($remainingWidth / $flexColumns.Count)
        }
        
        # Assign calculated widths
        foreach ($col in $this.Columns) {
            if ($col.Width) {
                $col.CalculatedWidth = $col.Width
            } else {
                $col.CalculatedWidth = [Math]::Max(5, $flexWidth)
            }
        }
        
        # Header
        if ($this.ShowHeader) {
            $headerX = $contentX
            
            # Row number header
            if ($this.ShowRowNumbers) {
                [void]$renderedContent.Append($this.MoveCursor($headerX, $currentY))
                [void]$renderedContent.Append($this.SetColor([ConsoleColor]::Cyan))
                [void]$renderedContent.Append("#".PadRight(4))
                $headerX += 5
            }
            
            # Column headers
            foreach ($col in $this.Columns) {
                $headerText = if ($col.Header) { $col.Header } else { $col.Name }
                $width = $col.CalculatedWidth
                
                # Add sort indicator
                if ($this.AllowSort -and $col.Sortable -ne $false -and $col.Name -eq $this.SortColumn) {
                    $sortIndicator = if ($this.SortDirection -eq "Ascending") { "▲" } else { "▼" }
                    $headerText = "$headerText $sortIndicator"
                }
                
                # Truncate if needed
                if ($headerText.Length -gt $width) {
                    $maxLength = [Math]::Max(0, $width - 3)
                    $headerText = $headerText.Substring(0, $maxLength) + "..."
                }
                
                # Align header
                if ($col.Align -eq "Right") {
                    $alignedText = $headerText.PadLeft($width)
                } elseif ($col.Align -eq "Center") {
                    $padding = $width - $headerText.Length
                    $leftPad = [Math]::Floor($padding / 2)
                    $rightPad = $padding - $leftPad
                    $alignedText = " " * $leftPad + $headerText + " " * $rightPad
                } else {
                    $alignedText = $headerText.PadRight($width)
                }
                
                [void]$renderedContent.Append($this.MoveCursor($headerX, $currentY))
                [void]$renderedContent.Append($this.SetColor([ConsoleColor]::Cyan))
                [void]$renderedContent.Append($alignedText)
                
                $headerX += $width + 1
            }
            
            $currentY++
            
            # Header separator
            [void]$renderedContent.Append($this.MoveCursor($contentX, $currentY))
            [void]$renderedContent.Append($this.SetColor([ConsoleColor]::DarkGray))
            [void]$renderedContent.Append("─" * $contentWidth)
            $currentY++
        }
        
        # Data rows
        $dataToRender = if ($this.ProcessedData.Count -eq 0 -and $this.Data.Count -gt 0) {
            $this.Data
        } else {
            $this.ProcessedData
        }
        
        $startIdx = $this.CurrentPage * $this.PageSize
        $endIdx = [Math]::Min($startIdx + $this.PageSize - 1, $dataToRender.Count - 1)
        
        for ($i = $startIdx; $i -le $endIdx; $i++) {
            $row = $dataToRender[$i]
            $rowX = $contentX
            
            # Selection highlighting
            $isSelected = if ($this.MultiSelect) {
                $this.SelectedRows -contains $i
            } else {
                $i -eq $this.SelectedRow
            }
            
            $rowBg = if ($isSelected) { [ConsoleColor]::Cyan } else { [ConsoleColor]::Black }
            $rowFg = if ($isSelected) { [ConsoleColor]::Black } else { [ConsoleColor]::White }
            
            # Clear row background if selected
            if ($isSelected) {
                [void]$renderedContent.Append($this.MoveCursor($rowX, $currentY))
                [void]$renderedContent.Append($this.SetBackgroundColor($rowBg))
                [void]$renderedContent.Append(" " * $contentWidth)
            }
            
            # Row number
            if ($this.ShowRowNumbers) {
                [void]$renderedContent.Append($this.MoveCursor($rowX, $currentY))
                [void]$renderedContent.Append($this.SetColor([ConsoleColor]::DarkGray))
                [void]$renderedContent.Append($this.SetBackgroundColor($rowBg))
                [void]$renderedContent.Append(($i + 1).ToString().PadRight(4))
                $rowX += 5
            }
            
            # Cell data
            foreach ($col in $this.Columns) {
                $value = $row."$($col.Name)"
                $width = $col.CalculatedWidth
                
                # Format value
                $displayValue = if ($col.Format -and $value -ne $null) {
                    & $col.Format $value
                } elseif ($value -ne $null) {
                    $value.ToString()
                } else {
                    ""
                }
                
                # Truncate if needed
                if ($displayValue.Length -gt $width) {
                    $maxLength = [Math]::Max(0, $width - 3)
                    if ($maxLength -le 0) {
                        $displayValue = "..."
                    } else {
                        $displayValue = $displayValue.Substring(0, $maxLength) + "..."
                    }
                }
                
                # Align value
                if ($col.Align -eq "Right") {
                    $alignedValue = $displayValue.PadLeft($width)
                } elseif ($col.Align -eq "Center") {
                    $padding = $width - $displayValue.Length
                    $leftPad = [Math]::Floor($padding / 2)
                    $rightPad = $padding - $leftPad
                    $alignedValue = " " * $leftPad + $displayValue + " " * $rightPad
                } else {
                    $alignedValue = $displayValue.PadRight($width)
                }
                
                # Determine color
                $cellFg = if ($col.Color -and -not $isSelected) {
                    $colorName = & $col.Color $value $row
                    Get-ThemeColor $colorName -Default ([ConsoleColor]::White)
                } else {
                    $rowFg
                }
                
                [void]$renderedContent.Append($this.MoveCursor($rowX, $currentY))
                [void]$renderedContent.Append($this.SetColor($cellFg))
                [void]$renderedContent.Append($this.SetBackgroundColor($rowBg))
                [void]$renderedContent.Append($alignedValue)
                
                $rowX += $width + 1
            }
            
            $currentY++
        }
        
        # Empty state
        if ($dataToRender.Count -eq 0) {
            $emptyMessage = if ($this.FilterText) {
                "No results match the filter"
            } else {
                "No data to display"
            }
            $msgX = $contentX + [Math]::Floor(($contentWidth - $emptyMessage.Length) / 2)
            $msgY = $contentY + [Math]::Floor($contentHeight / 2)
            [void]$renderedContent.Append($this.MoveCursor($msgX, $msgY))
            [void]$renderedContent.Append($this.SetColor([ConsoleColor]::DarkGray))
            [void]$renderedContent.Append($emptyMessage)
        }
        
        # Footer
        if ($this.ShowFooter) {
            $footerY = $contentY + $contentHeight - 1
            
            # Status
            $statusText = "$($dataToRender.Count) rows"
            if ($this.FilterText) {
                $statusText += " (filtered from $($this.Data.Count))"
            }
            if ($this.MultiSelect) {
                $statusText += " | $($this.SelectedRows.Count) selected"
            }
            [void]$renderedContent.Append($this.MoveCursor($contentX + 1, $footerY))
            [void]$renderedContent.Append($this.SetColor([ConsoleColor]::DarkGray))
            [void]$renderedContent.Append($statusText)
            
            # Pagination
            if ($dataToRender.Count -gt $this.PageSize) {
                $totalPages = [Math]::Ceiling($dataToRender.Count / [Math]::Max(1, $this.PageSize))
                $pageText = "Page $($this.CurrentPage + 1)/$totalPages"
                [void]$renderedContent.Append($this.MoveCursor($contentX + $contentWidth - $pageText.Length - 1, $footerY))
                [void]$renderedContent.Append($this.SetColor([ConsoleColor]::Blue))
                [void]$renderedContent.Append($pageText)
            }
        }
        
        [void]$renderedContent.Append($this.ResetColor())
        return $renderedContent.ToString()
    }
    
    [bool] HandleInput([System.ConsoleKeyInfo]$key) {
        # Filter mode
        if ($key.Modifiers -band [ConsoleModifiers]::Control) {
            switch ($key.Key) {
                ([ConsoleKey]::F) {
                    $this.FilterMode = -not $this.FilterMode
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                    return $true
                }
                ([ConsoleKey]::S) {
                    if ($this.AllowSort) {
                        $sortableCols = @($this.Columns | Where-Object { $_.Sortable -ne $false })
                        if ($sortableCols.Count -gt 0) {
                            $currentIdx = [array]::IndexOf($sortableCols.Name, $this.SortColumn)
                            $nextIdx = ($currentIdx + 1) % $sortableCols.Count
                            $this.SortColumn = $sortableCols[$nextIdx].Name
                            $this.ProcessData()
                            if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                                Request-TuiRefresh
                            }
                        }
                    }
                    return $true
                }
            }
        }
        
        # Filter text input
        if ($this.FilterMode) {
            switch ($key.Key) {
                ([ConsoleKey]::Escape) {
                    $this.FilterMode = $false
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                    return $true
                }
                ([ConsoleKey]::Enter) {
                    $this.FilterMode = $false
                    $this.ProcessData()
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                    return $true
                }
                ([ConsoleKey]::Backspace) {
                    if ($this.FilterText.Length -gt 0) {
                        $this.FilterText = $this.FilterText.Substring(0, $this.FilterText.Length - 1)
                        $this.ProcessData()
                        if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                            Request-TuiRefresh
                        }
                    }
                    return $true
                }
                default {
                    if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                        $this.FilterText += $key.KeyChar
                        $this.ProcessData()
                        if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                            Request-TuiRefresh
                        }
                        return $true
                    }
                }
            }
            return $false
        }
        
        # Normal navigation
        switch ($key.Key) {
            ([ConsoleKey]::UpArrow) {
                if ($this.SelectedRow -gt 0) {
                    $this.SelectedRow--
                    if ($this.SelectedRow -lt ($this.CurrentPage * $this.PageSize)) {
                        $this.CurrentPage--
                    }
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                }
                return $true
            }
            ([ConsoleKey]::DownArrow) {
                if ($this.SelectedRow -lt ($this.ProcessedData.Count - 1)) {
                    $this.SelectedRow++
                    if ($this.SelectedRow -ge (($this.CurrentPage + 1) * $this.PageSize)) {
                        $this.CurrentPage++
                    }
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                }
                return $true
            }
            ([ConsoleKey]::Enter) {
                if ($this.OnRowSelect -and $this.ProcessedData.Count -gt 0) {
                    $selectedData = if ($this.MultiSelect) {
                        @($this.SelectedRows | ForEach-Object { $this.ProcessedData[$_] })
                    } else {
                        $this.ProcessedData[$this.SelectedRow]
                    }
                    & $this.OnRowSelect $selectedData $this.SelectedRow
                }
                return $true
            }
        }
        
        return $false
    }
    
    # Helper methods for ANSI escape sequences
    hidden [string] MoveCursor([int]$x, [int]$y) {
        return "`e[$($y + 1);$($x + 1)H"
    }
    
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{
            'Black' = 30; 'DarkRed' = 31; 'DarkGreen' = 32; 'DarkYellow' = 33
            'DarkBlue' = 34; 'DarkMagenta' = 35; 'DarkCyan' = 36; 'Gray' = 37
            'DarkGray' = 90; 'Red' = 91; 'Green' = 92; 'Yellow' = 93
            'Blue' = 94; 'Magenta' = 95; 'Cyan' = 96; 'White' = 97
        }
        $colorCode = $colorMap[$color.ToString()]
        return "`e[${colorCode}m"
    }
    
    hidden [string] SetBackgroundColor([ConsoleColor]$color) {
        $colorMap = @{
            'Black' = 40; 'DarkRed' = 41; 'DarkGreen' = 42; 'DarkYellow' = 43
            'DarkBlue' = 44; 'DarkMagenta' = 45; 'DarkCyan' = 46; 'Gray' = 47
            'DarkGray' = 100; 'Red' = 101; 'Green' = 102; 'Yellow' = 103
            'Blue' = 104; 'Magenta' = 105; 'Cyan' = 106; 'White' = 107
        }
        $colorCode = $colorMap[$color.ToString()]
        return "`e[${colorCode}m"
    }
    
    hidden [string] ResetColor() {
        return "`e[0m"
    }
    
    hidden [string] RenderBorder([string]$title) {
        $borderBuilder = [System.Text.StringBuilder]::new()
        
        # Top border
        [void]$borderBuilder.Append("┌")
        
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            $titleText = " $title "
            $horizontalSpace = $this.Width - 2
            if ($titleText.Length -gt $horizontalSpace) {
                $titleText = $titleText.Substring(0, $horizontalSpace)
            }
            
            $paddingBefore = [Math]::Floor(($horizontalSpace - $titleText.Length) / 2)
            $paddingAfter = $horizontalSpace - $titleText.Length - $paddingBefore
            
            [void]$borderBuilder.Append("─" * $paddingBefore)
            [void]$borderBuilder.Append($titleText)
            [void]$borderBuilder.Append("─" * $paddingAfter)
        } else {
            [void]$borderBuilder.Append("─" * ($this.Width - 2))
        }
        
        [void]$borderBuilder.Append("┐")
        
        # Side borders
        for ($row = 1; $row -lt $this.Height - 1; $row++) {
            [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $row))
            [void]$borderBuilder.Append("│")
            [void]$borderBuilder.Append($this.MoveCursor($this.X + $this.Width - 1, $this.Y + $row))
            [void]$borderBuilder.Append("│")
        }
        
        # Bottom border
        [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $this.Height - 1))
        [void]$borderBuilder.Append("└")
        [void]$borderBuilder.Append("─" * ($this.Width - 2))
        [void]$borderBuilder.Append("┘")
        
        return $borderBuilder.ToString()
    }
    
    # Public methods
    [void] RefreshData() {
        $this.ProcessData()
        if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
            Request-TuiRefresh
        }
    }
    
    [void] SetData([hashtable[]]$data) {
        $this.Data = $data
        $this.ProcessData()
        if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
            Request-TuiRefresh
        }
    }
    
    [void] SetColumns([hashtable[]]$columns) {
        $this.Columns = $columns
        $this.ProcessData()
        if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
            Request-TuiRefresh
        }
    }
}

#endregion

#region Factory Functions for Backward Compatibility

function global:New-TuiDataTable {
    param([hashtable]$Props = @{})
    
    $name = if ($Props.Name) { $Props.Name } else { "DataTable_$([Guid]::NewGuid().ToString('N').Substring(0,8))" }
    $data = if ($Props.Data) { $Props.Data } else { @() }
    $columns = if ($Props.Columns) { $Props.Columns } else { @() }
    
    $table = [DataTableComponent]::new($name, $data, $columns)
    
    # Set properties from Props
    if ($Props.X) { $table.X = $Props.X }
    if ($Props.Y) { $table.Y = $Props.Y }
    if ($Props.Width) { $table.Width = $Props.Width }
    if ($Props.Height) { $table.Height = $Props.Height }
    if ($Props.Title) { $table.Title = $Props.Title }
    if ($null -ne $Props.ShowBorder) { $table.ShowBorder = $Props.ShowBorder }
    if ($null -ne $Props.ShowHeader) { $table.ShowHeader = $Props.ShowHeader }
    if ($null -ne $Props.ShowFooter) { $table.ShowFooter = $Props.ShowFooter }
    if ($null -ne $Props.ShowRowNumbers) { $table.ShowRowNumbers = $Props.ShowRowNumbers }
    if ($null -ne $Props.AllowSort) { $table.AllowSort = $Props.AllowSort }
    if ($null -ne $Props.AllowFilter) { $table.AllowFilter = $Props.AllowFilter }
    if ($null -ne $Props.AllowSelection) { $table.AllowSelection = $Props.AllowSelection }
    if ($null -ne $Props.MultiSelect) { $table.MultiSelect = $Props.MultiSelect }
    if ($null -ne $Props.Visible) { $table.Visible = $Props.Visible }
    if ($Props.OnRowSelect) { $table.OnRowSelect = $Props.OnRowSelect }
    if ($Props.OnSelectionChange) { $table.OnSelectionChange = $Props.OnSelectionChange }
    
    return $table
}

#endregion

# AI: FIX - Export functions only. Classes are automatically exported in PowerShell 5.1
Export-ModuleMember -Function @('New-TuiDataTable')