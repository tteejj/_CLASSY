# Fixed Error Handling Wrapper for PowerShell Classes
# Solves parameter binding issues with Context parameter

function global:Invoke-WithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $true)]
        [string]$Context,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [hashtable]$AdditionalData = @{}
    )
    
    # Validate parameters
    if ([string]::IsNullOrWhiteSpace($Component)) {
        $Component = "Unknown"
    }
    if ([string]::IsNullOrWhiteSpace($Context)) {
        $Context = "Unknown"
    }
    
    try {
        # Execute the script block
        & $ScriptBlock
    }
    catch {
        # Create enriched error data
        $errorData = @{
            Component = $Component
            Context = $Context
            Error = $_
            Exception = $_.Exception
            ScriptStackTrace = $_.ScriptStackTrace
            Timestamp = Get-Date
        }
        
        # Merge additional data
        foreach ($key in $AdditionalData.Keys) {
            $errorData[$key] = $AdditionalData[$key]
        }
        
        # Log the error if logging is available
        if (Get-Command -Name "Write-Log" -ErrorAction SilentlyContinue) {
            Write-Log -Level Error -Message "Error in '$Component' during '$Context': $($_.Exception.Message)" -Data $errorData
        }
        
        # Re-throw the original exception
        throw
    }
}

# Fixed version for use in classes
function global:Invoke-ClassMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        
        [Parameter(Mandatory = $true)]
        [string]$MethodName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [hashtable]$Data = @{}
    )
    
    # Ensure parameters are valid
    $component = if ([string]::IsNullOrWhiteSpace($ClassName)) { "UnknownClass" } else { $ClassName }
    $context = if ([string]::IsNullOrWhiteSpace($MethodName)) { "UnknownMethod" } else { $MethodName }
    
    try {
        & $ScriptBlock
    }
    catch {
        $errorInfo = @{
            ClassName = $component
            MethodName = $context
            ErrorMessage = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
            Timestamp = Get-Date
        }
        
        # Add any additional data
        foreach ($key in $Data.Keys) {
            if (-not $errorInfo.ContainsKey($key)) {
                $errorInfo[$key] = $Data[$key]
            }
        }
        
        if (Get-Command -Name "Write-Log" -ErrorAction SilentlyContinue) {
            Write-Log -Level Error -Message "[$component.$context] $($_.Exception.Message)" -Data $errorInfo
        }
        
        throw
    }
}

# Export the functions
Export-ModuleMember -Function @('Invoke-WithErrorHandling', 'Invoke-ClassMethod')