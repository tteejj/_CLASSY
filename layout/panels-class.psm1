# Panel Classes Module for PMC Terminal v5
# Implements specialized panel types for the TUI layout system

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# AI: FIX - All internal Import-Module statements removed. Dependencies are managed by _CLASSY-MAIN.ps1.

# BorderPanel - Panel with customizable border rendering
class BorderPanel : Panel {
    [ConsoleColor] $BorderColor = [ConsoleColor]::Gray
    [string] $BorderStyle = "Single" # Single, Double, Rounded
    [ConsoleColor] $TitleColor = [ConsoleColor]::White
    
    hidden static [hashtable] $BorderChars = @{
        Single = @{
            TopLeft = '┌'; TopRight = '┐'; BottomLeft = '└'; BottomRight = '┘'
            Horizontal = '─'; Vertical = '│'
        }
        Double = @{
            TopLeft = '╔'; TopRight = '╗'; BottomLeft = '╚'; BottomRight = '╝'
            Horizontal = '═'; Vertical = '║'
        }
        Rounded = @{
            TopLeft = '╭'; TopRight = '╮'; BottomLeft = '╰'; BottomRight = '╯'
            Horizontal = '─'; Vertical = '│'
        }
    }
    
    BorderPanel([string]$name, [int]$x, [int]$y, [int]$width, [int]$height) : base($name, $x, $y, $width, $height) {
    }
    
    # AI: FIX - Implemented _RenderContent() instead of overriding Render() to preserve the base class error-handling wrapper.
    hidden [string] _RenderContent() {
        $renderedContent = [System.Text.StringBuilder]::new()
        
        if ($this.ShowBorder) {
            [void]$renderedContent.Append($this.RenderBorder())
        }
        
        if ($this.Children.Count -gt 0) {
            [void]$renderedContent.Append($this.RenderChildContent())
        }
        
        return $renderedContent.ToString()
    }
    
    hidden [string] RenderBorder() {
        $borderBuilder = [System.Text.StringBuilder]::new()
        $chars = [BorderPanel]::BorderChars[$this.BorderStyle]
        
        if ($null -eq $chars) {
            Write-Log -Level Warning -Message "Unknown border style: $($this.BorderStyle), defaulting to Single" -Component "BorderPanel"
            $chars = [BorderPanel]::BorderChars["Single"]
        }
        
        [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y))
        [void]$borderBuilder.Append($this.SetColor($this.BorderColor))
        [void]$borderBuilder.Append($chars.TopLeft)
        
        $horizontalSpace = $this.Width - 2
        if (-not [string]::IsNullOrWhiteSpace($this.Title)) {
            $titleText = " $($this.Title) "
            if ($titleText.Length -gt $horizontalSpace) {
                $titleText = $titleText.Substring(0, $horizontalSpace)
            }
            
            $paddingBefore = [Math]::Floor(($horizontalSpace - $titleText.Length) / 2)
            $paddingAfter = $horizontalSpace - $titleText.Length - $paddingBefore
            
            [void]$borderBuilder.Append($chars.Horizontal * $paddingBefore)
            [void]$borderBuilder.Append($this.SetColor($this.TitleColor))
            [void]$borderBuilder.Append($titleText)
            [void]$borderBuilder.Append($this.SetColor($this.BorderColor))
            [void]$borderBuilder.Append($chars.Horizontal * $paddingAfter)
        }
        else {
            [void]$borderBuilder.Append($chars.Horizontal * $horizontalSpace)
        }
        
        [void]$borderBuilder.Append($chars.TopRight)
        
        for ($row = 1; $row -lt $this.Height - 1; $row++) {
            [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $row))
            [void]$borderBuilder.Append($chars.Vertical)
            [void]$borderBuilder.Append($this.MoveCursor($this.X + $this.Width - 1, $this.Y + $row))
            [void]$borderBuilder.Append($chars.Vertical)
        }
        
        [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $this.Height - 1))
        [void]$borderBuilder.Append($chars.BottomLeft)
        [void]$borderBuilder.Append($chars.Horizontal * $horizontalSpace)
        [void]$borderBuilder.Append($chars.BottomRight)
        
        [void]$borderBuilder.Append($this.ResetColor())
        
        return $borderBuilder.ToString()
    }
    
    hidden [string] RenderChildContent() {
        $contentBuilder = [System.Text.StringBuilder]::new()
        
        foreach ($child in $this.Children) {
            if ($child.Visible) {
                [void]$contentBuilder.Append($child.Render())
            }
        }
        
        return $contentBuilder.ToString()
    }
    
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
    
    hidden [string] ResetColor() {
        return "`e[0m"
    }
}

class ContentPanel : Panel {
    [string[]] $Content = @()
    [int] $ScrollOffset = 0
    [ConsoleColor] $TextColor = [ConsoleColor]::White
    [bool] $WordWrap = $true
    
    ContentPanel([string]$name, [int]$x, [int]$y, [int]$width, [int]$height) : base($name, $x, $y, $width, $height) {
    }
    
    [void] SetContent([string[]]$content) {
        if ($null -eq $content) {
            $this.Content = @()
        }
        else {
            $this.Content = $content
        }
        $this.ScrollOffset = 0
    }
    
    [void] AppendContent([string]$line) {
        if ($null -ne $line) {
            $this.Content += $line
        }
    }
    
    [void] ClearContent() {
        $this.Content = @()
        $this.ScrollOffset = 0
    }
    
    [void] ScrollUp([int]$lines = 1) {
        $this.ScrollOffset = [Math]::Max(0, $this.ScrollOffset - $lines)
    }
    
    [void] ScrollDown([int]$lines = 1) {
        $maxOffset = [Math]::Max(0, $this.Content.Count - $this.GetContentArea().Height)
        $this.ScrollOffset = [Math]::Min($maxOffset, $this.ScrollOffset + $lines)
    }
    
    [void] ScrollToTop() {
        $this.ScrollOffset = 0
    }
    
    [void] ScrollToBottom() {
        $maxOffset = [Math]::Max(0, $this.Content.Count - $this.GetContentArea().Height)
        $this.ScrollOffset = $maxOffset
    }
    
    hidden [string] _RenderContent() {
        $contentBuilder = [System.Text.StringBuilder]::new()
        $contentArea = $this.GetContentArea()
        
        $processedLines = @()
        if ($this.WordWrap) {
            foreach ($line in $this.Content) {
                $processedLines += $this.WrapText($line, $contentArea.Width)
            }
        }
        else {
            $processedLines = $this.Content
        }
        
        $visibleLines = [Math]::Min($contentArea.Height, $processedLines.Count - $this.ScrollOffset)
        
        for ($i = 0; $i -lt $visibleLines; $i++) {
            $lineIndex = $this.ScrollOffset + $i
            if ($lineIndex -lt $processedLines.Count) {
                $line = $processedLines[$lineIndex]
                
                if ($line.Length -gt $contentArea.Width) {
                    $line = $line.Substring(0, $contentArea.Width)
                }
                
                [void]$contentBuilder.Append($this.MoveCursor($contentArea.X, $contentArea.Y + $i))
                [void]$contentBuilder.Append($this.SetColor($this.TextColor))
                [void]$contentBuilder.Append($line)
            }
        }
        
        $clearLine = ' ' * $contentArea.Width
        for ($i = $visibleLines; $i -lt $contentArea.Height; $i++) {
            [void]$contentBuilder.Append($this.MoveCursor($contentArea.X, $contentArea.Y + $i))
            [void]$contentBuilder.Append($clearLine)
        }
        
        [void]$contentBuilder.Append($this.ResetColor())
        
        return $contentBuilder.ToString()
    }
    
    hidden [string[]] WrapText([string]$text, [int]$maxWidth) {
        if ([string]::IsNullOrEmpty($text) -or $maxWidth -le 0) {
            return @()
        }
        
        $lines = [System.Collections.Generic.List[string]]::new()
        $words = $text -split '\s+'
        $currentLine = [System.Text.StringBuilder]::new()
        
        foreach ($word in $words) {
            if ($currentLine.Length -eq 0) {
                [void]$currentLine.Append($word)
            }
            elseif (($currentLine.Length + 1 + $word.Length) -le $maxWidth) {
                [void]$currentLine.Append(' ').Append($word)
            }
            else {
                $lines.Add($currentLine.ToString())
                $currentLine.Clear()
                [void]$currentLine.Append($word)
            }
        }
        
        if ($currentLine.Length -gt 0) {
            $lines.Add($currentLine.ToString())
        }
        
        return $lines.ToArray()
    }
    
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
    
    hidden [string] ResetColor() {
        return "`e[0m"
    }
}

# AI: FIX - Removed -Class parameter for PowerShell 5.1 compatibility
# Classes are automatically exported in PowerShell 5.1 when defined in a module