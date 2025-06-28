# FILE: layout/panels.psm1 - FIXED VERSION
# PURPOSE: Provides specialized layout panels with resolved parameter binding issues

# AI: Helper function to resolve percentage dimensions to actual pixel values
function Resolve-Dimension {
    param(
        $Dimension,
        [int]$ParentSize
    )
    
    if ($null -eq $Dimension) { return 0 }
    
    # If it's already a number, return it
    if ($Dimension -is [int] -or $Dimension -is [double]) {
        return [int]$Dimension
    }
    
    # If it's a string with percentage
    if ($Dimension -is [string]) {
        # Handle corrupted values like "100%1"
        $cleanDimension = $Dimension -replace '[^0-9%]', ''
        
        if ($cleanDimension -match '^(\d+)%$') {
            $percentage = [int]$matches[1]
            return [int]([Math]::Floor($ParentSize * $percentage / 100))
        }
        
        # Try to parse as integer
        $intValue = 0
        if ([int]::TryParse($Dimension, [ref]$intValue)) {
            return $intValue
        }
    }
    
    # Default fallback
    return 0
}

function New-BasePanel {
    param([hashtable]$Props)
    
    $panel = @{
        Type = "Panel"
        Name = if ($null -ne $Props.Name) { $Props.Name } else { "Panel_$([Guid]::NewGuid().ToString('N').Substring(0,8))" }
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 40 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 20 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        IsFocusable = if ($null -ne $Props.IsFocusable) { $Props.IsFocusable } else { $false }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Children = @()
        Parent = $null
        LayoutProps = if ($null -ne $Props.LayoutProps) { $Props.LayoutProps } else { @{} }
        ShowBorder = if ($null -ne $Props.ShowBorder) { $Props.ShowBorder } else { $false }
        BorderStyle = if ($null -ne $Props.BorderStyle) { $Props.BorderStyle } else { "Single" }
        BorderColor = if ($null -ne $Props.BorderColor) { $Props.BorderColor } else { "Border" }
        Title = $Props.Title
        Padding = if ($null -ne $Props.Padding) { $Props.Padding } else { 0 }
        Margin = if ($null -ne $Props.Margin) { $Props.Margin } else { 0 }
        BackgroundColor = $Props.BackgroundColor
        ForegroundColor = $Props.ForegroundColor
        _isDirty = $true
        _cachedLayout = $null
        
        AddChild = { 
            param($self, $Child, [hashtable]$LayoutProps = @{})
            
            Invoke-WithErrorHandling -Component "$($self.Name).AddChild" -Context "Adding child component" -ScriptBlock {
                if (-not $Child) {
                    throw "Cannot add null child to panel"
                }
                
                $Child.Parent = $self
                $Child.LayoutProps = $LayoutProps
                $self.Children += $Child
                $self._isDirty = $true
                
                # Propagate visibility
                if (-not $self.Visible) {
                    $Child.Visible = $false
                }
            } -AdditionalData @{
                ParentPanel = $self.Name
                ChildType = if ($Child.Type) { $Child.Type } else { "Unknown" }
                ChildName = if ($Child.Name) { $Child.Name } else { "Unnamed" }
            }
        }
        
        RemoveChild = {
            param($self, $Child)
            
            Invoke-WithErrorHandling -Component "$($self.Name).RemoveChild" -Context "Removing child component" -ScriptBlock {
                $self.Children = $self.Children | Where-Object { $_ -ne $Child }
                if ($Child.Parent -eq $self) {
                    $Child.Parent = $null
                }
                $self._isDirty = $true
            } -AdditionalData @{
                ParentPanel = $self.Name
                ChildName = if ($Child.Name) { $Child.Name } else { "Unnamed" }
            }
        }
        
        Show = { 
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Name).Show" -Context "Showing panel" -ScriptBlock {
                $self.Visible = $true
                foreach ($child in $self.Children) { 
                    if ($child.Show) { 
                        & $child.Show -self $child
                    } else { 
                        $child.Visible = $true
                    }
                }
                
                if (Get-Command -Name "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                    Request-TuiRefresh
                }
            }
        }
        
        Hide = { 
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Name).Hide" -Context "Hiding panel" -ScriptBlock {
                $self.Visible = $false
                foreach ($child in $self.Children) { 
                    if ($child.Hide) { 
                        & $child.Hide -self $child
                    } else { 
                        $child.Visible = $false
                    }
                }
                
                if (Get-Command -Name "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                    Request-TuiRefresh
                }
            }
        }
        
        HandleInput = { 
            param($self, $Key)
            Invoke-WithErrorHandling -Component "$($self.Name).HandleInput" -Context "Handling input" -ScriptBlock {
                # Panels typically don't handle input directly
                return $false
            } -AdditionalData @{
                KeyPressed = if ($Key) { $Key.ToString() } else { "Unknown" }
            }
        }
        
        GetContentBounds = {
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Name).GetContentBounds" -Context "Calculating content bounds" -ScriptBlock {
                $borderOffset = if ($self.ShowBorder) { 1 } else { 0 }
                
                # AI: Resolve percentage values for width and height
                $resolvedWidth = Resolve-Dimension -Dimension $self.Width -ParentSize $global:TuiState.BufferWidth
                $resolvedHeight = Resolve-Dimension -Dimension $self.Height -ParentSize $global:TuiState.BufferHeight
                
                return @{
                    X = $self.X + $self.Padding + $borderOffset + $self.Margin
                    Y = $self.Y + $self.Padding + $borderOffset + $self.Margin
                    Width = $resolvedWidth - (2 * ($self.Padding + $borderOffset + $self.Margin))
                    Height = $resolvedHeight - (2 * ($self.Padding + $borderOffset + $self.Margin))
                }
            }
        }
        
        InvalidateLayout = {
            param($self)
            Invoke-WithErrorHandling -Component "$($self.Name).InvalidateLayout" -Context "Invalidating layout" -ScriptBlock {
                $self._isDirty = $true
                
                # Propagate to parent
                if ($self.Parent -and $self.Parent.InvalidateLayout) {
                    & $self.Parent.InvalidateLayout -self $self.Parent
                }
            }
        }
    }
    
    return $panel
}

function global:New-TuiStackPanel {
    param([hashtable]$Props = @{})
    
    $panel = New-BasePanel -Props $Props
    $panel.Type = "StackPanel"
    $panel.Layout = 'Stack'
    $panel.Orientation = if ($null -ne $Props.Orientation) { $Props.Orientation } else { 'Vertical' }
    $panel.Spacing = if ($null -ne $Props.Spacing) { $Props.Spacing } else { 1 }
    $panel.HorizontalAlignment = if ($null -ne $Props.HorizontalAlignment) { $Props.HorizontalAlignment } else { 'Stretch' }
    $panel.VerticalAlignment = if ($null -ne $Props.VerticalAlignment) { $Props.VerticalAlignment } else { 'Stretch' }
    
    $panel.CalculateLayout = {
        param($self)
        Invoke-WithErrorHandling -Component "$($self.Name).CalculateLayout" -Context "Calculating stack layout" -ScriptBlock {
            $bounds = & $self.GetContentBounds -self $self
            $layout = @{
                Children = @()
            }
            
            $currentX = $bounds.X
            $currentY = $bounds.Y
            $visibleChildren = $self.Children | Where-Object { $_.Visible }
            
            foreach ($child in $visibleChildren) {
                # AI: Resolve percentage dimensions for child sizes
                $childWidth = if ($self.Orientation -eq 'Horizontal') { 
                    Resolve-Dimension -Dimension $child.Width -ParentSize $bounds.Width 
                } else { 
                    $bounds.Width 
                }
                
                $childHeight = if ($self.Orientation -eq 'Vertical') { 
                    Resolve-Dimension -Dimension $child.Height -ParentSize $bounds.Height 
                } else { 
                    $bounds.Height 
                }
                
                $childLayout = @{
                    Component = $child
                    X = $currentX
                    Y = $currentY
                    Width = $childWidth
                    Height = $childHeight
                }
                
                # Update child position
                $child.X = $childLayout.X
                $child.Y = $childLayout.Y
                
                $layout.Children += $childLayout
                
                # Move to next position
                if ($self.Orientation -eq 'Vertical') {
                    $currentY += $childHeight + $self.Spacing
                } else {
                    $currentX += $childWidth + $self.Spacing
                }
            }
            
            $self._cachedLayout = $layout
            $self._isDirty = $false
            return $layout
        } -AdditionalData @{
            Orientation = $self.Orientation
            ChildrenCount = $self.Children.Count
        }
    }
    
    $panel.Render = {
        param($self)
        Invoke-WithErrorHandling -Component "$($self.Name).Render" -Context "Rendering stack panel" -ScriptBlock {
            if (-not $self.Visible) { return }
            
            # Clear panel area first
            $bgColor = if ($self.BackgroundColor) { 
                $self.BackgroundColor 
            } else { 
                if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
                    Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
                } else {
                    [ConsoleColor]::Black
                }
            }
            
            if ($self.ShowBorder) {
                $borderColor = if ($self.BorderColor) {
                    if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
                        Get-ThemeColor $self.BorderColor -Default ([ConsoleColor]::Gray)
                    } else {
                        [ConsoleColor]::Gray
                    }
                } else { 
                    [ConsoleColor]::Gray
                }
                
                # AI: Resolve percentage dimensions before rendering
                $resolvedWidth = Resolve-Dimension -Dimension $self.Width -ParentSize $global:TuiState.BufferWidth
                $resolvedHeight = Resolve-Dimension -Dimension $self.Height -ParentSize $global:TuiState.BufferHeight
                
                if (Get-Command -Name "Write-BufferBox" -ErrorAction SilentlyContinue) {
                    Write-BufferBox -X $self.X -Y $self.Y -Width $resolvedWidth -Height $resolvedHeight `
                        -BorderColor $borderColor -BackgroundColor $bgColor `
                        -BorderStyle $self.BorderStyle -Title $self.Title
                }
            }
            
            # Calculate layout
            & $self.CalculateLayout -self $self
        }
    }
    
    return $panel
}

function global:New-TuiGridPanel {
    param([hashtable]$Props = @{})
    
    $panel = New-BasePanel -Props $Props
    $panel.Type = "GridPanel"
    $panel.Layout = 'Grid'
    $panel.RowDefinitions = if ($Props.RowDefinitions) { $Props.RowDefinitions } else { @("1*") }
    $panel.ColumnDefinitions = if ($Props.ColumnDefinitions) { $Props.ColumnDefinitions } else { @("1*") }
    $panel.ShowGridLines = if ($null -ne $Props.ShowGridLines) { $Props.ShowGridLines } else { $false }
    $panel.GridLineColor = if ($Props.GridLineColor) { $Props.GridLineColor } else { "Border" }
    
    $panel.CalculateLayout = {
        param($self)
        Invoke-WithErrorHandling -Component "$($self.Name).CalculateLayout" -Context "Calculating grid layout" -ScriptBlock {
            $bounds = & $self.GetContentBounds -self $self
            
            # Calculate row and column sizes
            $rowSizes = $self._CalculateDimensions($self.RowDefinitions, $bounds.Height)
            $colSizes = $self._CalculateDimensions($self.ColumnDefinitions, $bounds.Width)
            
            # Calculate offsets
            $rowOffsets = @(0)
            for ($i = 0; $i -lt $rowSizes.Count; $i++) {
                $rowOffsets += $rowOffsets[-1] + $rowSizes[$i]
            }
            
            $colOffsets = @(0)
            for ($i = 0; $i -lt $colSizes.Count; $i++) {
                $colOffsets += $colOffsets[-1] + $colSizes[$i]
            }
            
            $layout = @{
                Children = @()
                RowOffsets = $rowOffsets
                ColumnOffsets = $colOffsets
                RowSizes = $rowSizes
                ColumnSizes = $colSizes
            }
            
            # Position children
            foreach ($child in $self.Children) {
                if (-not $child.Visible) { continue }
                
                $row = if ($child.LayoutProps -and $child.LayoutProps["Grid.Row"]) { $child.LayoutProps["Grid.Row"] } else { 0 }
                $col = if ($child.LayoutProps -and $child.LayoutProps["Grid.Column"]) { $child.LayoutProps["Grid.Column"] } else { 0 }
                
                # Bounds checking
                if ($row -ge $rowSizes.Count) { $row = $rowSizes.Count - 1 }
                if ($col -ge $colSizes.Count) { $col = $colSizes.Count - 1 }
                if ($row -lt 0) { $row = 0 }
                if ($col -lt 0) { $col = 0 }
                
                $childLayout = @{
                    Component = $child
                    X = $bounds.X + $colOffsets[$col]
                    Y = $bounds.Y + $rowOffsets[$row]
                    Width = $colSizes[$col]
                    Height = $rowSizes[$row]
                    GridRow = $row
                    GridColumn = $col
                }
                
                # Update child position
                $child.X = $childLayout.X
                $child.Y = $childLayout.Y
                
                $layout.Children += $childLayout
            }
            
            $self._cachedLayout = $layout
            $self._isDirty = $false
            return $layout
        } -AdditionalData @{
            RowDefinitions = $self.RowDefinitions
            ColumnDefinitions = $self.ColumnDefinitions
            ChildrenCount = $self.Children.Count
        }
    }
    
    # Helper method to calculate dimensions
    $panel._CalculateDimensions = {
        param($definitions, $totalSize)
        
        $fixedSize = 0
        $starCount = 0
        $sizes = @()
        
        # First pass: calculate fixed sizes and count stars
        foreach ($def in $definitions) {
            if ($def -match '^\d+$') {
                # Fixed size
                $size = [int]$def
                $sizes += $size
                $fixedSize += $size
            }
            elseif ($def -match '^(\d*\.?\d*)\*$') {
                # Star sizing
                $weight = if ($matches[1]) { [double]$matches[1] } else { 1.0 }
                $sizes += @{ Type = "Star"; Weight = $weight }
                $starCount += $weight
            }
            else {
                # Default to star
                $sizes += @{ Type = "Star"; Weight = 1.0 }
                $starCount += 1.0
            }
        }
        
        # Second pass: calculate star sizes
        $remainingSize = [Math]::Max(0, $totalSize - $fixedSize)
        $starSize = if ($starCount -gt 0) { $remainingSize / $starCount } else { 0 }
        
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            if ($sizes[$i] -is [hashtable] -and $sizes[$i].Type -eq "Star") {
                $sizes[$i] = [Math]::Floor($starSize * $sizes[$i].Weight)
            }
        }
        
        return $sizes
    }
    
    $panel.Render = {
        param($self)
        Invoke-WithErrorHandling -Component "$($self.Name).Render" -Context "Rendering grid panel" -ScriptBlock {
            if (-not $self.Visible) { return }
            
            # Clear panel area and draw border if needed
            $bgColor = if ($self.BackgroundColor) { 
                $self.BackgroundColor 
            } else { 
                if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
                    Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
                } else {
                    [ConsoleColor]::Black
                }
            }
            
            if ($self.ShowBorder) {
                $borderColor = if ($self.BorderColor) {
                    if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
                        Get-ThemeColor $self.BorderColor -Default ([ConsoleColor]::Gray)
                    } else {
                        [ConsoleColor]::Gray
                    }
                } else { 
                    [ConsoleColor]::Gray
                }
                
                # AI: Resolve percentage dimensions before rendering
                $resolvedWidth = Resolve-Dimension -Dimension $self.Width -ParentSize $global:TuiState.BufferWidth
                $resolvedHeight = Resolve-Dimension -Dimension $self.Height -ParentSize $global:TuiState.BufferHeight
                
                if (Get-Command -Name "Write-BufferBox" -ErrorAction SilentlyContinue) {
                    Write-BufferBox -X $self.X -Y $self.Y -Width $resolvedWidth -Height $resolvedHeight `
                        -BorderColor $borderColor -BackgroundColor $bgColor `
                        -BorderStyle $self.BorderStyle -Title $self.Title
                }
            }
            
            # Calculate layout
            $layout = & $self.CalculateLayout -self $self
            
            # Draw grid lines if enabled
            if ($self.ShowGridLines -and (Get-Command -Name "Write-BufferString" -ErrorAction SilentlyContinue)) {
                $bounds = & $self.GetContentBounds -self $self
                $gridColor = if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
                    Get-ThemeColor $self.GridLineColor -Default ([ConsoleColor]::Gray)
                } else {
                    [ConsoleColor]::Gray
                }
                
                # Vertical lines
                foreach ($offset in $layout.ColumnOffsets[1..($layout.ColumnOffsets.Count - 1)]) {
                    $x = $bounds.X + $offset
                    for ($y = $bounds.Y; $y -lt ($bounds.Y + $bounds.Height); $y++) { 
                        Write-BufferString -X $x -Y $y -Text "│" -ForegroundColor $gridColor
                    }
                }
                
                # Horizontal lines
                foreach ($offset in $layout.RowOffsets[1..($layout.RowOffsets.Count - 1)]) {
                    $y = $bounds.Y + $offset
                    Write-BufferString -X $bounds.X -Y $y -Text ("─" * $bounds.Width) -ForegroundColor $gridColor
                }
            }
        }
    }
    
    return $panel
}

function global:New-TuiDockPanel { 
    param([hashtable]$Props = @{}) 
    $dockProps = $Props.Clone()
    $dockProps.Orientation = 'Vertical'
    return New-TuiStackPanel -Props $dockProps
}

function global:New-TuiWrapPanel { 
    param([hashtable]$Props = @{}) 
    return New-TuiStackPanel -Props $Props 
}

Export-ModuleMember -Function @("New-BasePanel", "New-TuiStackPanel", "New-TuiGridPanel", "New-TuiDockPanel", "New-TuiWrapPanel")