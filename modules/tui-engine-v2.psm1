# TUI Engine v5.0 - PowerShell 7+ Edition
# Implements a modern, reliable TUI rendering and input loop.

#region Core TUI State
$script:TuiState = @{
    Running         = $false
    BufferWidth     = 0
    BufferHeight    = 0
    FrontBuffer     = $null
    BackBuffer      = $null
    ScreenStack     = [System.Collections.Stack]::new()
    CurrentScreen   = $null
    IsDirty         = $true
    RenderStats     = @{ LastFrameTime = 0; FrameCount = 0; TargetFPS = 60 }
    Components      = @()
    Layouts         = @{}
    FocusedComponent = $null
    InputQueue      = [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]::new()
    InputRunspace   = $null
    InputPowerShell = $null
    InputAsyncResult = $null
    CancellationTokenSource = $null
    EventHandlers   = @{}
}
#endregion

#region Engine Lifecycle & Main Loop

function Initialize-TuiEngine {
    param(
        [int]$Width = [Console]::WindowWidth,
        [int]$Height = [Console]::WindowHeight - 1
    )
    Write-Log -Level Info -Message "Initializing TUI Engine: ${Width}x${Height}"
    try {
        if ($Width -le 0 -or $Height -le 0) { throw "Invalid console dimensions: ${Width}x${Height}" }
        
        $script:TuiState.BufferWidth = $Width
        $script:TuiState.BufferHeight = $Height
        $script:TuiState.FrontBuffer = New-Object 'object[,]' $Height, $Width
        $script:TuiState.BackBuffer = New-Object 'object[,]' $Height, $Width
        
        for ($y = 0; $y -lt $Height; $y++) {
            for ($x = 0; $x -lt $Width; $x++) {
                $script:TuiState.FrontBuffer[$y, $x] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = [ConsoleColor]::Black }
                $script:TuiState.BackBuffer[$y, $x] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = [ConsoleColor]::Black }
            }
        }
        
        [Console]::CursorVisible = $false
        [Console]::Clear()
        
        try { Initialize-LayoutEngines; Write-Log -Level Debug -Message "Layout engines initialized" } catch { Write-Log -Level Error -Message "Layout engines init failed" -Data $_ }
        try { Initialize-ComponentSystem; Write-Log -Level Debug -Message "Component system initialized" } catch { Write-Log -Level Error -Message "Component system init failed" -Data $_ }
        
        $script:TuiState.EventHandlers = @{}
        [Console]::TreatControlCAsInput = $false
        
        Initialize-InputThread
        
        Publish-Event -EventName "System.EngineInitialized" -Data @{ Width = $Width; Height = $Height }
        $global:TuiState = $script:TuiState
        Write-Log -Level Info -Message "TUI Engine initialized successfully"
    }
    catch {
        Write-Host "FATAL: TUI Engine initialization failed. See error details below." -ForegroundColor Red
        $_.Exception | Format-List * -Force
        throw "TUI Engine initialization failed."
    }
}

function Initialize-InputThread {
    $script:TuiState.CancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
    $token = $script:TuiState.CancellationTokenSource.Token

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('InputQueue', $script:TuiState.InputQueue)
    $runspace.SessionStateProxy.SetVariable('token', $token)
    
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    
    $ps.AddScript({
        try {
            while (-not $token.IsCancellationRequested) {
                if ([Console]::KeyAvailable) {
                    if ($InputQueue.Count -lt 100) { $InputQueue.Enqueue([Console]::ReadKey($true)) }
                } else {
                    Start-Sleep -Milliseconds 20
                }
            }
        }
        catch [System.Management.Automation.PipelineStoppedException] { return }
        catch { Write-Warning "Input thread error: $_" }
    }) | Out-Null
    
    $script:TuiState.InputRunspace = $runspace
    $script:TuiState.InputPowerShell = $ps
    $script:TuiState.InputAsyncResult = $ps.BeginInvoke()
}

function Process-TuiInput {
    $processedAny = $false
    $keyInfo = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::None, $false, $false, $false)
    while ($script:TuiState.InputQueue.TryDequeue([ref]$keyInfo)) {
        $processedAny = $true
        try {
            Invoke-WithErrorHandling -Component "Engine.ProcessInput" -Context "Processing single key" -ScriptBlock { Process-SingleKeyInput -keyInfo $keyInfo }
        } catch {
            Write-Log -Level Error -Message "Error processing key input: $($_.Exception.Message)" -Data $_
            Request-TuiRefresh
        }
    }
    return $processedAny
}

function Process-SingleKeyInput {
    param($keyInfo)
    if ($keyInfo.Key -eq [ConsoleKey]::Tab) {
        Move-Focus -Reverse ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift)
        return
    }
    
    if (Handle-DialogInput -Key $keyInfo) { return }
    
    $focusedComponent = Get-FocusedComponent
    if ($focusedComponent -and $focusedComponent.HandleInput) {
        try { if (& $focusedComponent.HandleInput -self $focusedComponent -Key $keyInfo) { return } } catch { Write-Warning "Component input handler error: $_" }
    }
    
    $currentScreen = $script:TuiState.CurrentScreen
    if ($currentScreen -and $currentScreen.HandleInput) {
        try {
            $result = & $currentScreen.HandleInput -self $currentScreen -Key $keyInfo
            switch ($result) {
                "Back" { Pop-Screen }
                "Quit" { Stop-TuiEngine }
            }
        } catch { Write-Warning "Screen input handler error: $_" }
    }
}

function Start-TuiLoop {
    param([hashtable]$InitialScreen)
    try {
        if (-not $script:TuiState.BufferWidth) { Initialize-TuiEngine }
        if ($InitialScreen) { Push-Screen -Screen $InitialScreen }
        if (-not $script:TuiState.CurrentScreen) { throw "No screen available. Push a screen before calling Start-TuiLoop." }

        $script:TuiState.Running = $true
        $frameTime = [System.Diagnostics.Stopwatch]::new()
        $targetFrameTime = 1000.0 / $script:TuiState.RenderStats.TargetFPS
        
        while ($script:TuiState.Running) {
            try {
                $frameTime.Restart()
                $hadInput = Process-TuiInput
                try { Update-DialogSystem } catch {}
                if ($script:TuiState.IsDirty -or $hadInput) { Render-Frame; $script:TuiState.IsDirty = $false }
                $elapsed = $frameTime.ElapsedMilliseconds
                if ($elapsed -lt $targetFrameTime) { Start-Sleep -Milliseconds ([Math]::Max(1, $targetFrameTime - $elapsed)) }
            }
            catch [Helios.HeliosException] {
                Write-Log -Level Error -Message "A TUI Exception occurred: $($_.Exception.Message)" -Data $_.Exception.Context
                Show-AlertDialog -Title "Application Error" -Message "An operation failed: $($_.Exception.Message)"
                $script:TuiState.IsDirty = $true
            }
            catch {
                Write-Log -Level Error -Message "A FATAL, unhandled exception occurred: $($_.Exception.Message)" -Data $_
                Show-AlertDialog -Title "Fatal Error" -Message "A critical error occurred. The application will now close."
                $script:TuiState.Running = $false
            }
        }
    }
    finally { Cleanup-TuiEngine }
}

function Render-Frame {
    try {
        Clear-BackBuffer -BackgroundColor (Get-ThemeColor "Background")
        
        $renderQueue = [System.Collections.Generic.List[object]]::new()
        $collectComponents = {
            param($component)
            if (-not $component -or $component.Visible -eq $false) { return }
            $renderQueue.Add($component)
            if ($component.PSObject.Properties.Name -contains 'Children' -and $component.Children.Count -gt 0) {
                if ($component.PSObject.Properties.Name -contains 'CalculateLayout') {
                    try { & $component.CalculateLayout -self $component } catch { Write-Log -Level Error -Message "Layout failed for '$($component.Name)'" }
                }
                foreach ($child in $component.Children) { & $script:collectComponents $child }
            }
        }
        if ($script:TuiState.CurrentScreen) { & $collectComponents -component $script:TuiState.CurrentScreen }
        if ($dialog = Get-CurrentDialog) { & $collectComponents -component $dialog }

        $sortedQueue = $renderQueue | Sort-Object { $_.ZIndex ?? 0 }

        foreach ($component in $sortedQueue) {
            if (-not ($component.PSObject.Properties.Name -contains 'Render')) { continue }
            if ($component -is [UIElement]) {
                $componentOutput = $component.Render()
                if (-not [string]::IsNullOrEmpty($componentOutput)) { [Console]::Write($componentOutput) }
            } else {
                Invoke-WithErrorHandling -Component ($component.Name ?? $component.Type) -Context "Functional Render" -ScriptBlock { & $component.Render -self $component }
            }
        }
        
        Render-BufferOptimized
        [Console]::SetCursorPosition($script:TuiState.BufferWidth - 1, $script:TuiState.BufferHeight - 1)
    } catch { Write-Warning "Fatal Frame render error: $_" }
}

function Request-TuiRefresh { $script:TuiState.IsDirty = $true }

function Cleanup-TuiEngine {
    try {
        $script:TuiState.CancellationTokenSource?.Cancel()
        $script:TuiState.InputPowerShell?.EndInvoke($script:TuiState.InputAsyncResult)
        $script:TuiState.InputPowerShell?.Dispose()
        $script:TuiState.InputRunspace?.Dispose()
        $script:TuiState.CancellationTokenSource?.Dispose()
        
        Stop-AllTuiAsyncJobs
        
        foreach ($handlerId in $script:TuiState.EventHandlers.Values) { try { Unsubscribe-Event -HandlerId $handlerId } catch {} }
        $script:TuiState.EventHandlers.Clear()
        
        if ($Host.Name -ne 'Visual Studio Code Host') {
            [Console]::Write("`e[0m"); [Console]::CursorVisible = $true; [Console]::Clear(); [Console]::ResetColor()
        }
    } catch { Write-Warning "A secondary error occurred during TUI cleanup: $_" }
}
#endregion

#region Screen Management
function Push-Screen {
    param([hashtable]$Screen)
    if (-not $Screen) { return }
    Write-Log -Level Debug -Message "Pushing screen: $($Screen.Name)"
    try {
        $script:TuiState.FocusedComponent?.OnBlur?.Invoke()
        if ($script:TuiState.CurrentScreen) {
            $script:TuiState.CurrentScreen.OnExit?.Invoke()
            $script:TuiState.ScreenStack.Push($script:TuiState.CurrentScreen)
        }
        $script:TuiState.CurrentScreen = $Screen
        $script:TuiState.FocusedComponent = $null
        
        if ($Screen.Init) { 
            Invoke-WithErrorHandling -Component "$($Screen.Name).Init" -Context "Screen initialization" -ScriptBlock { 
                $services = $Screen._services ?? $global:Services
                & $Screen.Init -self $Screen -services $services
            }
        }
        Request-TuiRefresh
        Publish-Event -EventName "Screen.Pushed" -Data @{ ScreenName = $Screen.Name }
    } catch { Write-Warning "Push screen error: $_" }
}

function Pop-Screen {
    if ($script:TuiState.ScreenStack.Count -eq 0) { return $false }
    Write-Log -Level Debug -Message "Popping screen"
    try {
        $script:TuiState.FocusedComponent?.OnBlur?.Invoke()
        $screenToExit = $script:TuiState.CurrentScreen
        $script:TuiState.CurrentScreen = $script:TuiState.ScreenStack.Pop()
        $script:TuiState.FocusedComponent = $null
        
        $screenToExit?.OnExit?.Invoke()
        $script:TuiState.CurrentScreen?.OnResume?.Invoke()
        if ($script:TuiState.CurrentScreen.LastFocusedComponent) { Set-ComponentFocus -Component $script:TuiState.CurrentScreen.LastFocusedComponent }
        
        Request-TuiRefresh
        Publish-Event -EventName "Screen.Popped" -Data @{ ScreenName = $script:TuiState.CurrentScreen.Name }
        return $true
    } catch { Write-Warning "Pop screen error: $_"; return $false }
}
#endregion

#region Buffer and Rendering
function Clear-BackBuffer {
    param([ConsoleColor]$BackgroundColor = [ConsoleColor]::Black)
    for ($y = 0; $y -lt $script:TuiState.BufferHeight; $y++) {
        for ($x = 0; $x -lt $script:TuiState.BufferWidth; $x++) {
            $script:TuiState.BackBuffer[$y, $x] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = $BackgroundColor }
        }
    }
}

function Write-BufferString {
    param([int]$X, [int]$Y, [string]$Text, [ConsoleColor]$ForegroundColor = [ConsoleColor]::White, [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black)
    if ($Y -lt 0 -or $Y -ge $script:TuiState.BufferHeight -or [string]::IsNullOrEmpty($Text)) { return }
    $currentX = $X
    foreach ($char in $Text.ToCharArray()) {
        if ($currentX -ge $script:TuiState.BufferWidth) { break }
        if ($currentX -ge 0) { $script:TuiState.BackBuffer[$Y, $currentX] = @{ Char = $char; FG = $ForegroundColor; BG = $BackgroundColor } }
        $currentX++
    }
}

function Write-BufferBox {
    param([int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$BorderStyle = "Single", [ConsoleColor]$BorderColor = [ConsoleColor]::White, [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black, [string]$Title = "")
    $borders = Get-BorderChars -Style $BorderStyle
    Write-BufferString -X $X -Y $Y -Text "$($borders.TopLeft)$($borders.Horizontal * ($Width - 2))$($borders.TopRight)" -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    if ($Title) {
        $titleText = " $Title "; if ($titleText.Length -gt ($Width-2)) { $titleText = " $($Title.Substring(0,[Math]::Max(0,$Width-5)))... " }
        Write-BufferString -X ($X + [Math]::Floor(($Width - $titleText.Length) / 2)) -Y $Y -Text $titleText -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    for ($i = 1; $i -lt ($Height - 1); $i++) {
        Write-BufferString -X $X -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        Write-BufferString -X ($X + 1) -Y ($Y + $i) -Text (' ' * ($Width - 2)) -BackgroundColor $BackgroundColor
        Write-BufferString -X ($X + $Width - 1) -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    Write-BufferString -X $X -Y ($Y + $Height - 1) -Text "$($borders.BottomLeft)$($borders.Horizontal * ($Width - 2))$($borders.BottomRight)" -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
}

function Render-BufferOptimized {
    $outputBuilder = [System.Text.StringBuilder]::new(20000); $lastFG = -1; $lastBG = -1
    $forceFullRender = $script:TuiState.RenderStats.FrameCount -eq 0
    try {
        for ($y = 0; $y -lt $script:TuiState.BufferHeight; $y++) {
            $outputBuilder.Append("`e[$($y + 1);1H") | Out-Null
            for ($x = 0; $x -lt $script:TuiState.BufferWidth; $x++) {
                $backCell = $script:TuiState.BackBuffer[$y, $x]; $frontCell = $script:TuiState.FrontBuffer[$y, $x]
                if (-not $forceFullRender -and $backCell.Char -eq $frontCell.Char -and $backCell.FG -eq $frontCell.FG -and $backCell.BG -eq $frontCell.BG) { continue }
                if ($x -gt 0 -and $outputBuilder.Length -gt 0) { $outputBuilder.Append("`e[$($y + 1);$($x + 1)H") | Out-Null }
                if ($backCell.FG -ne $lastFG -or $backCell.BG -ne $lastBG) {
                    $fgCode = Get-AnsiColorCode $backCell.FG; $bgCode = Get-AnsiColorCode $backCell.BG -IsBackground $true
                    $outputBuilder.Append("`e[${fgCode};${bgCode}m") | Out-Null; $lastFG = $backCell.FG; $lastBG = $backCell.BG
                }
                $outputBuilder.Append($backCell.Char) | Out-Null
                $script:TuiState.FrontBuffer[$y, $x] = @{ Char = $backCell.Char; FG = $backCell.FG; BG = $backCell.BG }
            }
        }
        $outputBuilder.Append("`e[0m") | Out-Null
        if ($outputBuilder.Length -gt 0) { [Console]::Write($outputBuilder.ToString()) }
    } catch { Write-Warning "Render error: $_" }
}
#endregion

#region Component System
function Initialize-ComponentSystem { $script:TuiState.Components = @(); $script:TuiState.FocusedComponent = $null }
function Register-Component { param([hashtable]$Component); $script:TuiState.Components += $Component; if ($Component.Init) { try { & $Component.Init -self $Component } catch { Write-Warning "Component init error: $_" } }; return $Component }
function Set-ComponentFocus { param([hashtable]$Component); if ($Component -and ($Component.IsEnabled -eq $false -or $Component.Disabled -eq $true)) { return }; $script:TuiState.FocusedComponent?.OnBlur?.Invoke(); if ($script:TuiState.CurrentScreen) { $script:TuiState.CurrentScreen.LastFocusedComponent = $Component }; $script:TuiState.FocusedComponent = $Component; $Component?.OnFocus?.Invoke(); Request-TuiRefresh }
function Clear-ComponentFocus { $script:TuiState.FocusedComponent?.OnBlur?.Invoke(); $script:TuiState.FocusedComponent = $null; if ($script:TuiState.CurrentScreen) { $script:TuiState.CurrentScreen.LastFocusedComponent = $null }; Request-TuiRefresh }
function Get-NextFocusableComponent { param([hashtable]$CurrentComponent, [bool]$Reverse = $false); if (-not $script:TuiState.CurrentScreen) { return $null }; $focusableComponents = @(); function Find-Focusable([hashtable]$Comp) { if ($Comp.IsFocusable -eq $true -and $Comp.Visible -ne $false) { $focusableComponents += $Comp }; if ($Comp.Children) { foreach ($c in $Comp.Children) { Find-Focusable $c } } }; if ($script:TuiState.CurrentScreen.Components) { foreach ($c in $script:TuiState.CurrentScreen.Components.Values) { Find-Focusable $c } }; if ($focusableComponents.Count -eq 0) { return $null }; $sorted = $focusableComponents | Sort-Object { $_.TabIndex ?? ($_.Y * 1000 + $_.X) }; if ($Reverse) { [Array]::Reverse($sorted) }; $currentIndex = [array]::IndexOf($sorted, $CurrentComponent); if ($currentIndex -ge 0) { return $sorted[($currentIndex + 1) % $sorted.Count] } else { return $sorted[0] } }
function Handle-TabNavigation { param([bool]$Reverse = $false); $next = Get-NextFocusableComponent -CurrentComponent $script:TuiState.FocusedComponent -Reverse $Reverse; if ($next) { Set-ComponentFocus -Component $next } }

# AI: FIX - Added missing helper functions
function Get-FocusedComponent { return $script:TuiState.FocusedComponent }

function Move-Focus { 
    param([bool]$Reverse = $false)
    Handle-TabNavigation -Reverse $Reverse
}

function Get-CurrentDialog {
    # Check if dialog system module is loaded and retrieve current dialog
    if (Get-Module -Name 'dialog-system') {
        $dialogModule = Get-Module -Name 'dialog-system'
        $dialogState = & $dialogModule { $script:DialogState }
        return $dialogState.CurrentDialog
    }
    return $null
}

function Stop-AllTuiAsyncJobs {
    # AI: Placeholder for async job cleanup - currently no async jobs in the system
    Write-Log -Level Debug -Message "Stopping all TUI async jobs (none currently active)"
}
#endregion

#region Layout Management & Utilities
function Initialize-LayoutEngines { $script:TuiState.Layouts = @{} }
function Get-BorderChars { param([string]$Style); $styles = @{ Single=@{TopLeft='┌';TopRight='┐';BottomLeft='└';BottomRight='┘';Horizontal='─';Vertical='│'}; Double=@{TopLeft='╔';TopRight='╗';BottomLeft='╚';BottomRight='╝';Horizontal='═';Vertical='║'}; Rounded=@{TopLeft='╭';TopRight='╮';BottomLeft='╰';BottomRight='╯';Horizontal='─';Vertical='│'} }; return $styles[$Style] ?? $styles.Single }
function Get-AnsiColorCode { param([ConsoleColor]$Color, [bool]$IsBackground); $map = @{ Black=30;DarkBlue=34;DarkGreen=32;DarkCyan=36;DarkRed=31;DarkMagenta=35;DarkYellow=33;Gray=37;DarkGray=90;Blue=94;Green=92;Cyan=96;Red=91;Magenta=95;Yellow=93;White=97 }; $code = $map[$Color.ToString()]; return $IsBackground ? $code + 10 : $code }
function Get-WordWrappedLines { param([string]$Text, [int]$MaxWidth); if ([string]::IsNullOrEmpty($Text) -or $MaxWidth -le 0) { return @() }; $lines = @(); $words = $Text -split '\s+'; $sb = [System.Text.StringBuilder]::new(); foreach ($word in $words) { if ($sb.Length -eq 0) { [void]$sb.Append($word) } elseif (($sb.Length + 1 + $word.Length) -le $MaxWidth) { [void]$sb.Append(' ').Append($word) } else { $lines += $sb.ToString(); [void]$sb.Clear().Append($word) } }; if ($sb.Length -gt 0) { $lines += $sb.ToString() }; return $lines }
function Stop-TuiEngine { Write-Log -Level Info -Message "Stop-TuiEngine called"; $script:TuiState.Running = $false; $script:TuiState.CancellationTokenSource?.Cancel(); Publish-Event -EventName "System.Shutdown" }
#endregion

Export-ModuleMember -Function 'Initialize-TuiEngine', 'Start-TuiLoop', 'Stop-TuiEngine', 'Push-Screen', 'Pop-Screen', 'Request-TuiRefresh', 'Write-BufferString', 'Write-BufferBox', 'Clear-BackBuffer', 'Get-BorderChars', 'Register-Component', 'Set-ComponentFocus', 'Clear-ComponentFocus', 'Get-NextFocusableComponent', 'Handle-TabNavigation', 'Get-WordWrappedLines' -Variable 'TuiState'