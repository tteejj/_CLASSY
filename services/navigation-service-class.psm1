# Navigation Service - Class-Based Implementation
# Manages screen navigation with proper error handling and validation
# AI: Updated with sophisticated navigation features from R2 version

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Screen Factory Class for creating screen instances

class ScreenFactory {
    [hashtable] $Services
    [hashtable] $ScreenTypes = @{}
    
    ScreenFactory([hashtable]$services) {
        if ($null -eq $services) {
            throw [System.ArgumentNullException]::new("services", "Services cannot be null")
        }
        $this.Services = $services
        $this.RegisterDefaultScreens()
    }
    
    hidden [void] RegisterDefaultScreens() {
        # AI: Register factory functions for both class-based and hashtable-based screens
        $this.ScreenTypes = @{
            "DashboardScreen" = { param($services) $this.CreateClassBasedScreen("DashboardScreen", $services) }
            "TaskListScreen" = { param($services) $this.CreateClassBasedScreen("TaskListScreen", $services) }
            "NewTaskScreen" = { param($services) $this.CreateClassBasedScreen("NewTaskScreen", $services) }
        }
        
        # AI: Also support function-based screens for backward compatibility
        if (Get-Command "Get-DashboardScreen" -ErrorAction SilentlyContinue) {
            $this.ScreenTypes["DashboardScreen"] = { param($services) Get-DashboardScreen -Services $services }
        }
        if (Get-Command "Get-TaskManagementScreen" -ErrorAction SilentlyContinue) {
            $this.ScreenTypes["TaskManagementScreen"] = { param($services) Get-TaskManagementScreen -Services $services }
        }
    }
    
    hidden [object] CreateClassBasedScreen([string]$screenName, [hashtable]$services) {
        # AI: Try to create class-based screen dynamically, fallback to function-based
        try {
            # Attempt to get the type dynamically without hardcoding class names
            $screenType = "$screenName" -as [type]
            if ($screenType) {
                # Check if the type has a constructor that takes services
                $constructor = $screenType.GetConstructor([type[]]@([hashtable]))
                if ($constructor) {
                    return $screenType::new($services)
                }
            }
        }
        catch {
            # Ignore type resolution errors and fall through to function-based approach
        }
        
        # Fallback: try to find and call a function-based screen creator
        $functionName = "Get-$screenName"
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            return & $functionName -Services $services
        }
        
        throw [System.InvalidOperationException]::new("Unable to create screen: $screenName")
    }
    
    [void] RegisterScreen([string]$name, [scriptblock]$factory) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new("Screen name cannot be null or empty", "name")
        }
        if ($null -eq $factory) {
            throw [System.ArgumentNullException]::new("factory", "Screen factory cannot be null")
        }
        
        $this.ScreenTypes[$name] = $factory
        Write-Log -Level Debug -Message "Registered screen factory: $name"
    }
    
    [object] CreateScreen([string]$screenName) {
        return $this.CreateScreen($screenName, @{})
    }
    
    [object] CreateScreen([string]$screenName, [hashtable]$parameters) {
        if ([string]::IsNullOrWhiteSpace($screenName)) {
            throw [System.ArgumentException]::new("Screen name cannot be null or empty", "screenName")
        }
        
        if (-not $this.ScreenTypes.ContainsKey($screenName)) {
            $availableScreens = ($this.ScreenTypes.Keys | Sort-Object) -join ", "
            throw [System.InvalidOperationException]::new(
                "Unknown screen type: '$screenName'. Available screens: $availableScreens"
            )
        }
        
        try {
            $factory = $this.ScreenTypes[$screenName]
            $screen = & $factory -services $this.Services
            
            if ($null -eq $screen) {
                throw [System.InvalidOperationException]::new("Screen factory returned null for '$screenName'")
            }
            
            # Store services reference on screen for later use
            if ($screen -is [hashtable] -and -not $screen._services) {
                $screen._services = $this.Services
            }
            elseif ($screen.PSObject.Properties.Name -contains "Services" -and -not $screen.Services) {
                $screen.Services = $this.Services
            }
            
            # Apply parameters to screen state
            if ($parameters -and $parameters.Count -gt 0) {
                if ($screen -is [hashtable] -and $screen.ContainsKey("State")) {
                    foreach ($key in $parameters.Keys) {
                        $screen.State[$key] = $parameters[$key]
                    }
                }
                elseif ($screen.PSObject.Properties.Name -contains "State") {
                    foreach ($key in $parameters.Keys) {
                        $screen.State[$key] = $parameters[$key]
                    }
                }
            }
            
            Write-Log -Level Debug -Message "Created screen: $screenName"
            return $screen
        }
        catch {
            Write-Log -Level Error -Message "Failed to create screen '$screenName': $_"
            throw
        }
    }
}

#endregion

#region Navigation Service Class - Manages screen stack and navigation

class NavigationService {
    [System.Collections.Generic.Stack[object]] $ScreenStack
    [ScreenFactory] $ScreenFactory
    [object] $CurrentScreen
    [hashtable] $Services
    [int] $MaxStackDepth = 10
    [hashtable] $NavigationHistory = @{}
    [hashtable] $RouteMap = @{}
    
    NavigationService([hashtable]$services) {
        if ($null -eq $services) {
            throw [System.ArgumentNullException]::new("services", "Services cannot be null")
        }
        
        $this.Services = $services
        $this.ScreenStack = [System.Collections.Generic.Stack[object]]::new()
        $this.ScreenFactory = [ScreenFactory]::new($services)
        $this.InitializeRoutes()
        
        Write-Log -Level Info -Message "NavigationService initialized"
    }
    
    hidden [void] InitializeRoutes() {
        # AI: Map URL-like paths to screen names
        $this.RouteMap = @{
            "/" = "DashboardScreen"
            "/dashboard" = "DashboardScreen"
            "/tasks" = "TaskListScreen"
            "/new-task" = "NewTaskScreen"
        }
    }
    
    [void] RegisterRoute([string]$path, [string]$screenName) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new("Route path cannot be null or empty", "path")
        }
        if ([string]::IsNullOrWhiteSpace($screenName)) {
            throw [System.ArgumentException]::new("Screen name cannot be null or empty", "screenName")
        }
        
        $this.RouteMap[$path] = $screenName
        Write-Log -Level Debug -Message "Registered route: $path -> $screenName"
    }
    
    [void] PushScreen([string]$screenName) {
        $this.PushScreen($screenName, @{})
    }
    
    [void] PushScreen([string]$screenName, [hashtable]$parameters) {
        Invoke-WithErrorHandling -Component "NavigationService" -Context "PushScreen:$screenName" -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($screenName)) {
                throw [System.ArgumentException]::new("Screen name cannot be null or empty", "screenName")
            }
            
            # Check stack depth limit
            if ($this.ScreenStack.Count -ge $this.MaxStackDepth) {
                throw [System.InvalidOperationException]::new(
                    "Navigation stack depth limit reached ($($this.MaxStackDepth))"
                )
            }
            
            Write-Log -Level Info -Message "Pushing screen: $screenName"
            
            # Handle current screen exit
            if ($null -ne $this.CurrentScreen) {
                try {
                    $this.CallScreenMethod($this.CurrentScreen, "OnExit")
                    $this.ScreenStack.Push($this.CurrentScreen)
                }
                catch {
                    Write-Log -Level Warning -Message "Error during current screen cleanup: $_"
                }
            }
            
            # Create new screen
            $newScreen = $this.ScreenFactory.CreateScreen($screenName, $parameters)
            
            # Set as current screen
            $this.CurrentScreen = $newScreen
            
            # Initialize the new screen
            try {
                $this.CallScreenMethod($newScreen, "Initialize", $this.Services)
                $this.CallScreenMethod($newScreen, "OnEnter")
            }
            catch {
                Write-Log -Level Error -Message "Failed to initialize screen '$screenName': $_"
                throw
            }
            
            # Track navigation history
            $this.TrackNavigation($screenName, "Push")
            
            # Update TUI state if available
            if ($global:TuiState) {
                $global:TuiState.CurrentScreen = $newScreen
                if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                    Request-TuiRefresh
                }
            }
            
            # Publish navigation event
            if (Get-Command "Publish-Event" -ErrorAction SilentlyContinue) {
                # AI: Ensure event data is serializable
                $eventData = @{
                    Screen = $screenName
                    Action = "Push"
                    StackDepth = $this.ScreenStack.Count + 1
                }
                
                # AI: Only include parameters if they're simple types
                if ($parameters -and $parameters.Count -gt 0) {
                    $simpleParams = @{}
                    foreach ($key in $parameters.Keys) {
                        $value = $parameters[$key]
                        if ($value -is [string] -or $value -is [int] -or $value -is [bool] -or $value -is [datetime]) {
                            $simpleParams[$key] = $value
                        }
                    }
                    if ($simpleParams.Count -gt 0) {
                        $eventData.Parameters = $simpleParams
                    }
                }
                
                Publish-Event -EventName "Navigation.ScreenChanged" -Data $eventData
            }
            
            Write-Log -Level Debug -Message "Screen '$screenName' pushed successfully. Stack depth: $($this.ScreenStack.Count + 1)"
        }
    }
    
    [bool] PopScreen() {
        return Invoke-WithErrorHandling -Component "NavigationService" -Context "PopScreen" -ScriptBlock {
            if ($this.ScreenStack.Count -eq 0) {
                Write-Log -Level Warning -Message "Cannot pop screen: stack is empty"
                return $false
            }
            
            Write-Log -Level Info -Message "Popping screen"
            
            # Exit current screen
            if ($null -ne $this.CurrentScreen) {
                try {
                    $this.CallScreenMethod($this.CurrentScreen, "OnExit")
                }
                catch {
                    Write-Log -Level Warning -Message "Error during screen exit: $_"
                }
            }
            
            # Pop previous screen
            $this.CurrentScreen = $this.ScreenStack.Pop()
            
            # Resume previous screen
            if ($null -ne $this.CurrentScreen) {
                try {
                    $this.CallScreenMethod($this.CurrentScreen, "OnResume")
                }
                catch {
                    Write-Log -Level Warning -Message "Error during screen resume: $_"
                }
                
                # Update TUI state
                if ($global:TuiState) {
                    $global:TuiState.CurrentScreen = $this.CurrentScreen
                    if (Get-Command "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
                        Request-TuiRefresh
                    }
                }
            }
            
            # Publish event
            if (Get-Command "Publish-Event" -ErrorAction SilentlyContinue) {
                $screenName = if ($this.CurrentScreen -is [hashtable] -and $this.CurrentScreen.Name) {
                    $this.CurrentScreen.Name
                } elseif ($this.CurrentScreen.PSObject.Properties.Name -contains "Name") {
                    $this.CurrentScreen.Name
                } else {
                    $null
                }
                
                Publish-Event -EventName "Navigation.ScreenPopped" -Data @{
                    CurrentScreen = $screenName
                    StackDepth = $this.ScreenStack.Count
                }
            }
            
            return $true
        }
    }
    
    [bool] GoTo([string]$path) {
        return $this.GoTo($path, @{})
    }
    
    [bool] GoTo([string]$path, [hashtable]$parameters) {
        return Invoke-WithErrorHandling -Component "NavigationService" -Context "GoTo:$path" -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw [System.ArgumentException]::new("Navigation path cannot be null or empty", "path")
            }
            
            Write-Log -Level Info -Message "Navigating to path: $path"
            
            # Handle special cases
            if ($path -eq "/exit") {
                $this.RequestExit()
                return $true
            }
            
            # Map path to screen name
            if (-not $this.RouteMap.ContainsKey($path)) {
                $availableRoutes = ($this.RouteMap.Keys | Sort-Object) -join ", "
                Write-Log -Level Warning -Message "Unknown navigation path: $path. Available routes: $availableRoutes"
                return $false
            }
            
            $screenName = $this.RouteMap[$path]
            
            try {
                $this.PushScreen($screenName, $parameters)
                return $true
            }
            catch {
                Write-Log -Level Error -Message "Failed to navigate to '$screenName' via path '$path': $_"
                return $false
            }
        }
    }
    
    [void] RequestExit() {
        Write-Log -Level Info -Message "Exit requested"
        
        # Clean up all screens
        while ($this.ScreenStack.Count -gt 0) {
            try {
                $this.PopScreen()
            }
            catch {
                Write-Log -Level Warning -Message "Error during exit cleanup: $_"
            }
        }
        
        # Exit current screen
        if ($null -ne $this.CurrentScreen) {
            try {
                $this.CallScreenMethod($this.CurrentScreen, "OnExit")
            }
            catch {
                Write-Log -Level Warning -Message "Error during final screen cleanup: $_"
            }
        }
        
        # Stop TUI engine if available
        if (Get-Command "Stop-TuiEngine" -ErrorAction SilentlyContinue) {
            Stop-TuiEngine
        }
        
        # Publish exit event
        if (Get-Command "Publish-Event" -ErrorAction SilentlyContinue) {
            Publish-Event -EventName "Application.Exit" -Data @{}
        }
    }
    
    [object] GetCurrentScreen() {
        return $this.CurrentScreen
    }
    
    [int] GetStackDepth() {
        return $this.ScreenStack.Count
    }
    
    [string[]] GetAvailableRoutes() {
        return $this.RouteMap.Keys | Sort-Object
    }
    
    [bool] IsValidRoute([string]$path) {
        return $this.RouteMap.ContainsKey($path)
    }
    
    [hashtable] GetNavigationStats() {
        return $this.NavigationHistory.Clone()
    }
    
    hidden [void] CallScreenMethod([object]$screen, [string]$methodName) {
        $this.CallScreenMethod($screen, $methodName, $null)
    }
    
    hidden [void] CallScreenMethod([object]$screen, [string]$methodName, [object]$parameter) {
        if ($null -eq $screen) {
            return
        }
        
        try {
            # Handle both class-based and hashtable-based screens
            if ($screen -is [hashtable] -and $screen.ContainsKey($methodName)) {
                $method = $screen[$methodName]
                if ($method -is [scriptblock]) {
                    if ($null -ne $parameter) {
                        & $method -self $screen -parameter $parameter
                    } else {
                        & $method -self $screen
                    }
                }
            }
            elseif ($screen.PSObject.Methods.Name -contains $methodName) {
                # Class-based screen
                if ($null -ne $parameter) {
                    $screen.$methodName($parameter)
                } else {
                    $screen.$methodName()
                }
            }
        }
        catch {
            Write-Log -Level Warning -Message "Error calling screen method '$methodName': $_"
        }
    }
    
    hidden [void] TrackNavigation([string]$screenName, [string]$action) {
        $timestamp = [DateTime]::UtcNow
        
        if (-not $this.NavigationHistory.ContainsKey($screenName)) {
            $this.NavigationHistory[$screenName] = @{
                VisitCount = 0
                LastVisit = $null
                FirstVisit = $timestamp
            }
        }
        
        $this.NavigationHistory[$screenName].VisitCount++
        $this.NavigationHistory[$screenName].LastVisit = $timestamp
        
        Write-Log -Level Debug -Message "Tracked navigation: $screenName ($action)"
    }
}

#endregion

# Initialize function for backward compatibility
function Initialize-NavigationService {
    param([hashtable]$Services)
    
    if (-not $Services) {
        throw [System.ArgumentNullException]::new("Services", "Services parameter is required")
    }
    
    return [NavigationService]::new($Services)
}

# Export the functions and classes
Export-ModuleMember -Function Initialize-NavigationService