# Context capture helper for consistent handler creation
function New-ContextHandler {
    param(
        [hashtable]$CapturedContext,
        [scriptblock]$Handler
    )
    
    # Create a closure that captures the context
    $wrapper = {
        param($Event, $Args)
        $context = $CapturedContext
        & $Handler -Context $context -Event $Event -Args $Args
    }.GetNewClosure()
    
    # Store the captured context for debugging
    Add-Member -InputObject $wrapper -MemberType NoteProperty -Name "_CapturedContext" -Value $CapturedContext
    
    return $wrapper
}

# Screen context capture helper
function Get-ScreenContext {
    param([hashtable]$Screen)
    
    return @{
        Screen = $Screen
        Services = $Screen._services
        Store = $Screen._services.Store
        Navigation = $Screen._services.Navigation
        Components = $Screen.Components
    }
}

# Safe method invocation helper
function Invoke-SafeMethod {
    param(
        [hashtable]$Object,
        [string]$MethodName,
        [hashtable]$Parameters = @{}
    )
    
    if (-not $Object) {
        Write-Log -Level Warning -Message "Cannot invoke $MethodName on null object"
        return $null
    }
    
    if (-not $Object[$MethodName]) {
        Write-Log -Level Warning -Message "Method $MethodName not found on object"
        return $null
    }
    
    try {
        return & $Object[$MethodName] -self $Object @Parameters
    } catch {
        Write-Log -Level Error -Message "Error invoking $MethodName" -Data $_
        throw
    }
}

Export-ModuleMember -Function @(
    'New-ContextHandler',
    'Get-ScreenContext',
    'Invoke-SafeMethod'
)
