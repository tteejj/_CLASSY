# Panel Classes Module for PMC Terminal v5
# Implements specialized panel types for the TUI layout system

using namespace System.Management.Automation
using module ..\components\ui-classes.psm1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# BorderPanel - Panel with customizable border rendering
class BorderPanel : Panel {
    # ... (class content is unchanged) ...
    [ConsoleColor] $BorderColor = [ConsoleColor]::Gray
    [string] $BorderStyle = "Single" # Single, Double, Rounded
    [ConsoleColor] $TitleColor = [ConsoleColor]::White
    
    hidden static [hashtable] $BorderChars = @{
        Single  = @{ TopLeft='┌'; TopRight='┐'; BottomLeft='└'; BottomRight='┘'; Horizontal='─'; Vertical='│' }
        Double  = @{ TopLeft='╔'; TopRight='╗'; BottomLeft='╚'; BottomRight='╝'; Horizontal='═'; Vertical='║' }
        Rounded = @{ TopLeft='╭'; TopRight='╮'; BottomLeft='╰'; BottomRight='╯'; Horizontal='─'; Vertical='│' }
    }
    
    BorderPanel([string]$name, [int]$x, [int]$y, [int]$width, [int]$height) : base($name, $x, $y, $width, $height) {}
    
    hidden [string] _RenderContent() {
        if ($this.ShowBorder) {
            return $this.RenderBorder()
        }
        return ""
    }
    
    hidden [string] RenderBorder() {
        $borderBuilder = [System.Text.StringBuilder]::new()
        $chars = [BorderPanel]::BorderChars[$this.BorderStyle] ?? [BorderPanel]::BorderChars["Single"]
        
        [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y)).Append($this.SetColor($this.BorderColor)).Append($chars.TopLeft)
        
        $horizontalSpace = $this.Width - 2
        if (-not [string]::IsNullOrWhiteSpace($this.Title)) {
            $titleText = " $($this.Title) "
            if ($titleText.Length -gt $horizontalSpace) { $titleText = $titleText.Substring(0, $horizontalSpace) }
            
            $paddingBefore = [Math]::Floor(($horizontalSpace - $titleText.Length) / 2)
            $paddingAfter = $horizontalSpace - $titleText.Length - $paddingBefore
            
            [void]$borderBuilder.Append($chars.Horizontal * $paddingBefore).Append($this.SetColor($this.TitleColor)).Append($titleText)
            [void]$borderBuilder.Append($this.SetColor($this.BorderColor)).Append($chars.Horizontal * $paddingAfter)
        } else {
            [void]$borderBuilder.Append($chars.Horizontal * $horizontalSpace)
        }
        
        [void]$borderBuilder.Append($chars.TopRight)
        
        for ($row = 1; $row -lt $this.Height - 1; $row++) {
            [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $row)).Append($chars.Vertical)
            [void]$borderBuilder.Append($this.MoveCursor($this.X + $this.Width - 1, $this.Y + $row)).Append($chars.Vertical)
        }
        
        [void]$borderBuilder.Append($this.MoveCursor($this.X, $this.Y + $this.Height - 1))
        [void]$borderBuilder.Append($chars.BottomLeft).Append($chars.Horizontal * $horizontalSpace).Append($chars.BottomRight)
        [void]$borderBuilder.Append($this.ResetColor())
        
        return $borderBuilder.ToString()
    }
    
    hidden [string] MoveCursor([int]$x, [int]$y) { return "`e[$($y + 1);$($x + 1)H" }
    
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{ Black=30;DarkRed=31;DarkGreen=32;DarkYellow=33;DarkBlue=34;DarkMagenta=35;DarkCyan=36;Gray=37;DarkGray=90;Red=91;Green=92;Yellow=93;Blue=94;Magenta=95;Cyan=96;White=97 }
        return "`e[$($colorMap[$color.ToString()])m"
    }
    
    hidden [string] ResetColor() { return "`e[0m" }
}

class ContentPanel : Panel {
    # ... (class content is unchanged) ...
    [string[]] $Content = @()
    [int] $ScrollOffset = 0
    [ConsoleColor] $TextColor = [ConsoleColor]::White
    [bool] $WordWrap = $true
    
    ContentPanel([string]$name, [int]$x, [int]$y, [int]$width, [int]$height) : base($name, $x, $y, $width, $height) {}
    
    [void] SetContent([string[]]$content) {
        $this.Content = $content ?? @()
        $this.ScrollOffset = 0
    }
    
    [void] AppendContent([string]$line) {
        if ($null -ne $line) { $this.Content += $line }
    }
    
    [void] ClearContent() {
        $this.Content = @()
        $this.ScrollOffset = 0
    }
    
    [void] ScrollUp([int]$lines = 1) { $this.ScrollOffset = [Math]::Max(0, $this.ScrollOffset - $lines) }
    
    [void] ScrollDown([int]$lines = 1) {
        $maxOffset = [Math]::Max(0, $this.Content.Count - $this.GetContentArea().Height)
        $this.ScrollOffset = [Math]::Min($maxOffset, $this.ScrollOffset + $lines)
    }
    
    hidden [string] _RenderContent() {
        $contentBuilder = [System.Text.StringBuilder]::new()
        $contentArea = $this.GetContentArea()
        
        $processedLines = $this.WordWrap ? ($this.Content | ForEach-Object { $this.WrapText($_, $contentArea.Width) }) : $this.Content
        $visibleLinesCount = [Math]::Min($contentArea.Height, $processedLines.Count - $this.ScrollOffset)
        
        for ($i = 0; $i -lt $visibleLinesCount; $i++) {
            $lineIndex = $this.ScrollOffset + $i
            if ($lineIndex -lt $processedLines.Count) {
                $line = $processedLines[$lineIndex]
                if ($line.Length -gt $contentArea.Width) { $line = $line.Substring(0, $contentArea.Width) }
                [void]$contentBuilder.Append($this.MoveCursor($contentArea.X, $contentArea.Y + $i))
                [void]$contentBuilder.Append($this.SetColor($this.TextColor))
                [void]$contentBuilder.Append($line.PadRight($contentArea.Width))
            }
        }
        
        [void]$contentBuilder.Append($this.ResetColor())
        return $contentBuilder.ToString()
    }
    
    hidden [string[]] WrapText([string]$text, [int]$maxWidth) {
        if ([string]::IsNullOrEmpty($text) -or $maxWidth -le 0) { return @("") }
        $lines = [System.Collections.Generic.List[string]]::new()
        $words = $text -split '\s+'
        $currentLine = [System.Text.StringBuilder]::new()
        foreach ($word in $words) {
            if ($currentLine.Length -eq 0) {
                [void]$currentLine.Append($word)
            } elseif (($currentLine.Length + 1 + $word.Length) -le $maxWidth) {
                [void]$currentLine.Append(' ').Append($word)
            } else {
                $lines.Add($currentLine.ToString()); $currentLine.Clear(); [void]$currentLine.Append($word)
            }
        }
        if ($currentLine.Length -gt 0) { $lines.Add($currentLine.ToString()) }
        return $lines.ToArray()
    }

    hidden [string] MoveCursor([int]$x, [int]$y) { return "`e[$($y + 1);$($x + 1)H" }
    hidden [string] SetColor([ConsoleColor]$color) {
        $colorMap = @{ Black=30;DarkRed=31;DarkGreen=32;DarkYellow=33;DarkBlue=34;DarkMagenta=35;DarkCyan=36;Gray=37;DarkGray=90;Red=91;Green=92;Yellow=93;Blue=94;Magenta=95;Cyan=96;White=97 }
        return "`e[$($colorMap[$color.ToString()])m"
    }
    hidden [string] ResetColor() { return "`e[0m" }
}
# AI: FIX - Removed '-Class' parameter. No functions are exported, so the entire statement can be removed.