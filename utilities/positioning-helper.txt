# Component Positioning Helper Module
# Provides utilities for easier component placement and relative positioning

function global:New-TuiPositioner {
    <#
    .SYNOPSIS
    Creates a positioning helper for managing component placement
    
    .DESCRIPTION
    The positioner helps calculate positions for components relative to each other
    and handles common layout patterns like rows, columns, and grids.
    
    .PARAMETER Container
    Defines the bounding container for positioning
    
    .EXAMPLE
    $pos = New-TuiPositioner -Container @{X=0; Y=0; Width=80; Height=25}
    $button1Pos = $pos.NextInRow(10, 3)  # Width=10, Height=3
    $button2Pos = $pos.NextInRow(10, 3)  # Automatically positioned after button1
    #>
    param(
        [hashtable]$Container = @{ X = 0; Y = 0; Width = 80; Height = 25 },
        [hashtable]$Options = @{}
    )
    
    $positioner = @{
        Container = $Container
        CurrentX = $Container.X + ($Options.PaddingLeft ?? 0)
        CurrentY = $Container.Y + ($Options.PaddingTop ?? 0)
        RowHeight = 0
        Options = @{
            Spacing = $Options.Spacing ?? 1
            PaddingTop = $Options.PaddingTop ?? 0
            PaddingRight = $Options.PaddingRight ?? 0
            PaddingBottom = $Options.PaddingBottom ?? 0
            PaddingLeft = $Options.PaddingLeft ?? 0
        }
        
        # Reset to start of container
        Reset = {
            $this.CurrentX = $this.Container.X + $this.Options.PaddingLeft
            $this.CurrentY = $this.Container.Y + $this.Options.PaddingTop
            $this.RowHeight = 0
        }
        
        # Move to next row
        NewRow = {
            $this.CurrentX = $this.Container.X + $this.Options.PaddingLeft
            $this.CurrentY += $this.RowHeight + $this.Options.Spacing
            $this.RowHeight = 0
        }
        
        # Get next position in current row
        NextInRow = {
            param([int]$Width, [int]$Height)
            
            # Check if component fits in current row
            $maxX = $this.Container.X + $this.Container.Width - $this.Options.PaddingRight
            if (($this.CurrentX + $Width) -gt $maxX) {
                & $this.NewRow
            }
            
            $position = @{
                X = $this.CurrentX
                Y = $this.CurrentY
                Width = $Width
                Height = $Height
            }
            
            # Update position for next component
            $this.CurrentX += $Width + $this.Options.Spacing
            $this.RowHeight = [Math]::Max($this.RowHeight, $Height)
            
            return $position
        }
        
        # Get next position in current column
        NextInColumn = {
            param([int]$Width, [int]$Height)
            
            # Check if component fits in current column
            $maxY = $this.Container.Y + $this.Container.Height - $this.Options.PaddingBottom
            if (($this.CurrentY + $Height) -gt $maxY) {
                # Move to next column
                $this.CurrentY = $this.Container.Y + $this.Options.PaddingTop
                $this.CurrentX += $Width + $this.Options.Spacing
            }
            
            $position = @{
                X = $this.CurrentX
                Y = $this.CurrentY
                Width = $Width
                Height = $Height
            }
            
            # Update position for next component
            $this.CurrentY += $Height + $this.Options.Spacing
            
            return $position
        }
        
        # Position at specific coordinates
        At = {
            param([int]$X, [int]$Y, [int]$Width, [int]$Height)
            
            $this.CurrentX = $X + $Width + $this.Options.Spacing
            $this.CurrentY = $Y
            $this.RowHeight = $Height
            
            return @{
                X = $X
                Y = $Y
                Width = $Width
                Height = $Height
            }
        }
        
        # Position relative to another position
        RelativeTo = {
            param(
                [hashtable]$Reference,
                [string]$Direction = "Right",  # Right, Left, Above, Below
                [int]$Width,
                [int]$Height,
                [int]$Offset = $null
            )
            
            if ($null -eq $Offset) { $Offset = $this.Options.Spacing }
            
            $position = switch ($Direction) {
                "Right" {
                    @{
                        X = $Reference.X + $Reference.Width + $Offset
                        Y = $Reference.Y
                        Width = $Width
                        Height = $Height
                    }
                }
                "Left" {
                    @{
                        X = $Reference.X - $Width - $Offset
                        Y = $Reference.Y
                        Width = $Width
                        Height = $Height
                    }
                }
                "Below" {
                    @{
                        X = $Reference.X
                        Y = $Reference.Y + $Reference.Height + $Offset
                        Width = $Width
                        Height = $Height
                    }
                }
                "Above" {
                    @{
                        X = $Reference.X
                        Y = $Reference.Y - $Height - $Offset
                        Width = $Width
                        Height = $Height
                    }
                }
            }
            
            return $position
        }
        
        # Center component in container
        Center = {
            param([int]$Width, [int]$Height)
            
            return @{
                X = $this.Container.X + [Math]::Floor(($this.Container.Width - $Width) / 2)
                Y = $this.Container.Y + [Math]::Floor(($this.Container.Height - $Height) / 2)
                Width = $Width
                Height = $Height
            }
        }
        
        # Align to edges
        AlignTopLeft = {
            param([int]$Width, [int]$Height)
            return @{
                X = $this.Container.X + $this.Options.PaddingLeft
                Y = $this.Container.Y + $this.Options.PaddingTop
                Width = $Width
                Height = $Height
            }
        }
        
        AlignTopRight = {
            param([int]$Width, [int]$Height)
            return @{
                X = $this.Container.X + $this.Container.Width - $Width - $this.Options.PaddingRight
                Y = $this.Container.Y + $this.Options.PaddingTop
                Width = $Width
                Height = $Height
            }
        }
        
        AlignBottomLeft = {
            param([int]$Width, [int]$Height)
            return @{
                X = $this.Container.X + $this.Options.PaddingLeft
                Y = $this.Container.Y + $this.Container.Height - $Height - $this.Options.PaddingBottom
                Width = $Width
                Height = $Height
            }
        }
        
        AlignBottomRight = {
            param([int]$Width, [int]$Height)
            return @{
                X = $this.Container.X + $this.Container.Width - $Width - $this.Options.PaddingRight
                Y = $this.Container.Y + $this.Container.Height - $Height - $this.Options.PaddingBottom
                Width = $Width
                Height = $Height
            }
        }
    }
    
    return $positioner
}

function global:Position-Components {
    <#
    .SYNOPSIS
    Positions multiple components using a layout pattern
    
    .PARAMETER Components
    Array of component hashtables to position
    
    .PARAMETER Pattern
    Layout pattern: 'Row', 'Column', 'Grid', 'Flow'
    
    .PARAMETER Container
    Container bounds
    
    .PARAMETER Options
    Layout options (spacing, columns for grid, etc.)
    #>
    param(
        [hashtable[]]$Components,
        [string]$Pattern = 'Row',
        [hashtable]$Container = @{ X = 0; Y = 0; Width = 80; Height = 25 },
        [hashtable]$Options = @{}
    )
    
    $spacing = $Options.Spacing ?? 1
    $padding = $Options.Padding ?? @{ Top = 0; Right = 0; Bottom = 0; Left = 0 }
    
    switch ($Pattern) {
        'Row' {
            $x = $Container.X + $padding.Left
            $y = $Container.Y + $padding.Top
            
            foreach ($comp in $Components) {
                $comp.X = $x
                $comp.Y = $y
                $x += $comp.Width + $spacing
            }
        }
        
        'Column' {
            $x = $Container.X + $padding.Left
            $y = $Container.Y + $padding.Top
            
            foreach ($comp in $Components) {
                $comp.X = $x
                $comp.Y = $y
                $y += $comp.Height + $spacing
            }
        }
        
        'Grid' {
            $columns = $Options.Columns ?? 2
            $x = $Container.X + $padding.Left
            $y = $Container.Y + $padding.Top
            $col = 0
            $rowHeight = 0
            
            foreach ($comp in $Components) {
                if ($col -ge $columns) {
                    $col = 0
                    $x = $Container.X + $padding.Left
                    $y += $rowHeight + $spacing
                    $rowHeight = 0
                }
                
                $comp.X = $x
                $comp.Y = $y
                $x += $comp.Width + $spacing
                $rowHeight = [Math]::Max($rowHeight, $comp.Height)
                $col++
            }
        }
        
        'Flow' {
            $x = $Container.X + $padding.Left
            $y = $Container.Y + $padding.Top
            $maxX = $Container.X + $Container.Width - $padding.Right
            $rowHeight = 0
            
            foreach ($comp in $Components) {
                # Check if component fits in current row
                if (($x + $comp.Width) -gt $maxX -and $x -ne ($Container.X + $padding.Left)) {
                    # Move to next row
                    $x = $Container.X + $padding.Left
                    $y += $rowHeight + $spacing
                    $rowHeight = 0
                }
                
                $comp.X = $x
                $comp.Y = $y
                $x += $comp.Width + $spacing
                $rowHeight = [Math]::Max($rowHeight, $comp.Height)
            }
        }
    }
}

function global:Get-RelativePosition {
    <#
    .SYNOPSIS
    Calculate position relative to another component
    #>
    param(
        [hashtable]$Reference,
        [string]$Direction = "Right",
        [int]$Offset = 1
    )
    
    switch ($Direction) {
        "Right" { return @{ X = $Reference.X + $Reference.Width + $Offset; Y = $Reference.Y } }
        "Left" { return @{ X = $Reference.X - $Offset; Y = $Reference.Y } }
        "Above" { return @{ X = $Reference.X; Y = $Reference.Y - $Offset } }
        "Below" { return @{ X = $Reference.X; Y = $Reference.Y + $Reference.Height + $Offset } }
        "TopRight" { return @{ X = $Reference.X + $Reference.Width + $Offset; Y = $Reference.Y } }
        "TopLeft" { return @{ X = $Reference.X - $Offset; Y = $Reference.Y } }
        "BottomRight" { return @{ X = $Reference.X + $Reference.Width + $Offset; Y = $Reference.Y + $Reference.Height } }
        "BottomLeft" { return @{ X = $Reference.X - $Offset; Y = $Reference.Y + $Reference.Height } }
    }
}

Export-ModuleMember -Function @(
    'New-TuiPositioner',
    'Position-Components',
    'Get-RelativePosition'
)