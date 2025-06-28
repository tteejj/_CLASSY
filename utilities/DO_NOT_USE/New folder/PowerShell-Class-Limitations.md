# Understanding PowerShell Class Limitations
## Why Classes Alone Don't Prevent Errors

### The Reality of PowerShell Classes

PowerShell classes are **not** like C# or Java classes. They provide structure but lack many protective features:

1. **No Built-in Parameter Validation**
   ```powershell
   # This DOES NOT validate automatically:
   class Task {
       [string] $Title
       
       Task([string]$title) {
           $this.Title = $title  # Accepts null, empty, etc.
       }
   }
   ```

2. **No Automatic Null Checking**
   ```powershell
   # This will NOT throw an error:
   $task = [Task]::new($null)  # Title is now null
   $task.Title.Length          # NullReferenceException!
   ```

3. **No Type Constraints on Properties**
   ```powershell
   # User can still break type safety:
   $task = [Task]::new("Valid")
   $task.Title = $null        # PowerShell allows this!
   ```

### What PowerShell Classes DO Provide

1. **Basic Type Definitions**
   - Properties have types
   - Methods have signatures
   - IntelliSense support

2. **Constructor Control**
   - You control object creation
   - Can add validation (manually)

3. **Encapsulation**
   - Hidden members
   - Method-based access

### Making Classes Protective (What We Did)

The enhanced models show how to add protection:

1. **Manual Validation in Constructors**
   ```powershell
   Task([string]$title) {
       if ([string]::IsNullOrWhiteSpace($title)) {
           throw "Title cannot be empty"
       }
       $this.Title = $title
   }
   ```

2. **Setter Methods with Validation**
   ```powershell
   [void] SetTitle([string]$value) {
       if ([string]::IsNullOrWhiteSpace($value)) {
           throw "Title cannot be empty"
       }
       $this.Title = $value
   }
   ```

3. **Validation Base Class**
   ```powershell
   class ValidationBase {
       static [void] ValidateNotNull([object]$value, [string]$name) {
           if ($null -eq $value) {
               throw [System.ArgumentNullException]::new($name)
           }
       }
   }
   ```

### The Parameter Binding Error

Your error "Cannot bind parameter because parameter 'Context' is specified more than once" happens because:

1. **PowerShell's Parameter Binding is Flexible**
   - Allows positional and named parameters
   - Can accidentally duplicate parameters

2. **The Fix**: Ensure single parameter specification
   ```powershell
   # WRONG - Context specified twice:
   Invoke-WithErrorHandling -Component "X" -Context "Y" -Context "Z"
   
   # CORRECT:
   Invoke-WithErrorHandling -Component "X" -Context "Y"
   ```

### Why Navigation Service Failed

The navigation service initialization failed because:

1. **No Automatic Dependency Injection**
   - Services must be manually wired
   - No compile-time checking

2. **Method Existence Not Guaranteed**
   - Dashboard expected GoTo method
   - NavigationService didn't have it initially

### Best Practices for PowerShell Classes

1. **Always Validate in Constructors**
   ```powershell
   ClassName([type]$param) {
       if ($null -eq $param) {
           throw [System.ArgumentNullException]::new("param")
       }
   }
   ```

2. **Use Setter Methods for Complex Properties**
   ```powershell
   hidden [string] $_title
   [string] GetTitle() { return $this._title }
   [void] SetTitle([string]$value) {
       # Validation here
       $this._title = $value
   }
   ```

3. **Implement Validate() Methods**
   ```powershell
   [bool] Validate() {
       # Check all properties
       # Return true/false
   }
   ```

4. **Use Static Factory Methods**
   ```powershell
   static [Task] Create([string]$title) {
       # Validation before creation
       return [Task]::new($title)
   }
   ```

### Areas Still Needing Work

Based on the refactoring guide and current state:

1. **Missing Components**
   - Form input validation components
   - Modal/dialog system
   - Additional screens (6 remaining)

2. **Service Layer Gaps**
   - Input validation service
   - Keyboard shortcut service
   - Theme service

3. **Infrastructure**
   - Global exception handler
   - Retry logic for transient errors
   - Better logging configuration

4. **Testing**
   - Unit tests for all classes
   - Integration tests for services
   - UI automation tests

### Conclusion

PowerShell classes provide **structure**, not **protection**. To get C#-like safety:

1. Add manual validation everywhere
2. Use wrapper methods for property access
3. Implement validation base classes
4. Never trust external input
5. Always check for null

The refactoring is about 70% complete. The remaining 30% involves:
- Implementing missing screens
- Adding form components
- Completing validation layer
- Comprehensive error handling

This will take 2-3 more days of focused development to complete properly.
