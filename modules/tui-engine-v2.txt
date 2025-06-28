# Rock-Solid TUI Engine v4.0 - Performance & Reliability Edition
# Implements all critical fixes from code review

#region Core TUI State
$script:TuiState = @{
    Running         = $false
    BufferWidth     = 0
    BufferHeight    = 0
    FrontBuffer     = $null
    BackBuffer      = $null
    ScreenStack     = New-Object System.Collections.Stack
    CurrentScreen   = $null
    IsDirty         = $true
    LastActivity    = [DateTime]::Now
    LastRenderTime  = [DateTime]::MinValue
    RenderStats     = @{ LastFrameTime = 0; FrameCount = 0; TotalTime = 0; TargetFPS = 60 }
    Components      = @()
    Layouts         = @{}
    DebugOverlayEnabled = $false
    FocusedComponent = $null
    
    InputQueue = $null
    InputRunspace = $null
    InputPowerShell = $null
    InputAsyncResult = $null
    
    CancellationTokenSource = $null
    
    EventHandlers = @{}
}

$script:CellPool = @{
    Pool = New-Object System.Collections.Queue
    MaxSize = 1000
}
#endregion

#region Cell Management & Object Pooling

function Get-PooledCell {
    param(
        [char]$Char = ' ',
        [ConsoleColor]$FG = [ConsoleColor]::White,
        [ConsoleColor]$BG = [ConsoleColor]::Black
    )
    
    if ($script:CellPool.Pool.Count -gt 0) {
        $cell = $script:CellPool.Pool.Dequeue()
        $cell.Char = $Char
        $cell.FG = $FG
        $cell.BG = $BG
        return $cell
    }
    
    return @{
        Char = $Char
        FG = $FG
        BG = $BG
    }
}

function Return-CellToPool {
    param($Cell)
    if ($script:CellPool.Pool.Count -lt $script:CellPool.MaxSize) {
        $script:CellPool.Pool.Enqueue($Cell)
    }
}

#endregion

#region Engine Lifecycle & Main Loop

function global:Initialize-TuiEngine {
    param(
        [int]$Width = [Console]::WindowWidth,
        [int]$Height = [Console]::WindowHeight - 1
    )

    if (-not $Width) { $Width = [Console]::WindowWidth }
    if (-not $Height) { $Height = [Console]::WindowHeight - 1 }
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Info -Message "Initializing TUI Engine: ${Width}x${Height}"
    }
    
    try {
        if ($Width -le 0 -or $Height -le 0) { throw "Invalid console dimensions: ${Width}x${Height}" }
        
        $script:TuiState.BufferWidth = $Width
        $script:TuiState.BufferHeight = $Height
        
        $script:TuiState.FrontBuffer = New-Object 'object[,]' $Height, $Width
        $script:TuiState.BackBuffer = New-Object 'object[,]' $Height, $Width
        
        $emptyCell = @{ Char = ' '; FG = [ConsoleColor]::White; BG = [ConsoleColor]::Black }
        for ($y = 0; $y -lt $Height; $y++) {
            for ($x = 0; $x -lt $Width; $x++) {
                $script:TuiState.FrontBuffer[$y, $x] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = [ConsoleColor]::Black }
                $script:TuiState.BackBuffer[$y, $x] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = [ConsoleColor]::Black }
            }
        }
        
        [Console]::CursorVisible = $false
        [Console]::Clear()
        
        try { 
            Initialize-LayoutEngines 
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log -Level Debug -Message "Layout engines initialized"
            }
        } catch { 
            Write-Warning "Layout engines init failed: $_" 
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log -Level Error -Message "Layout engines init failed" -Data $_
            }
        }
        try { 
            Initialize-ComponentSystem 
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log -Level Debug -Message "Component system initialized"
            }
        } catch { 
            Write-Warning "Component system init failed: $_" 
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log -Level Error -Message "Component system init failed" -Data $_
            }
        }
        
        $script:TuiState.EventHandlers = @{}
        
        try {
            [Console]::TreatControlCAsInput = $false
        } catch {
            Write-Warning "Could not set console input mode: $_"
        }
        
        Initialize-InputThread
        
        Safe-PublishEvent -EventName "System.EngineInitialized" -Data @{ Width = $Width; Height = $Height }
        
        $global:TuiState = $script:TuiState
        
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level Info -Message "TUI Engine initialized successfully"
        }
    }
    catch {
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        Write-Host "IMMEDIATE, ORIGINAL ERROR DETECTED DURING INITIALIZATION" -ForegroundColor Red
        Write-Host "THE *REAL* PROBLEM IS LIKELY THIS:" -ForegroundColor Yellow
        
        if ($_) {
            Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor White
            
            Write-Host "FULL ERROR:" -ForegroundColor Yellow
            if ($_.Exception) {
                $_.Exception | Format-List * -Force
            } else {
                Write-Host "Error details: $_" -ForegroundColor White
            }
        } else {
            Write-Host "Unknown error occurred" -ForegroundColor White
        }
        
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        
        throw "FATAL: TUI Engine initialization failed. See original error details above."
    }
}

function Initialize-InputThread {
    try {
        $queueType = [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]
        $script:TuiState.InputQueue = New-Object $queueType
    } catch {
        Write-Warning "Failed to create ConcurrentQueue, falling back to ArrayList"
        $script:TuiState.InputQueue = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    }
    
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
                    $keyInfo = [Console]::ReadKey($true)
                    
                    if ($InputQueue -is [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]) {
                        if ($InputQueue.Count -lt 100) {
                            $InputQueue.Enqueue($keyInfo)
                        }
                    } elseif ($InputQueue -is [System.Collections.ArrayList]) {
                        if ($InputQueue.Count -lt 100) {
                            $InputQueue.Add($keyInfo) | Out-Null
                        }
                    }
                }
                else {
                    Start-Sleep -Milliseconds 20
                }
            }
        }
        catch [System.Management.Automation.PipelineStoppedException] {
            return
        }
        catch {
            Write-Warning "Input thread error: $_"
        }
    }) | Out-Null
    
    $script:TuiState.InputRunspace   = $runspace
    $script:TuiState.InputPowerShell = $ps
    $script:TuiState.InputAsyncResult = $ps.BeginInvoke()
}

function Process-TuiInput {
    $processedAny = $false
    if (-not $script:TuiState.InputQueue) { return $false }
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Verbose -Message "Processing input queue"
    }

    $keyInfo = $null
    
    if ($script:TuiState.InputQueue -is [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]) {
        $keyInfo = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::None, $false, $false, $false)
        while ($script:TuiState.InputQueue.TryDequeue([ref]$keyInfo)) {
            $processedAny = $true
            $script:TuiState.LastActivity = [DateTime]::Now
            try {
                Invoke-WithErrorHandling -Component "Engine.ProcessInput" -Context "Processing single key input" -ScriptBlock {
                    Process-SingleKeyInput -keyInfo $keyInfo
                } -AdditionalData @{ KeyInfo = $keyInfo }
            } catch {
                Write-Log -Level Error -Message "Error processing single key input: $($_.Exception.Message)" -Data $_
                Request-TuiRefresh
            }
        }
    } elseif ($script:TuiState.InputQueue -is [System.Collections.ArrayList]) {
        while ($script:TuiState.InputQueue.Count -gt 0) {
            try {
                $keyInfo = $script:TuiState.InputQueue[0]
                $script:TuiState.InputQueue.RemoveAt(0)
                $processedAny = $true
                $script:TuiState.LastActivity = [DateTime]::Now
                try {
                    Invoke-WithErrorHandling -Component "Engine.ProcessInput" -Context "Processing single key input" -ScriptBlock {
                        Process-SingleKeyInput -keyInfo $keyInfo
                    } -AdditionalData @{ KeyInfo = $keyInfo }
                } catch {
                    Write-Log -Level Error -Message "Error processing single key input: $($_.Exception.Message)" -Data $_
                    Request-TuiRefresh
                }
            } catch {
                break
            }
        }
    }
    
    return $processedAny
}

function Process-SingleKeyInput {
    param($keyInfo)
    
    try {
        if ($keyInfo.Key -eq [ConsoleKey]::Tab) {
            if (Get-Command -Name "Move-Focus" -ErrorAction SilentlyContinue) {
                Move-Focus -Reverse ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift)
            } else {
                Handle-TabNavigation -Reverse ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift)
            }
            return
        }
        
        if ((Get-Command -Name "Handle-DialogInput" -ErrorAction SilentlyContinue) -and (Handle-DialogInput -Key $keyInfo)) {
            return
        }
        
        $focusedComponent = if (Get-Command -Name "Get-FocusedComponent" -ErrorAction SilentlyContinue) {
            Get-FocusedComponent
        } else {
            $script:TuiState.FocusedComponent
        }
        
        if ($focusedComponent -and $focusedComponent.HandleInput) {
            try {
                if (& $focusedComponent.HandleInput -self $focusedComponent -Key $keyInfo) {
                    return
                }
            } catch {
                Write-Warning "Component input handler error: $_"
            }
        }
        
        $currentScreen = $script:TuiState.CurrentScreen
        if ($currentScreen -and $currentScreen.HandleInput) {
            try {
                $result = & $currentScreen.HandleInput -self $currentScreen -Key $keyInfo
                switch ($result) {
                    "Back" { Pop-Screen }
                    "Quit" { 
                        $script:TuiState.Running = $false
                        if ($script:TuiState.CancellationTokenSource) {
                            $script:TuiState.CancellationTokenSource.Cancel()
                        }
                    }
                }
            } catch {
                Write-Warning "Screen input handler error: $_"
            }
        }
    } catch {
        Write-Warning "Input processing error: $_"
    }
}

function global:Start-TuiLoop {
    param([hashtable]$InitialScreen = $null)

    try {
        if (-not $script:TuiState.BufferWidth -or $script:TuiState.BufferWidth -eq 0) {
            Initialize-TuiEngine
        }
        
        if ($InitialScreen) {
            Push-Screen -Screen $InitialScreen
        }
        
        if (-not $script:TuiState.CurrentScreen -and $script:TuiState.ScreenStack.Count -eq 0) {
            throw "No screen available to display. Push a screen before calling Start-TuiLoop or provide an InitialScreen parameter."
        }

        $script:TuiState.Running = $true
        $frameTime = New-Object System.Diagnostics.Stopwatch
        $targetFrameTime = 1000.0 / $script:TuiState.RenderStats.TargetFPS
        
        while ($script:TuiState.Running) {
            try {
                $frameTime.Restart()

                $hadInput = Process-TuiInput
                
                if (Get-Command -Name "Update-DialogSystem" -ErrorAction SilentlyContinue) { 
                    try { Update-DialogSystem } catch { Write-Log -Level Warning -Message "Dialog update error: $_" }
                }

                if ($script:TuiState.IsDirty -or $hadInput) {
                    Render-Frame
                    $script:TuiState.IsDirty = $false
                }
                
                $elapsed = $frameTime.ElapsedMilliseconds
                if ($elapsed -lt $targetFrameTime) {
                    $sleepTime = [Math]::Max(1, $targetFrameTime - $elapsed)
                    Start-Sleep -Milliseconds $sleepTime
                }
            }
            catch [Helios.HeliosException] {
                $exception = $_.Exception
                Write-Log -Level Error -Message "A TUI Exception occurred: $($exception.Message)" -Data $exception.Context
                Show-AlertDialog -Title "Application Error" -Message "An operation failed: $($exception.Message)"
                $script:TuiState.IsDirty = $true
            }
            catch {
                $exception = $_.Exception
                Write-Log -Level Error -Message "A FATAL, unhandled exception occurred: $($exception.Message)" -Data $_
                Show-AlertDialog -Title "Fatal Error" -Message "A critical error occurred. The application will now close."
                $script:TuiState.Running = $false
            }
        }
    }
    finally {
        Cleanup-TuiEngine
    }
}

# AI: FIX - This is the consolidated, correct Render-Frame function.
function Render-Frame {
    try {
        # --- 1. Preparation ---
        $bgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
        Clear-BackBuffer -BackgroundColor $bgColor
        
        # --- 2. Component Collection ---
        $renderQueue = [System.Collections.Generic.List[object]]::new()
        $script:collectComponents = {
            param($component)
            if (-not $component -or $component.Visible -eq $false) { return }
            
            $renderQueue.Add($component)
            
            # AI: FIX - Check for a 'Children' property, which is the standard for class-based components.
            if ($component.PSObject.Properties.Name -contains 'Children' -and $component.Children -and $component.Children.Count -gt 0) {
                if ($component.PSObject.Properties.Name -contains 'CalculateLayout') {
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
            if (-not $component.PSObject.Properties.Name -contains 'Render') { continue }
            
            if ($component -is [UIElement]) {
                # PATTERN A: Class-Based Component (returns a string with ANSI codes for positioning)
                $componentOutput = $component.Render() # This calls the safe base Render()
                if (-not [string]::IsNullOrEmpty($componentOutput)) {
                    # The component's Render() method is now responsible for generating the full ANSI string,
                    # including cursor positioning. The engine just writes it.
                    [Console]::Write($componentOutput)
                }
            } else {
                # PATTERN B: Functional Component (calls Write-BufferString itself)
                Invoke-WithErrorHandling -Component "$($component.Name ?? $component.Type).Render" -Context "Functional Render" -ScriptBlock {
                    & $component.Render -self $component
                }
            }
        }
        
        # --- 5. Final Draw ---
        # AI: FIX - The functional components have drawn to the backbuffer. Now we flush it.
        # The class-based components have written directly to the console.
        # This is a temporary hybrid solution. Long-term, all components should draw to the backbuffer.
        Render-BufferOptimized
        [Console]::SetCursorPosition($script:TuiState.BufferWidth - 1, $script:TuiState.BufferHeight - 1)

    } catch {
        Write-Warning "Fatal Frame render error: $_"
    }
}

function global:Request-TuiRefresh {
    $script:TuiState.IsDirty = $true
}

function Cleanup-TuiEngine {
    try {
        if ($script:TuiState.CancellationTokenSource) {
            try {
                if (-not $script:TuiState.CancellationTokenSource.IsCancellationRequested) {
                    $script:TuiState.CancellationTokenSource.Cancel()
                }
            } catch { }
        }

        if ($script:TuiState.InputPowerShell) {
            if ($script:TuiState.InputAsyncResult) {
                try { $script:TuiState.InputPowerShell.EndInvoke($script:TuiState.InputAsyncResult) } catch { }
            }
            try { $script:TuiState.InputPowerShell.Dispose() } catch { }
        }
        
        if ($script:TuiState.InputRunspace) {
            try { $script:TuiState.InputRunspace.Dispose() } catch { }
        }
        
        if ($script:TuiState.CancellationTokenSource) {
            try { $script:TuiState.CancellationTokenSource.Dispose() } catch { }
        }

        if (Get-Command -Name "Stop-AllTuiAsyncJobs" -ErrorAction SilentlyContinue) {
            try { Stop-AllTuiAsyncJobs } catch { }
        }

        Cleanup-EventHandlers
        
        if (-not $env:CI -and -not $PSScriptRoot) {
            try {
                if ([System.Environment]::UserInteractive) {
                    [Console]::Write("$([char]27)[0m")
                    [Console]::CursorVisible = $true
                    [Console]::Clear()
                    [Console]::ResetColor()
                }
            } catch { }
        }
    } catch {
        Write-Warning "A secondary error occurred during TUI cleanup: $_"
    }
}

function Cleanup-EventHandlers {
    if (-not (Get-Command -Name "Unsubscribe-Event" -ErrorAction SilentlyContinue)) { return }
    if (-not $script:TuiState.EventHandlers) { return }

    foreach ($handlerId in $script:TuiState.EventHandlers.Values) {
        try { Unsubscribe-Event -HandlerId $handlerId } catch { }
    }
    $script:TuiState.EventHandlers.Clear()
    
    try {
        Get-EventSubscriber -SourceIdentifier "TuiCtrlC" -ErrorAction SilentlyContinue | Unregister-Event
    } catch { }
}

function Safe-PublishEvent {
    param($EventName, $Data)
    if (Get-Command -Name "Publish-Event" -ErrorAction SilentlyContinue) {
        try { Publish-Event -EventName $EventName -Data $Data } catch { }
    }
}

#endregion

#region Screen Management

function global:Push-Screen {
    param([hashtable]$Screen)
    if (-not $Screen) { return }
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Debug -Message "Pushing screen: $($Screen.Name)"
    }
    
    try {
        if ($script:TuiState.FocusedComponent -and $script:TuiState.FocusedComponent.OnBlur) {
            try {
                & $script:TuiState.FocusedComponent.OnBlur -self $script:TuiState.FocusedComponent
            } catch {
                Write-Log -Level Warning -Message "Error in OnBlur for component '$($script:TuiState.FocusedComponent.Name)'" -Data $_
            }
        }
        
        if ($script:TuiState.CurrentScreen) {
            if ($script:TuiState.CurrentScreen.OnExit) { 
                try {
                    Invoke-WithErrorHandling -Component "$($script:TuiState.CurrentScreen.Name).OnExit" -Context "Screen exit" -ScriptBlock {
                        & $script:TuiState.CurrentScreen.OnExit -self $script:TuiState.CurrentScreen
                    } -AdditionalData @{ ScreenName = $script:TuiState.CurrentScreen.Name }
                } catch {
                    Write-Warning "Screen exit error: $($_.Exception.Message)"
                }
            }
            $script:TuiState.ScreenStack.Push($script:TuiState.CurrentScreen)
        }
        
        $script:TuiState.CurrentScreen = $Screen
        $script:TuiState.FocusedComponent = $null
        
        if ($Screen.Init) { 
            try {
                Invoke-WithErrorHandling -Component "$($Screen.Name).Init" -Context "Screen initialization" -ScriptBlock {
                    $services = $null
                    if ($Screen._services) {
                        $services = $Screen._services
                    } elseif ($global:Services) {
                        $services = $global:Services
                    }
                    
                    if ($services) {
                        & $Screen.Init -self $Screen -services $services
                    } else {
                        & $Screen.Init -self $Screen
                    }
                } -AdditionalData @{ ScreenName = $Screen.Name }
            } catch {
                throw "Failed to initialize screen '$($Screen.Name)': $($_.Exception.Message)"
            }
        }
        
        Request-TuiRefresh
        Safe-PublishEvent -EventName "Screen.Pushed" -Data @{ ScreenName = $Screen.Name }
        
    } catch {
        Write-Warning "Push screen error: $_"
    }
}

function global:Pop-Screen {
    if ($script:TuiState.ScreenStack.Count -eq 0) { return $false }
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Debug -Message "Popping screen"
    }
    
    try {
        if ($script:TuiState.FocusedComponent -and $script:TuiState.FocusedComponent.OnBlur) {
            try {
                & $script:TuiState.FocusedComponent.OnBlur -self $script:TuiState.FocusedComponent
            } catch {
                Write-Warning "Component blur error: $_"
            }
        }
        
        $screenToExit = $script:TuiState.CurrentScreen
        
        $script:TuiState.CurrentScreen = $script:TuiState.ScreenStack.Pop()
        $script:TuiState.FocusedComponent = $null
        
        if ($screenToExit -and $screenToExit.OnExit) { 
            try {
                Invoke-WithErrorHandling -Component "$($screenToExit.Name).OnExit" -Context "Screen exit" -ScriptBlock {
                    & $screenToExit.OnExit -self $screenToExit
                } -AdditionalData @{ ScreenName = $screenToExit.Name }
            } catch {
                Write-Warning "Screen exit error: $($_.Exception.Message)"
            }
        }
        if ($script:TuiState.CurrentScreen -and $script:TuiState.CurrentScreen.OnResume) { 
            try {
                Invoke-WithErrorHandling -Component "$($script:TuiState.CurrentScreen.Name).OnResume" -Context "Screen resume" -ScriptBlock {
                    & $script:TuiState.CurrentScreen.OnResume -self $script:TuiState.CurrentScreen
                } -AdditionalData @{ ScreenName = $script:TuiState.CurrentScreen.Name }
            } catch {
                Write-Warning "Screen resume error: $($_.Exception.Message)"
            }
        }
        
        if ($script:TuiState.CurrentScreen.LastFocusedComponent) {
            Set-ComponentFocus -Component $script:TuiState.CurrentScreen.LastFocusedComponent
        }
        
        Request-TuiRefresh
        Safe-PublishEvent -EventName "Screen.Popped" -Data @{ ScreenName = $script:TuiState.CurrentScreen.Name }
        
        return $true
        
    } catch {
        Write-Warning "Pop screen error: $_"
        return $false
    }
}

#endregion

#region Buffer and Rendering

function global:Clear-BackBuffer {
    param([ConsoleColor]$BackgroundColor = [ConsoleColor]::Black)
    
    for ($y = 0; $y -lt $script:TuiState.BufferHeight; $y++) {
        for ($x = 0; $x -lt $script:TuiState.BufferWidth; $x++) {
            $script:TuiState.BackBuffer[$y, $x] = @{ 
                Char = ' '
                FG = [ConsoleColor]::White
                BG = $BackgroundColor 
            }
        }
    }
}

function global:Write-BufferString {
    param(
        [int]$X, 
        [int]$Y, 
        [string]$Text, 
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White, 
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
    )
    if ($Y -lt 0 -or $Y -ge $script:TuiState.BufferHeight) { return }
    if ([string]::IsNullOrEmpty($Text)) { return }
    
    $currentX = $X
    foreach ($char in $Text.ToCharArray()) {
        if ($currentX -ge $script:TuiState.BufferWidth) { break }

        if ($currentX -ge 0) {
            $script:TuiState.BackBuffer[$Y, $currentX] = @{ 
                Char = $char
                FG = $ForegroundColor
                BG = $BackgroundColor 
            }
        }
        
        if ($char -match '[\u1100-\u11FF\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]') {
            $currentX += 2
            if ($currentX -lt $script:TuiState.BufferWidth -and $currentX -gt 0) {
                $script:TuiState.BackBuffer[$Y, $currentX - 1] = @{ 
                    Char = ' '
                    FG = $ForegroundColor
                    BG = $BackgroundColor 
                }
            }
        } else {
            $currentX++
        }
    }
}

function global:Write-BufferBox {
    param(
        [int]$X, 
        [int]$Y, 
        [int]$Width, 
        [int]$Height, 
        [string]$BorderStyle = "Single", 
        [ConsoleColor]$BorderColor = [ConsoleColor]::White, 
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black, 
        [string]$Title = ""
    )
    $borders = Get-BorderChars -Style $BorderStyle
    
    Write-BufferString -X $X -Y $Y -Text "$($borders.TopLeft)$($borders.Horizontal * ($Width - 2))$($borders.TopRight)" -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    
    if ($Title) {
        $titleText = " $Title "
        if ($titleText.Length -gt ($Width - 2)) {
            $maxLength = [Math]::Max(0, $Width - 5)
            $titleText = " $($Title.Substring(0, $maxLength))... "
        }
        $titleX = $X + [Math]::Floor(($Width - $titleText.Length) / 2)
       Write-BufferString -X $titleX -Y $Y -Text $titleText -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    
    for ($i = 1; $i -lt ($Height - 1); $i++) {
        Write-BufferString -X $X -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        Write-BufferString -X ($X + 1) -Y ($Y + $i) -Text (' ' * ($Width - 2)) -BackgroundColor $BackgroundColor
        Write-BufferString -X ($X + $Width - 1) -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    
    Write-BufferString -X $X -Y ($Y + $Height - 1) -Text "$($borders.BottomLeft)$($borders.Horizontal * ($Width - 2))$($borders.BottomRight)" -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
}

function global:Render-BufferOptimized {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outputBuilder = New-Object System.Text.StringBuilder -ArgumentList 20000
    $lastFG = -1
    $lastBG = -1
    
    $forceFullRender = $script:TuiState.RenderStats.FrameCount -eq 0
    
    try {
        for ($y = 0; $y -lt $script:TuiState.BufferHeight; $y++) {
            $outputBuilder.Append("$([char]27)[$($y + 1);1H") | Out-Null
            
            for ($x = 0; $x -lt $script:TuiState.BufferWidth; $x++) {
                $backCell = $script:TuiState.BackBuffer[$y, $x]
                $frontCell = $script:TuiState.FrontBuffer[$y, $x]
                
                if (-not $forceFullRender -and
                    $backCell.Char -eq $frontCell.Char -and 
                    $backCell.FG -eq $frontCell.FG -and 
                    $backCell.BG -eq $frontCell.BG) {
                    continue
                }
                
                if ($x -gt 0 -and $outputBuilder.Length -gt 0) {
                    $outputBuilder.Append("$([char]27)[$($y + 1);$($x + 1)H") | Out-Null
                }
                
                if ($backCell.FG -ne $lastFG -or $backCell.BG -ne $lastBG) {
                    $fgCode = Get-AnsiColorCode $backCell.FG
                    $bgCode = Get-AnsiColorCode $backCell.BG -IsBackground $true
                    $outputBuilder.Append("$([char]27)[${fgCode};${bgCode}m") | Out-Null
                    $lastFG = $backCell.FG
                    $lastBG = $backCell.BG
                }
                
                $outputBuilder.Append($backCell.Char) | Out-Null
                
                $script:TuiState.FrontBuffer[$y, $x] = @{
                    Char = $backCell.Char
                    FG = $backCell.FG
                    BG = $backCell.BG
                }
            }
        }
        
        $outputBuilder.Append("$([char]27)[0m") | Out-Null
        
        if ($outputBuilder.Length -gt 0) {
            [Console]::Write($outputBuilder.ToString())
        }
        
    } catch {
        Write-Warning "Render error: $_"
    }
    
    $stopwatch.Stop()
    $script:TuiState.RenderStats.LastFrameTime = $stopwatch.ElapsedMilliseconds
    $script:TuiState.RenderStats.FrameCount++
    $script:TuiState.RenderStats.TotalTime += $stopwatch.ElapsedMilliseconds
}

#endregion

#region Component System

function Initialize-ComponentSystem {
    $script:TuiState.Components = @()
    $script:TuiState.FocusedComponent = $null
}

function global:Register-Component {
    param([hashtable]$Component)
    
    $script:TuiState.Components += $Component
    
    if ($Component.Init) {
        try {
            Invoke-WithErrorHandling -Component "$($Component.Name ?? $Component.Type).Init" -Context "Component initialization" -ScriptBlock {
                & $Component.Init -self $Component
            } -AdditionalData @{ ComponentType = $Component.Type; ComponentName = $Component.Name }
        } catch {
            Write-Warning "Component init error: $($_.Exception.Message)"
        }
    }
    
    return $Component
}

function global:Set-ComponentFocus {
    param([hashtable]$Component)
    
    if ($Component -and ($Component.IsEnabled -eq $false -or $Component.Disabled -eq $true)) {
        return
    }
    
    if ($script:TuiState.FocusedComponent -and $script:TuiState.FocusedComponent.OnBlur) {
        try {
            Invoke-WithErrorHandling -Component "$($script:TuiState.FocusedComponent.Name ?? $script:TuiState.FocusedComponent.Type).OnBlur" -Context "Component blur" -ScriptBlock {
                & $script:TuiState.FocusedComponent.OnBlur -self $script:TuiState.FocusedComponent
            } -AdditionalData @{ ComponentType = $script:TuiState.FocusedComponent.Type; ComponentName = $script:TuiState.FocusedComponent.Name }
        } catch {
            Write-Warning "Component blur error: $($_.Exception.Message)"
        }
    }
    
    if ($script:TuiState.CurrentScreen) {
        $script:TuiState.CurrentScreen.LastFocusedComponent = $Component
    }
    
    $script:TuiState.FocusedComponent = $Component
    if ($Component -and $Component.OnFocus) {
        try {
            Invoke-WithErrorHandling -Component "$($Component.Name ?? $Component.Type).OnFocus" -Context "Component focus" -ScriptBlock {
                & $Component.OnFocus -self $Component
            } -AdditionalData @{ ComponentType = $Component.Type; ComponentName = $Component.Name }
        } catch {
            Write-Warning "Component focus error: $($_.Exception.Message)"
        }
    }
    
    Request-TuiRefresh
}

function global:Clear-ComponentFocus {
    if ($script:TuiState.FocusedComponent -and $script:TuiState.FocusedComponent.OnBlur) {
        try {
            Invoke-WithErrorHandling -Component "$($script:TuiState.FocusedComponent.Name ?? $script:TuiState.FocusedComponent.Type).OnBlur" -Context "Component blur" -ScriptBlock {
                & $script:TuiState.FocusedComponent.OnBlur -self $script:TuiState.FocusedComponent
            } -AdditionalData @{ ComponentType = $script:TuiState.FocusedComponent.Type; ComponentName = $script:TuiState.FocusedComponent.Name }
        } catch {
            Write-Warning "Component blur error: $($_.Exception.Message)"
        }
    }
    
    $script:TuiState.FocusedComponent = $null
    
    if ($script:TuiState.CurrentScreen) {
        $script:TuiState.CurrentScreen.LastFocusedComponent = $null
    }
    
    Request-TuiRefresh
}

function global:Get-NextFocusableComponent {
    param(
        [hashtable]$CurrentComponent,
        [bool]$Reverse = $false
    )
    
    if (-not $script:TuiState.CurrentScreen) { return $null }
    
    $focusableComponents = @()
    
    function Find-FocusableComponents {
        param($Component)
        
        if ($Component.IsFocusable -eq $true -and 
            $Component.Visible -ne $false) {
            $focusableComponents += $Component
        }
        
        if ($Component.Children) {
            foreach ($child in $Component.Children) {
                Find-FocusableComponents -Component $child
            }
        }
    }
    
    if ($script:TuiState.CurrentScreen.Components) {
        if ($script:TuiState.CurrentScreen.Components -is [hashtable]) {
            foreach ($comp in $script:TuiState.CurrentScreen.Components.Values) {
                Find-FocusableComponents -Component $comp
            }
        } elseif ($script:TuiState.CurrentScreen.Components -is [array]) {
            foreach ($comp in $script:TuiState.CurrentScreen.Components) {
                Find-FocusableComponents -Component $comp
            }
        }
    }
    
    if ($focusableComponents.Count -eq 0) { return $null }
    
    $sorted = $focusableComponents | Sort-Object {
        if ($null -ne $_.TabIndex) { $_.TabIndex }
        else { $_.Y * 1000 + $_.X }
    }
    
    if ($Reverse) {
        [Array]::Reverse($sorted)
    }
    
    $currentIndex = -1
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i] -eq $CurrentComponent) {
            $currentIndex = $i
            break
        }
    }
    
    if ($currentIndex -ge 0) {
        $nextIndex = ($currentIndex + 1) % $sorted.Count
        return $sorted[$nextIndex]
    } else {
        return $sorted[0]
    }
}

function global:Handle-TabNavigation {
    param([bool]$Reverse = $false)
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Debug -Message "Handle-TabNavigation called, Reverse=$Reverse"
    }
    
    $next = Get-NextFocusableComponent -CurrentComponent $script:TuiState.FocusedComponent -Reverse $Reverse
    if ($next) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level Debug -Message "Setting focus to component: Type=$($next.Type), Name=$($next.Name)"
        }
        Set-ComponentFocus -Component $next
    }
}

function global:New-Component {
    param(
        [string]$Type = "Base",
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 10,
        [int]$Height = 1,
        [hashtable]$Props = @{}
    )
    
    $component = @{
        Type = $Type
        X = $X
        Y = $Y
        Width = $Width
        Height = $Height
        Visible = $true
        Focused = $false
        Parent = $null
        Children = @()
        Props = $Props
        State = @{}
        
        Init = { param($self) }
        Render = { param($self) }
        HandleInput = { param($self, $Key) return $false }
        OnFocus = { param($self) $self.Focused = $true }
        OnBlur = { param($self) $self.Focused = $false }
        Dispose = { param($self) }
    }
    
    switch ($Type) {
        "TextInput" { $component = Merge-Hashtables $component (Get-TextInputComponent) }
        "Button" { $component = Merge-Hashtables $component (Get-ButtonComponent) }
        "List" { $component = Merge-Hashtables $component (Get-ListComponent) }
        "Table" { $component = Merge-Hashtables $component (Get-TableComponent) }
    }
    
    return $component
}

function Merge-Hashtables {
    param($Base, $Override)
    $result = $Base.Clone()
    foreach ($key in $Override.Keys) {
        $result[$key] = $Override[$key]
    }
    return $result
}

#endregion

#region Layout Management

function Initialize-LayoutEngines {
    $script:TuiState.Layouts = @{
        Grid = Get-GridLayout
        Stack = Get-StackLayout
        Dock = Get-DockLayout
    }
}

function global:Apply-Layout {
    param(
        [string]$LayoutType,
        [hashtable[]]$Components,
        [hashtable]$Options = @{}
    )
    
    if ($script:TuiState.Layouts.ContainsKey($LayoutType)) {
        $layout = $script:TuiState.Layouts[$LayoutType]
        try {
            Invoke-WithErrorHandling -Component "Layout.$LayoutType" -Context "Applying layout" -ScriptBlock {
                & $layout.Apply -Components $Components -Options $Options
            } -AdditionalData @{ LayoutType = $LayoutType; Options = $Options }
        } catch {
            Write-Warning "Layout error: $($_.Exception.Message)"
        }
    }
}

function Get-GridLayout {
    return @{
        Apply = {
            param($Components, $Options)
            $cols = if ($Options.Columns) { $Options.Columns } else { 2 }
            $rows = [Math]::Ceiling($Components.Count / $cols)
            $cellWidth = [Math]::Floor($script:TuiState.BufferWidth / $cols)
            $cellHeight = [Math]::Floor($script:TuiState.BufferHeight / $rows)
            
            for ($i = 0; $i -lt $Components.Count; $i++) {
                $col = $i % $cols
                $row = [Math]::Floor($i / $cols)
                $Components[$i].X = $col * $cellWidth
                $Components[$i].Y = $row * $cellHeight
                $Components[$i].Width = $cellWidth - 1
                $Components[$i].Height = $cellHeight - 1
            }
        }
    }
}

function Get-StackLayout {
    return @{
        Apply = {
            param($Components, $Options)
            $orientation = if ($Options.Orientation) { $Options.Orientation } else { "Vertical" }
            $spacing = if ($null -ne $Options.Spacing) { $Options.Spacing } else { 1 }
            $x = if ($null -ne $Options.X) { $Options.X } else { 0 }
            $y = if ($null -ne $Options.Y) { $Options.Y } else { 0 }
            
            foreach ($component in $Components) {
                $component.X = $x
                $component.Y = $y
                
                if ($orientation -eq "Vertical") {
                    $y += $component.Height + $spacing
                } else {
                    $x += $component.Width + $spacing
                }
            }
        }
    }
}

function Get-DockLayout {
    return @{
        Apply = {
            param($Components, $Options)
            
            $containerX = if ($null -ne $Options.X) { $Options.X } else { 0 }
            $containerY = if ($null -ne $Options.Y) { $Options.Y } else { 0 }
            $containerWidth = if ($Options.Width) { $Options.Width } else { $script:TuiState.BufferWidth }
            $containerHeight = if ($Options.Height) { $Options.Height } else { $script:TuiState.BufferHeight }
            
            $availableX = $containerX
            $availableY = $containerY
            $availableWidth = $containerWidth
            $availableHeight = $containerHeight
            
            $topComponents = $Components | Where-Object { $_.Props.Dock -eq "Top" }
            $bottomComponents = $Components | Where-Object { $_.Props.Dock -eq "Bottom" }
            $leftComponents = $Components | Where-Object { $_.Props.Dock -eq "Left" }
            $rightComponents = $Components | Where-Object { $_.Props.Dock -eq "Right" }
            $fillComponents = $Components | Where-Object { $_.Props.Dock -eq "Fill" -or -not $_.Props.Dock }
            
            foreach ($comp in $topComponents) {
                $comp.X = $availableX
                $comp.Y = $availableY
                $comp.Width = $availableWidth
                $availableY += $comp.Height
                $availableHeight -= $comp.Height
            }
            
            foreach ($comp in $bottomComponents) {
                $comp.X = $availableX
                $comp.Y = $availableY + $availableHeight - $comp.Height
                $comp.Width = $availableWidth
                $availableHeight -= $comp.Height
            }
            
            foreach ($comp in $leftComponents) {
                $comp.X = $availableX
                $comp.Y = $availableY
                $comp.Height = $availableHeight
                $availableX += $comp.Width
                $availableWidth -= $comp.Width
            }
            
            foreach ($comp in $rightComponents) {
                $comp.X = $availableX + $availableWidth - $comp.Width
                $comp.Y = $availableY
                $comp.Height = $availableHeight
                $availableWidth -= $comp.Width
            }
            
            foreach ($comp in $fillComponents) {
                $comp.X = $availableX
                $comp.Y = $availableY
                $comp.Width = $availableWidth
                $comp.Height = $availableHeight
            }
        }
    }
}

#endregion

#region Utility Functions

function global:Get-BorderChars { 
    param([string]$Style) 
    $styles = @{ 
        Single = @{ 
            TopLeft='┌'; TopRight='┐'; BottomLeft='└'; BottomRight='┘'
            Horizontal='─'; Vertical='│' 
        }
        Double = @{ 
            TopLeft='╔'; TopRight='╗'; BottomLeft='╚'; BottomRight='╝'
            Horizontal='═'; Vertical='║' 
        }
        Rounded = @{ 
            TopLeft='╭'; TopRight='╮'; BottomLeft='╰'; BottomRight='╯'
            Horizontal='─'; Vertical='│' 
        } 
    }
    if ($styles.ContainsKey($Style)) { 
        return $styles[$Style] 
    } else { 
        return $styles.Single 
    }
}

function Get-AnsiColorCode { 
    param([ConsoleColor]$Color, [bool]$IsBackground) 
    $map = @{ 
        Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36
        DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37
        DarkGray=90; Blue=94; Green=92; Cyan=96
        Red=91; Magenta=95; Yellow=93; White=97 
    }
    $code = $map[$Color.ToString()]
    if ($IsBackground) { 
        return $code + 10 
    } else { 
        return $code 
    } 
}

function Get-ThemeColorFallback {
    param($ColorName, $Default = [ConsoleColor]::White)
    return $Default
}

if (-not (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue)) {
    function global:Get-ThemeColor {
        param($ColorName, $Default = [ConsoleColor]::White)
        return Get-ThemeColorFallback -ColorName $ColorName -Default $Default
    }
}

function global:Write-StatusLine { 
    param(
        [string]$Text, 
        [ConsoleColor]$ForegroundColor = 'White', 
        [ConsoleColor]$BackgroundColor = 'DarkBlue'
    ) 
    try { 
        $y = $script:TuiState.BufferHeight
        [Console]::SetCursorPosition(0, $y)
        [Console]::ForegroundColor = $ForegroundColor
        [Console]::BackgroundColor = $BackgroundColor
        [Console]::Write($Text.PadRight([Console]::WindowWidth))
        [Console]::ResetColor() 
    } catch {
        Write-Warning "Status line error: $_"
    } 
}

function global:Subscribe-TuiEvent {
    param($EventName, $Handler)
    if (Get-Command -Name "Subscribe-Event" -ErrorAction SilentlyContinue) {
        $handlerId = Subscribe-Event -EventName $EventName -Handler $Handler
        $script:TuiState.EventHandlers[$EventName] = $handlerId
        return $handlerId
    }
}

#endregion

#region Component Definitions

function Get-TextInputComponent {
    return @{
        Value = ""
        CursorPosition = 0
        MaxLength = 50
        
        Render = {
            param($self)
            try {
                $borderColor = if ($self.Focused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                } else { 
                    Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
                }
                
                Write-BufferBox -X $self.X -Y $self.Y -Width $self.Width -Height $self.Height `
                    -BorderColor $borderColor -BackgroundColor ([ConsoleColor]::Black)
                
                if ($self.Focused) {
                    Write-BufferString -X ($self.X - 1) -Y ($self.Y + [Math]::Floor($self.Height / 2)) `
                        -Text "[" -ForegroundColor ([ConsoleColor]::Yellow)
                    Write-BufferString -X ($self.X + $self.Width) -Y ($self.Y + [Math]::Floor($self.Height / 2)) `
                        -Text "]" -ForegroundColor ([ConsoleColor]::Yellow)
                }
                
                $displayText = $self.Value
                if ($displayText.Length > ($self.Width - 3)) {
                    $displayText = $displayText.Substring($displayText.Length - ($self.Width - 3))
                }
                Write-BufferString -X ($self.X + 1) -Y ($self.Y + 1) -Text $displayText
                
                if ($self.Focused -and $self.CursorPosition -lt ($self.Width - 3)) {
                    Write-BufferString -X ($self.X + 1 + $self.CursorPosition) -Y ($self.Y + 1) `
                        -Text "_" -ForegroundColor ([ConsoleColor]::Yellow)
                }
            } catch {
                Write-Warning "TextInput render error: $_"
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                switch ($Key.Key) {
                    ([ConsoleKey]::Backspace) {
                        if ($self.Value.Length -gt 0 -and $self.CursorPosition -gt 0) {
                            $self.Value = $self.Value.Remove($self.CursorPosition - 1, 1)
                            $self.CursorPosition--
                        }
                        return $true
                    }
                    ([ConsoleKey]::Delete) {
                        if ($self.CursorPosition -lt $self.Value.Length) {
                            $self.Value = $self.Value.Remove($self.CursorPosition, 1)
                        }
                        return $true
                    }
                    ([ConsoleKey]::LeftArrow) {
                        if ($self.CursorPosition -gt 0) {
                            $self.CursorPosition--
                        }
                        return $true
                    }
                    ([ConsoleKey]::RightArrow) {
                        if ($self.CursorPosition -lt $self.Value.Length) {
                            $self.CursorPosition++
                        }
                        return $true
                    }
                    ([ConsoleKey]::Home) {
                        $self.CursorPosition = 0
                        return $true
                    }
                    ([ConsoleKey]::End) {
                        $self.CursorPosition = $self.Value.Length
                        return $true
                    }
                    default {
                        if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar) -and 
                            $self.Value.Length -lt $self.MaxLength) {
                            $self.Value = $self.Value.Insert($self.CursorPosition, $Key.KeyChar)
                            $self.CursorPosition++
                            return $true
                        }
                    }
                }
            } catch {
                Write-Warning "TextInput input error: $_"
            }
            return $false
        }
    }
}

function Get-ButtonComponent {
    return @{
        Text = "Button"
        
        Render = {
            param($self)
            try {
                $bgColor = if ($self.Focused) { 
                    Get-ThemeColor "Accent" -Default ([ConsoleColor]::DarkCyan)
                } else { 
                    Get-ThemeColor "Primary" -Default ([ConsoleColor]::DarkGray)
                }
                
                $text = " $($self.Text) "
                if ($text.Length > $self.Width) {
                    $text = $text.Substring(0, $self.Width)
                }
                
                $x = $self.X + [Math]::Floor(($self.Width - $text.Length) / 2)
                Write-BufferString -X $x -Y $self.Y -Text $text `
                    -ForegroundColor ([ConsoleColor]::White) -BackgroundColor $bgColor
                
                if ($self.Focused) {
                    if ($x -gt 0) {
                        Write-BufferString -X ($x - 1) -Y $self.Y `
                            -Text "[" -ForegroundColor ([ConsoleColor]::Yellow)
                    }
                    if (($x + $text.Length) -lt $script:TuiState.BufferWidth) {
                        Write-BufferString -X ($x + $text.Length) -Y $self.Y `
                            -Text "]" -ForegroundColor ([ConsoleColor]::Yellow)
                    }
                }
            } catch {
                Write-Warning "Button render error: $_"
            }
        }
        
        HandleInput = {
            param($self, $Key)
            try {
                if ($Key.Key -eq [ConsoleKey]::Enter -or $Key.Key -eq [ConsoleKey]::Spacebar) {
                    if ($self.OnClick) {
                        & $self.OnClick -self $self
                    }
                    return $true
                }
            } catch {
                Write-Warning "Button input error: $_"
            }
            return $false
        }
    }
}

function Get-TableComponent {
    return @{
        Data = @()
        Columns = @()
        SelectedRow = 0
        ScrollOffset = 0
        
        Render = {
            param($self)
            try {
                $y = $self.Y
                
                $headerText = ""
                foreach ($col in $self.Columns) {
                    $headerText += $col.Name.PadRight($col.Width)
                }
                Write-BufferString -X $self.X -Y $y -Text $headerText `
                    -ForegroundColor (Get-ThemeColor "Header" -Default ([ConsoleColor]::Cyan))
                $y++
                
                $visibleRows = $self.Data | Select-Object -Skip $self.ScrollOffset -First ($self.Height - 1)
                $rowIndex = $self.ScrollOffset
                foreach ($row in $visibleRows) {
                    $rowText = ""
                    foreach ($col in $self.Columns) {
                        $value = if ($row.($col.Property)) { $row.($col.Property) } else { "" }
                        $rowText += $value.ToString().PadRight($col.Width)
                    }
                    
                    $fg = if ($rowIndex -eq $self.SelectedRow) {
                        Get-ThemeColor "Selection" -Default ([ConsoleColor]::Yellow)
                    } else {
                        Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
                    }
                    
                    Write-BufferString -X $self.X -Y $y -Text $rowText -ForegroundColor $fg
                    $y++
                    $rowIndex++
                }
            } catch {
                Write-Warning "Table render error: $_"
            }
        }
    }
}

#endregion

#region Word Wrap Helper
function global:Get-WordWrappedLines {
    param(
        [string]$Text,
        [int]$MaxWidth
    )
    
    if ([string]::IsNullOrEmpty($Text) -or $MaxWidth -le 0) { return @() }
    
    $lines = @()
    $words = $Text -split '\s+'
    $sb = New-Object System.Text.StringBuilder
    
    foreach ($word in $words) {
        if ($sb.Length -eq 0) {
            [void]$sb.Append($word)
        } elseif (($sb.Length + 1 + $word.Length) -le $MaxWidth) {
            [void]$sb.Append(' ')
            [void]$sb.Append($word)
        } else {
            $lines += $sb.ToString()
            [void]$sb.Clear()
            [void]$sb.Append($word)
        }
    }
    
    if ($sb.Length -gt 0) {
        $lines += $sb.ToString()
    }
    
    return $lines
}
#endregion

function global:Stop-TuiEngine {
    param()
    
    Write-Log -Level Info -Message "Stop-TuiEngine called - shutting down application" -Data @{ Component = "TuiEngine" }
    
    $script:TuiState.Running = $false
    
    if ($script:TuiState.CancellationTokenSource) {
        try {
            $script:TuiState.CancellationTokenSource.Cancel()
        }
        catch {
            Write-Warning "Failed to cancel input thread: $_"
        }
    }
    
    Safe-PublishEvent -EventName "System.Shutdown" -Data @{ Reason = "User requested" }
}

# AI: FIX - Narrowed export list to only public-facing functions.
Export-ModuleMember -Function @(
    'Initialize-TuiEngine',
    'Start-TuiLoop',
    'Stop-TuiEngine',
    'Push-Screen',
    'Pop-Screen',
    'Request-TuiRefresh',
    'Write-BufferString',
    'Write-BufferBox',
    'Clear-BackBuffer',
    'Write-StatusLine',
    'Get-BorderChars',
    'Register-Component',
    'Set-ComponentFocus',
    'Clear-ComponentFocus',
    'Get-NextFocusableComponent',
    'Handle-TabNavigation',
    'New-Component',
    'Apply-Layout',
    'Get-WordWrappedLines',
    'Subscribe-TuiEvent'
) -Variable 'TuiState'