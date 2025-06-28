# Dashboard Screen - Helios Service-Based Version (CORRECTED)
# Conforms to Z-Index rendering and proper service injection patterns

function Get-DashboardScreen {
    param([hashtable]$Services)

    $screen = @{
        Name = "DashboardScreen"
        Components = @{}
        Children = @()   # FIX: Added Children array for the Z-Index renderer to discover components.
        _subscriptions = @()
        Visible = $true
        ZIndex = 0

        Init = {
            param($self, $services)
            
            Write-Log -Level Debug -Message "Dashboard Init started (Helios version)"
            
            try {
                # Store services passed to Init
                if ($services) {
                    $self._services = $services
                } else {
                    $services = $self._services
                }
                
                if (-not $services) {
                    Write-Log -Level Error -Message "Services not available for dashboard screen"
                    return
                }
                
                # Create the main grid layout
                $rootPanel = New-TuiGridPanel -Props @{
                    X = 1
                    Y = 2
                    Width = ($global:TuiState.BufferWidth - 2)
                    Height = ($global:TuiState.BufferHeight - 4)
                    ShowBorder = $false
                    RowDefinitions = @("14", "1*")
                    ColumnDefinitions = @("37", "42", "1*")
                }
                $self.Components.rootPanel = $rootPanel
                $self.Children += $rootPanel # FIX: Add rootPanel to the Children array for the engine to find.
                
                Write-Log -Level Debug -Message "Dashboard: Created rootPanel, Children count=$($self.Children.Count)"

                # --- Quick Actions Panel ---
                $quickActionsPanel = New-TuiStackPanel -Props @{
                    Name = "quickActionsPanel"
                    Title = " Quick Actions "
                    ShowBorder = $true
                    Padding = 1
                }
                
                $quickActions = New-TuiDataTable -Props @{
                    Name = "quickActions"
                    IsFocusable = $true
                    ShowBorder = $false
                    ShowHeader = $false
                    ShowFooter = $false
                    Columns = @( @{ Name = "Action"; Width = 32 } )
                    Data = @() # Will be populated from store
                    OnRowSelect = {
                        param($SelectedData, $SelectedIndex)
                        $routes = @("/time-entry", "/timer/start", "/tasks", "/projects", "/reports", "/settings")
                        if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $routes.Count) {
                            # Access services from the screen instance
                            $screenServices = $self._services
                            & $screenServices.Navigation.GoTo -self $screenServices.Navigation -Path $routes[$SelectedIndex] -Services $screenServices
                        }
                    }
                }
                & $quickActionsPanel.AddChild -self $quickActionsPanel -Child $quickActions
                & $rootPanel.AddChild -self $rootPanel -Child $quickActionsPanel -LayoutProps @{ "Grid.Row" = 0; "Grid.Column" = 0 }
                
                # --- Active Timers Panel ---
                $timersPanel = New-TuiStackPanel -Props @{
                    Name = "timersPanel"
                    Title = " Active Timers "
                    ShowBorder = $true
                    Padding = 1
                }
                $activeTimers = New-TuiDataTable -Props @{
                    Name = "activeTimers"
                    IsFocusable = $true
                    ShowBorder = $false
                    ShowFooter = $false
                    Columns = @( @{ Name = "Project"; Width = 20 }, @{ Name = "Time"; Width = 10 } )
                    Data = @()
                }
                & $timersPanel.AddChild -self $timersPanel -Child $activeTimers
                & $rootPanel.AddChild -self $rootPanel -Child $timersPanel -LayoutProps @{ "Grid.Row" = 0; "Grid.Column" = 1 }
                
                # --- Stats Panel ---
                $statsPanel = New-TuiStackPanel -Props @{
                    Name = "statsPanel"
                    Title = " Stats "
                    ShowBorder = $true
                    Padding = 1
                    Orientation = "Vertical"
                    Spacing = 1
                }
                $todayLabel = New-TuiLabel -Props @{ Name = "todayHoursLabel"; Text = "Today: 0h"; Height = 1 }
                $weekLabel = New-TuiLabel -Props @{ Name = "weekHoursLabel"; Text = "Week: 0h"; Height = 1 }
                $tasksLabel = New-TuiLabel -Props @{ Name = "activeTasksLabel"; Text = "Tasks: 0"; Height = 1 }
                $timersLabel = New-TuiLabel -Props @{ Name = "runningTimersLabel"; Text = "Timers: 0"; Height = 1 }
                & $statsPanel.AddChild -self $statsPanel -Child $todayLabel
                & $statsPanel.AddChild -self $statsPanel -Child $weekLabel
                & $statsPanel.AddChild -self $statsPanel -Child $tasksLabel
                & $statsPanel.AddChild -self $statsPanel -Child $timersLabel
                & $rootPanel.AddChild -self $rootPanel -Child $statsPanel -LayoutProps @{ "Grid.Row" = 0; "Grid.Column" = 2 }
                
                # --- Today's Tasks Panel ---
                $tasksPanel = New-TuiStackPanel -Props @{
                    Name = "tasksPanel"
                    Title = " Today's Tasks "
                    ShowBorder = $true
                    Padding = 1
                }
                $todaysTasks = New-TuiDataTable -Props @{
                    Name = "todaysTasks"
                    IsFocusable = $true
                    ShowBorder = $false
                    ShowFooter = $false
                    Columns = @( @{ Name = "Priority"; Width = 8 }, @{ Name = "Task"; Width = 45 }, @{ Name = "Project"; Width = 15 } )
                    Data = @()
                }
                & $tasksPanel.AddChild -self $tasksPanel -Child $todaysTasks
                & $rootPanel.AddChild -self $rootPanel -Child $tasksPanel -LayoutProps @{ "Grid.Row" = 1; "Grid.Column" = 0; "Grid.ColumnSpan" = 3 }
                
                # Store references for easy access
                $self._activeTimers = $activeTimers
                $self._todaysTasks = $todaysTasks
                $self._todayLabel = $todayLabel
                $self._weekLabel = $weekLabel
                $self._tasksLabel = $tasksLabel
                $self._timersLabel = $timersLabel
                
                # Subscribe to app store updates
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "quickActions" -handler { param($data) ; $quickActions.Data = $data.NewValue ; & $quickActions.ProcessData -self $quickActions }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "activeTimers" -handler { param($data) ; $self._activeTimers.Data = $data.NewValue ; & $self._activeTimers.ProcessData -self $self._activeTimers }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "todaysTasks" -handler { param($data) ; $self._todaysTasks.Data = $data.NewValue ; & $self._todaysTasks.ProcessData -self $self._todaysTasks }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "stats.todayHours" -handler { param($data) ; $self._todayLabel.Text = "Today: $($data.NewValue)h" }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "stats.weekHours" -handler { param($data) ; $self._weekLabel.Text = "Week: $($data.NewValue)h" }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "stats.activeTasks" -handler { param($data) ; $self._tasksLabel.Text = "Tasks: $($data.NewValue)" }
                $self._subscriptions += & $services.Store.Subscribe -self $services.Store -path "stats.runningTimers" -handler { param($data) ; $self._timersLabel.Text = "Timers: $($data.NewValue)" }
                
                # Initial data load - populate quick actions first
                & $services.Store.Dispatch -self $services.Store -actionName "LOAD_DASHBOARD_DATA"
                & $services.Store.Dispatch -self $services.Store -actionName "DASHBOARD_REFRESH"
                
                # Register screen with focus manager after all components are created
                if (Get-Command -Name "Register-ScreenForFocus" -ErrorAction SilentlyContinue) {
                    Register-ScreenForFocus -Screen $self
                }
                
                # Set initial focus
                Request-Focus -Component $quickActions
                
                # FIX: Set up auto-refresh timer with proper service access via MessageData
                $self._refreshTimer = [System.Timers.Timer]::new(5000)
                $self._timerSubscription = Register-ObjectEvent -InputObject $self._refreshTimer -EventName Elapsed -MessageData $services -Action {
                    $passedServices = $Event.MessageData
                    try {
                        if ($passedServices -and $passedServices.Store) {
                            & $passedServices.Store.Dispatch -self $passedServices.Store -actionName "DASHBOARD_REFRESH"
                        } else {
                            Write-Log -Level Error -Message "Timer event: services not available via MessageData"
                        }
                    } catch {
                        Write-Log -Level Error -Message "Timer DASHBOARD_REFRESH failed: $_"
                    }
                }
                $self._refreshTimer.Start()
                
                Write-Log -Level Debug -Message "Dashboard Init completed"
                
            } catch {
                Write-Log -Level Error -Message "Dashboard Init error: $_" -Data $_
            }
        }
        
        Render = {
            param($self)
            
            try {
                # This method now ONLY draws screen-level "chrome" (non-component elements).
                # The engine handles rendering the component tree in the Children array.
                
                # Header
                $headerColor = Get-ThemeColor "Header" -Default Cyan
                $currentTime = Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss'
                Write-BufferString -X 2 -Y 1 -Text "PMC Terminal Dashboard - $currentTime" -ForegroundColor $headerColor
                
                # Active timer indicator
                $store = $self._services.Store
                if ($store) {
                    $timers = & $store.GetState -self $store -path "stats.runningTimers"
                    if ($timers -gt 0) {
                        $timerText = "● TIMER ACTIVE"
                        $timerX = $global:TuiState.BufferWidth - $timerText.Length - 2
                        Write-BufferString -X $timerX -Y 1 -Text $timerText -ForegroundColor Red
                    }
                }
                
                # Status bar
                $subtleColor = Get-ThemeColor "Subtle" -Default DarkGray
                $statusY = $global:TuiState.BufferHeight - 2
                Write-BufferString -X 2 -Y $statusY -Text "Tab: Switch Focus | Enter: Select | R: Refresh | Q: Quit | F12: Debug Log" -ForegroundColor $subtleColor
                
            } catch {
                Write-Log -Level Error -Message "Dashboard Render error: $_" -Data $_
                Write-BufferString -X 2 -Y 2 -Text "Error rendering dashboard: $_" -ForegroundColor Red
            }
        }
        
        HandleInput = {
            param($self, $Key)
            
            try {
                $services = $self._services
                if (-not $services) { return $false }
                
                $action = & $services.Keybindings.HandleKey -self $services.Keybindings -KeyInfo $Key
                
                switch ($action) {
                    "App.Refresh" { & $services.Store.Dispatch -self $services.Store -actionName "DASHBOARD_REFRESH"; return $true }
                    "App.DebugLog" { & $services.Navigation.GoTo -self $services.Navigation -Path "/log" -Services $services; return $true }
                    "App.Quit" { return "Quit" }
                    "App.Back" { return "Quit" }
                }
                
                if ($Key.KeyChar -ge '1' -and $Key.KeyChar -le '6') {
                    $index = [int]$Key.KeyChar.ToString() - 1
                    $routes = @("/time-entry", "/timer/start", "/tasks", "/projects", "/reports", "/settings")
                    & $services.Navigation.GoTo -self $services.Navigation -Path $routes[$index] -Services $services
                    return $true
                }
                
                return $false
                
            } catch {
                Write-Log -Level Error -Message "HandleInput error: $_" -Data $_
                return $false
            }
        }
        
        OnExit = {
            param($self)
            
            Write-Log -Level Debug -Message "Dashboard screen exiting"
            
            if ($self._refreshTimer) {
                $self._refreshTimer.Stop()
                $self._refreshTimer.Dispose()
            }
            if ($self._timerSubscription) {
                Unregister-Event -SubscriptionId $self._timerSubscription.Id -ErrorAction SilentlyContinue
                $self._timerSubscription = $null
            }
            
            $services = $self._services
            if ($services -and $services.Store) {
                foreach ($subId in $self._subscriptions) {
                    & $services.Store.Unsubscribe -self $services.Store -subId $subId
                }
            }
        }
        
        OnResume = {
            param($self)
            
            Write-Log -Level Debug -Message "Dashboard screen resuming"
            $global:TuiState.RenderStats.FrameCount = 0
            
            $services = $self._services
            if ($services -and $services.Store) {
                & $services.Store.Dispatch -self $services.Store -actionName "DASHBOARD_REFRESH"
            }
            Request-TuiRefresh
        }
    }
    
    $screen._services = $Services
    return $screen
}

Export-ModuleMember -Function Get-DashboardScreen