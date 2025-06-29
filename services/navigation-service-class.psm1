# Navigation Service - Class-Based Implementation
# Manages screen navigation, routing, and history.

using module ..\components\ui-classes.psm1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

class ScreenFactory {
    hidden [hashtable] $Services
    hidden [hashtable] $ScreenTypes = @{}
    
    ScreenFactory([hashtable]$services) {
        $this.Services = $services ?? (throw [System.ArgumentNullException]::new("services"))
        $this.RegisterDefaultScreens()
    }
    
    hidden [void] RegisterDefaultScreens() {
        # Screen classes are discovered by the main script's `using module` statements.
        $screenBaseType = [Screen]
        $loadedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
        $screenClasses = $loadedAssemblies.GetTypes() | Where-Object { $_.IsSubclassOf($screenBaseType) -and -not $_.IsAbstract }
        
        foreach ($class in $screenClasses) {
            $this.RegisterScreen($class.Name, $class)
        }
    }
    
    [void] RegisterScreen([string]$name, [type]$screenType) {
        if (-not $screenType.IsSubclassOf([Screen])) { throw "'$($screenType.Name)' must inherit from the Screen class." }
        $this.ScreenTypes[$name] = $screenType
        Write-Log -Level Debug -Message "Registered screen factory: $name"
    }
    
    [Screen] CreateScreen([string]$screenName, [hashtable]$parameters) {
        $screenType = $this.ScreenTypes[$screenName] ?? (throw [System.InvalidOperationException]::new("Unknown screen type: '$screenName'."))
        
        try {
            $screen = $screenType.GetConstructor(@([hashtable])).Invoke(@($this.Services))
            if ($parameters) {
                foreach ($key in $parameters.Keys) { $screen.State[$key] = $parameters[$key] }
            }
            Write-Log -Level Debug -Message "Created screen: $screenName"
            return $screen
        } catch {
            Write-Log -Level Error -Message "Failed to create screen '$screenName': $_"
            throw
        }
    }
}

class NavigationService {
    [System.Collections.Generic.Stack[Screen]] $ScreenStack
    [ScreenFactory] $ScreenFactory
    [Screen] $CurrentScreen
    [hashtable] $Services
    [hashtable] $RouteMap = @{}
    
    NavigationService([hashtable]$services) {
        $this.Services = $services ?? (throw [System.ArgumentNullException]::new("services"))
        $this.ScreenStack = [System.Collections.Generic.Stack[Screen]]::new()
        $this.ScreenFactory = [ScreenFactory]::new($services)
        $this.InitializeRoutes()
        Write-Log -Level Info -Message "NavigationService initialized"
    }
    
    hidden [void] InitializeRoutes() {
        $this.RouteMap = @{
            "/" = "DashboardScreen"
            "/dashboard" = "DashboardScreen"
            "/tasks" = "TaskListScreen"
        }
    }
    
    [void] GoTo([string]$path, [hashtable]$parameters = @{}) {
        Invoke-WithErrorHandling -Component "NavigationService" -Context "GoTo:$path" -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($path)) { throw [System.ArgumentException]::new("Path cannot be empty.") }
            if ($path -eq "/exit") { $this.RequestExit(); return }
            
            $screenName = $this.RouteMap[$path] ?? (throw [System.InvalidOperationException]::new("Unknown route: $path"))
            $this.PushScreen($screenName, $parameters)
        }
    }
    
    [void] PushScreen([string]$screenName, [hashtable]$parameters = @{}) {
        Invoke-WithErrorHandling -Component "NavigationService" -Context "PushScreen:$screenName" -ScriptBlock {
            if ($this.CurrentScreen) {
                $this.CurrentScreen.OnExit()
                $this.ScreenStack.Push($this.CurrentScreen)
            }
            
            $newScreen = $this.ScreenFactory.CreateScreen($screenName, $parameters)
            $this.CurrentScreen = $newScreen
            
            $newScreen.Initialize()
            $newScreen.OnEnter()
            
            if ($global:TuiState) {
                $global:TuiState.CurrentScreen = $newScreen
                Request-TuiRefresh
            }
            Publish-Event -EventName "Navigation.ScreenChanged" -Data @{ Screen = $screenName; Action = "Push" }
        }
    }
    
    [bool] PopScreen() {
        return Invoke-WithErrorHandling -Component "NavigationService" -Context "PopScreen" -ScriptBlock {
            if ($this.ScreenStack.Count -eq 0) { Write-Log -Level Warning -Message "Cannot pop screen: stack is empty"; return $false }
            
            $this.CurrentScreen?.OnExit()
            $this.CurrentScreen = $this.ScreenStack.Pop()
            $this.CurrentScreen?.OnResume()
            
            if ($global:TuiState) {
                $global:TuiState.CurrentScreen = $this.CurrentScreen
                Request-TuiRefresh
            }
            Publish-Event -EventName "Navigation.ScreenPopped" -Data @{ Screen = $this.CurrentScreen.Name }
            return $true
        }
    }
    
    [void] RequestExit() {
        Write-Log -Level Info -Message "Exit requested"
        while ($this.PopScreen()) {} # Pop all screens
        $this.CurrentScreen?.OnExit()
        Stop-TuiEngine
        Publish-Event -EventName "Application.Exit"
    }
    
    [Screen] GetCurrentScreen() { return $this.CurrentScreen }
    [bool] IsValidRoute([string]$path) { return $this.RouteMap.ContainsKey($path) }
}

function Initialize-NavigationService {
    param([hashtable]$Services)
    if (-not $Services) { throw [System.ArgumentNullException]::new("Services") }
    return [NavigationService]::new($Services)
}

# AI: FIX - Removed '-Class' parameter.
Export-ModuleMember -Function 'Initialize-NavigationService'