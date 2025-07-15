# AutoUpdater API Client PowerShell Script
# Generated from OpenAPI specification

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Command,
    
    [Parameter(Position=1)]
    [string]$PackageName,
    
    [string]$BaseUrl = $env:AUTOUPDATER_BASE_URL ?? "http://localhost:8080",
    
    [switch]$Debug
)

# Global configuration
$script:AutoUpdaterApiBase = "$BaseUrl/api"
$script:DebugMode = $Debug -or ($env:AUTOUPDATER_DEBUG -eq "true")

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Debug {
    param([string]$Message)
    if ($script:DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Blue
    }
}

# Help function
function Show-Help {
    Write-Host @"
AutoUpdater API Client

USAGE:
    .\autoupdater.ps1 <command> [options]

COMMANDS:
    health                      Check AutoUpdater health
    packages                    List all configured packages
    status <package>            Get upgrade status for a package
    update <package>            Trigger update for a specific package
    update-all                  Trigger updates for all packages
    debug                       Test API connectivity

PARAMETERS:
    -BaseUrl <url>             Base URL for AutoUpdater (default: http://localhost:8080)
    -Debug                     Enable debug output

EXAMPLES:
    .\autoupdater.ps1 health
    .\autoupdater.ps1 packages
    .\autoupdater.ps1 status rocket-welder
    .\autoupdater.ps1 update rocket-welder
    .\autoupdater.ps1 update-all

ENVIRONMENT VARIABLES:
    AUTOUPDATER_BASE_URL       Base URL for AutoUpdater
    AUTOUPDATER_DEBUG          Enable debug output (true/false)

"@
}

# API call wrapper
function Invoke-AutoUpdaterApi {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null
    )
    
    $url = "$script:AutoUpdaterApiBase$Endpoint"
    Write-Debug "Making $Method request to: $url"
    
    $headers = @{
        'Accept' = 'application/json'
    }
    
    $splat = @{
        Uri = $url
        Method = $Method
        Headers = $headers
        UseBasicParsing = $true
    }
    
    if ($Method -eq "POST" -and $Body) {
        $splat.Body = $Body | ConvertTo-Json
        $headers['Content-Type'] = 'application/json'
    }
    
    try {
        $response = Invoke-WebRequest @splat
        Write-Debug "HTTP Status: $($response.StatusCode)"
        Write-Debug "Response: $($response.Content)"
        
        if ($response.Content) {
            try {
                $response.Content | ConvertFrom-Json
            } catch {
                $response.Content
            }
        }
        return $true
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Debug "HTTP Status: $statusCode"
        
        if ($statusCode -eq 404) {
            Write-Error "Package not found"
        }
        else {
            Write-Error "API call failed with status $statusCode"
            if ($_.Exception.Response) {
                try {
                    $errorContent = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorContent)
                    $errorText = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $errorJson = $errorText | ConvertFrom-Json
                    Write-Host ($errorJson.title ?? $errorJson.error ?? $errorText)
                } catch {
                    Write-Host $_.Exception.Message
                }
            }
        }
        return $false
    }
}

# Command implementations
function Invoke-HealthCheck {
    Write-Info "Checking AutoUpdater health..."
    if (Invoke-AutoUpdaterApi -Endpoint "/health") {
        Write-Info "AutoUpdater is healthy"
    }
    else {
        Write-Error "Health check failed"
        exit 1
    }
}

function Get-Packages {
    Write-Info "Getting configured packages..."
    Invoke-AutoUpdaterApi -Endpoint "/packages"
}

function Get-UpgradeStatus {
    param([string]$PackageName)
    
    if (-not $PackageName) {
        Write-Error "Package name is required"
        Write-Host "Usage: .\autoupdater.ps1 status <package-name>"
        exit 1
    }
    
    Write-Info "Getting upgrade status for package: $PackageName"
    Invoke-AutoUpdaterApi -Endpoint "/upgrades/$PackageName"
}

function Start-PackageUpdate {
    param([string]$PackageName)
    
    if (-not $PackageName) {
        Write-Error "Package name is required"
        Write-Host "Usage: .\autoupdater.ps1 update <package-name>"
        exit 1
    }
    
    Write-Info "Triggering update for package: $PackageName"
    Invoke-AutoUpdaterApi -Method POST -Endpoint "/update/$PackageName"
}

function Start-AllUpdates {
    Write-Info "Triggering updates for all packages..."
    Invoke-AutoUpdaterApi -Method POST -Endpoint "/update-all"
}

function Test-ApiConnectivity {
    Write-Info "Testing API connectivity..."
    if (Invoke-AutoUpdaterApi -Endpoint "/debug") {
        Write-Info "API connectivity test successful"
    }
    else {
        Write-Error "API connectivity test failed"
        exit 1
    }
}

# Main command dispatcher
switch ($Command.ToLower()) {
    "health" { 
        Invoke-HealthCheck 
    }
    "packages" { 
        Get-Packages 
    }
    "status" { 
        Get-UpgradeStatus -PackageName $PackageName 
    }
    "update" { 
        Start-PackageUpdate -PackageName $PackageName 
    }
    "update-all" { 
        Start-AllUpdates 
    }
    "debug" { 
        Test-ApiConnectivity 
    }
    "help" { 
        Show-Help 
    }
    default {
        Write-Error "Unknown command: $Command"
        Show-Help
        exit 1
    }
}