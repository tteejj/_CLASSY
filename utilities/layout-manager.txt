# Layout Manager Utility Module
# Provides helper functions for component positioning and layout management

function global:New-TuiLayoutManager {
    <#
    .SYNOPSIS
    Creates a layout manager for organizing components within a container
    
    .DESCRIPTION
    The layout manager helps with automatic positioning, spacing, and alignment of components.
    It provides various layout modes: Stack, Grid, Dock, and Manual.
    
    .PARAMETER Container
    A hashtable with X, Y, Width, Height properties defining the container bounds
    
    .PARAMETER Mode
    Layout mode: 'Stack', 'Grid', 'Dock', or 'Manual'
    
    .EXAMPLE
    $layout = New-TuiLayoutManager -Container @{X=0; Y=0; Width=80; Height=25} -Mode 'Stack'
    $layout.Add($component1)
    $layout.Add($component2)
    $layout.Apply()
    #>
    param(
        [hashtable]$Container = @{ X = 0; Y = 0; Width = 80; Height = 25 },
        [string]$Mode = 'Manual',
        [hashtable]$Options = @{}
    )
    
    $manager = @{
        Container = $Container
        Mode = $Mode
        Components = @()
        Options = @{
            # Stack options
            Direction = $Options.Direction ?? 'Vertical'  # 'Vertical' or 'Horizontal'
            Spacing = $Options.Spacing ?? 1
            Padding = $Options.Padding ?? @{ Top = 0; Right = 0; Bottom = 0; Left = 0 }
            Alignment = $Options.Alignment ?? 'Left'  # 'Left', 'Center', 'Right'
            
            # Grid options
            Columns = $Options.Columns ?? 2
            RowHeight = $Options.RowHeight ?? 5
            ColumnWidth = $Options.ColumnWidth ?? 20
            
            # Dock options
            FillLast = $Options.FillLast ?? $true
        }
        
        # Methods
        Add = {
            param($Component, [hashtable]$LayoutProps = @{})
            $this = $args[-1]
            $this.Components += @{
                Component = $Component
                LayoutProps = $LayoutProps
            }
        }.GetNewClosure()
        
        Clear = {
            $this = $args[-1]
            $this.Components = @()
        }.GetNewClosure()
        
        Apply = {
            $this = $args[-1]
            switch ($this.Mode) {
                'Stack' { & $this.ApplyStackLayout }
                'Grid' { & $this.ApplyGridLayout }
                'Dock' { & $this.ApplyDockLayout }
                'Manual' { # Do nothing - components use their existing positions }
            }
        }.GetNewClosure()
        
        ApplyStackLayout = {
            $this = $args[-1]
            $x = $this.Container.X + $this.Options.Padding.Left
            $y = $this.Container.Y + $this.Options.Padding.Top
            $maxWidth = $this.Container.Width - $this.Options.Padding.Left - $this.Options.Padding.Right
            $maxHeight = $this.Container.Height - $this.Options.Padding.Top - $this.Options.Padding.Bottom
            
            foreach ($item in $this.Components) {
                $comp = $item.Component
                
                # Apply alignment
                switch ($this.Options.Alignment) {
                    'Center' { $comp.X = $x + [Math]::Floor(($maxWidth - $comp.Width) / 2) }
                    'Right' { $comp.X = $x + $maxWidth - $comp.Width }
                    default { $comp.X = $x }
                }
                
                if ($this.Options.Direction -eq 'Vertical') {
                    $comp.Y = $y
                    $y += $comp.Height + $this.Options.Spacing
                } else {
                    $comp.Y = $y
                    $x += $comp.Width + $this.Options.Spacing
                }
            }
        }.GetNewClosure()
        
        ApplyGridLayout = {
            $this = $args[-1]
            $startX = $this.Container.X + $this.Options.Padding.Left
            $startY = $this.Container.Y + $this.Options.Padding.Top
            $cols = $this.Options.Columns
            
            for ($i = 0; $i -lt $this.Components.Count; $i++) {
                $comp = $this.Components[$i].Component
                $row = [Math]::Floor($i / $cols)
                $col = $i % $cols
                
                $comp.X = $startX + ($col * ($this.Options.ColumnWidth + $this.Options.Spacing))
                $comp.Y = $startY + ($row * ($this.Options.RowHeight + $this.Options.Spacing))
                
                # Optionally constrain size to grid cell
                if ($this.Components[$i].LayoutProps.ConstrainToCell) {
                    $comp.Width = [Math]::Min($comp.Width, $this.Options.ColumnWidth)
                    $comp.Height = [Math]::Min($comp.Height, $this.Options.RowHeight)
                }
            }
        }.GetNewClosure()
        
        ApplyDockLayout = {
            $this = $args[-1]
            $remainingX = $this.Container.X
            $remainingY = $this.Container.Y
            $remainingWidth = $this.Container.Width
            $remainingHeight = $this.Container.Height
            
            # Process in order: Top, Bottom, Left, Right, Fill
            $dockOrder = @('Top', 'Bottom', 'Left', 'Right', 'Fill')
            
            foreach ($dock in $dockOrder) {
                $items = $this.Components | Where-Object { $_.LayoutProps.Dock -eq $dock }
                
                foreach ($item in $items) {
                    $comp = $item.Component
                    
                    switch ($dock) {
                        'Top' {
                            $comp.X = $remainingX
                            $comp.Y = $remainingY
                            $comp.Width = $remainingWidth
                            $remainingY += $comp.Height
                            $remainingHeight -= $comp.Height
                        }
                        'Bottom' {
                            $comp.X = $remainingX
                            $comp.Y = $remainingY + $remainingHeight - $comp.Height
                            $comp.Width = $remainingWidth
                            $remainingHeight -= $comp.Height
                        }
                        'Left' {
                            $comp.X = $remainingX
                            $comp.Y = $remainingY
                            $comp.Height = $remainingHeight
                            $remainingX += $comp.Width
                            $remainingWidth -= $comp.Width
                        }
                        'Right' {
                            $comp.X = $remainingX + $remainingWidth - $comp.Width
                            $comp.Y = $remainingY
                            $comp.Height = $remainingHeight
                            $remainingWidth -= $comp.Width
                        }
                        'Fill' {
                            $comp.X = $remainingX
                            $comp.Y = $remainingY
                            $comp.Width = $remainingWidth
                            $comp.Height = $remainingHeight
                        }
                    }
                }
            }
        }.GetNewClosure()
        
        # Helper to calculate required size
        GetRequiredSize = {
            $this = $args[-1]
            $width = 0
            $height = 0
            
            switch ($this.Mode) {
                'Stack' {
                    if ($this.Options.Direction -eq 'Vertical') {
                        $width = ($this.Components | ForEach-Object { $_.Component.Width } | Measure-Object -Maximum).Maximum
                        $height = ($this.Components | ForEach-Object { $_.Component.Height } | Measure-Object -Sum).Sum
                        $height += ($this.Components.Count - 1) * $this.Options.Spacing
                    } else {
                        $width = ($this.Components | ForEach-Object { $_.Component.Width } | Measure-Object -Sum).Sum
                        $width += ($this.Components.Count - 1) * $this.Options.Spacing
                        $height = ($this.Components | ForEach-Object { $_.Component.Height } | Measure-Object -Maximum).Maximum
                    }
                }
                'Grid' {
                    $cols = $this.Options.Columns
                    $rows = [Math]::Ceiling($this.Components.Count / $cols)
                    $width = $cols * $this.Options.ColumnWidth + ($cols - 1) * $this.Options.Spacing
                    $height = $rows * $this.Options.RowHeight + ($rows - 1) * $this.Options.Spacing
                }
            }
            
            $width += $this.Options.Padding.Left + $this.Options.Padding.Right
            $height += $this.Options.Padding.Top + $this.Options.Padding.Bottom
            
            return @{ Width = $width; Height = $height }
        }.GetNewClosure()
    }
    
    # Bind methods to the manager instance
    $manager.Add = $manager.Add.Invoke(@($manager))
    $manager.Clear = $manager.Clear.Invoke(@($manager))
    $manager.Apply = $manager.Apply.Invoke(@($manager))
    $manager.ApplyStackLayout = $manager.ApplyStackLayout.Invoke(@($manager))
    $manager.ApplyGridLayout = $manager.ApplyGridLayout.Invoke(@($manager))
    $manager.ApplyDockLayout = $manager.ApplyDockLayout.Invoke(@($manager))
    $manager.GetRequiredSize = $manager.GetRequiredSize.Invoke(@($manager))
    
    return $manager
}

function global:Center-Component {
    <#
    .SYNOPSIS
    Centers a component within a container
    #>
    param(
        [hashtable]$Component,
        [hashtable]$Container = @{ X = 0; Y = 0; Width = $global:TuiState.BufferWidth; Height = $global:TuiState.BufferHeight }
    )
    
    $Component.X = $Container.X + [Math]::Floor(($Container.Width - $Component.Width) / 2)
    $Component.Y = $Container.Y + [Math]::Floor(($Container.Height - $Component.Height) / 2)
}

function global:Align-Components {
    <#
    .SYNOPSIS
    Aligns multiple components horizontally or vertically
    #>
    param(
        [hashtable[]]$Components,
        [string]$Direction = 'Horizontal',  # 'Horizontal' or 'Vertical'
        [string]$Alignment = 'Center',      # 'Top', 'Middle', 'Bottom' for horizontal; 'Left', 'Center', 'Right' for vertical
        [int]$Spacing = 2
    )
    
    if ($Components.Count -eq 0) { return }
    
    if ($Direction -eq 'Horizontal') {
        # Calculate total width needed
        $totalWidth = ($Components | ForEach-Object { $_.Width } | Measure-Object -Sum).Sum
        $totalWidth += ($Components.Count - 1) * $Spacing
        
        # Starting X position
        $currentX = switch ($Alignment) {
            'Left' { 0 }
            'Right' { $global:TuiState.BufferWidth - $totalWidth }
            default { [Math]::Floor(($global:TuiState.BufferWidth - $totalWidth) / 2) }
        }
        
        # Position each component
        foreach ($comp in $Components) {
            $comp.X = $currentX
            $currentX += $comp.Width + $Spacing
        }
    } else {
        # Calculate total height needed
        $totalHeight = ($Components | ForEach-Object { $_.Height } | Measure-Object -Sum).Sum
        $totalHeight += ($Components.Count - 1) * $Spacing
        
        # Starting Y position
        $currentY = switch ($Alignment) {
            'Top' { 0 }
            'Bottom' { $global:TuiState.BufferHeight - $totalHeight }
            default { [Math]::Floor(($global:TuiState.BufferHeight - $totalHeight) / 2) }
        }
        
        # Position each component
        foreach ($comp in $Components) {
            $comp.Y = $currentY
            $currentY += $comp.Height + $Spacing
        }
    }
}

function global:Create-ComponentGrid {
    <#
    .SYNOPSIS
    Arranges components in a grid layout
    #>
    param(
        [hashtable[]]$Components,
        [int]$Columns = 2,
        [int]$StartX = 0,
        [int]$StartY = 0,
        [int]$CellWidth = 20,
        [int]$CellHeight = 5,
        [int]$HorizontalSpacing = 2,
        [int]$VerticalSpacing = 1
    )
    
    for ($i = 0; $i -lt $Components.Count; $i++) {
        $row = [Math]::Floor($i / $Columns)
        $col = $i % $Columns
        
        $Components[$i].X = $StartX + ($col * ($CellWidth + $HorizontalSpacing))
        $Components[$i].Y = $StartY + ($row * ($CellHeight + $VerticalSpacing))
    }
}

Export-ModuleMember -Function @(
    'New-TuiLayoutManager',
    'Center-Component',
    'Align-Components',
    'Create-ComponentGrid'
)