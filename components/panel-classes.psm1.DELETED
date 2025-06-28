# (Keep all other functions in tui-engine-v2.psm1 the same)

# ==============================================================================
# === FINAL, UNIFIED RENDER-FRAME IMPLEMENTATION ===============================
# ==============================================================================
function Render-Frame {
    try {
        # --- 1. Preparation ---
        $bgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
        Clear-BackBuffer -BackgroundColor $bgColor
        
        # --- 2. Component Collection ---
        $renderQueue = [System.Collections.Generic.List[object]]::new()
        $script:collectComponents = {
            param($component)
            if (-not $component -or -not $component.Visible) { return }
            
            $renderQueue.Add($component)
            
            if ($component.Children -and $component.Children.Count -gt 0) {
                if ($component.CalculateLayout) {
                    try { & $component.CalculateLayout -self $component } catch { Write-Log -Level Error -Message "Layout failed for '$($component.Name)'" -Data $_ }
                }
                foreach ($child in $component.Children) { & $script:collectComponents $child }
            }
        }

        # Start collection from the active screen and any dialogs
        if ($script:TuiState.CurrentScreen) { & $script:collectComponents -component $script:TuiState.CurrentScreen }
        if ((Get-Command -Name "Get-CurrentDialog" -ErrorAction SilentlyContinue) -and ($dialog = Get-CurrentDialog)) {
             & $script:collectComponents -component $dialog
        }

        # --- 3. Sorting ---
        # Sort by Z-Index to ensure proper layering (e.g., dialogs on top).
        $sortedQueue = $renderQueue | Sort-Object { $_.ZIndex ?? 0 }

        # --- 4. The Unified Rendering Loop ---
        foreach ($component in $sortedQueue) {
            if (-not $component.Render) { continue }
            
            # This is the core architectural decision point.
            if ($component -is [UIElement]) {
                # PATTERN A: Class-Based Component (returns a string)
                # The engine is responsible for placing the component's output.
                $componentOutput = $component.Render() # This calls the safe base Render()
                if (-not [string]::IsNullOrEmpty($componentOutput)) {
                    $lines = $componentOutput.Split([Environment]::NewLine)
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        Write-BufferString -X $component.X -Y ($component.Y + $i) -Text $lines[$i]
                    }
                }
            } else {
                # PATTERN B: Functional Component (calls Write-BufferString itself)
                # We simply invoke its Render method and let it draw itself.
                Invoke-WithErrorHandling -Component "$($component.Name ?? $component.Type).Render" -Context "Functional Render" -ScriptBlock {
                    & $component.Render -self $component
                }
            }
        }
        
        # --- 5. Final Draw ---
        Render-BufferOptimized
        [Console]::SetCursorPosition($script:TuiState.BufferWidth - 1, $script:TuiState.BufferHeight - 1)

    } catch {
        Write-Warning "Fatal Frame render error: $_"
    }
}

# (Keep all other functions in tui-engine-v2.psm1 the same)