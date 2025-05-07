# Set Dell API Information
$dellApi = "<dell_api_key>"
$dellSecret = "dell_secret_key"
$dellOAuth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${dellApi}:${dellSecret}"))
$dellAuthUrl = "https://apigtwb2c.us.dell.com/auth/oauth/v2/token"
$dellApiUrl = "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements"

# Set Datto RMM Keys
$dattoRmmKey = "<datto_rmm_key>"
$dattoRmmPrivKey = "<datto_rmm_priv_key>"
$filePath = "C:\path\to\your\file"  # Adjust to your file location

# Fetch Dell OAuth Token
Write-Host "Fetching Dell OAuth token..."
$dellResponse = Invoke-RestMethod -Method Post -Uri $dellAuthUrl -Headers @{
    Authorization = "Basic $dellOAuth"
} -Body @{
    grant_type = "client_credentials"
}
$dellToken = $dellResponse.access_token
if (-not $dellToken) {
    Write-Error "Error: Failed to retrieve Dell OAuth token"
    exit 1
}

# Fetch Datto RMM Token
# Datto RMM API Token Retrieval
Write-Host "Fetching Datto RMM token..."

# Set headers
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("public-client:public"))
    "Content-Type"  = "application/x-www-form-urlencoded"
}

# Set form data
$body = @{
    "grant_type" = "password"
    "username"   = $dattoRmmKey
    "password"   = $dattoRmmPrivKey
}

# Invoke the API request
try {
    $dattoResponse = Invoke-RestMethod -Method Post -Uri "https://vidal-api.centrastage.net/auth/oauth/token" -Headers $headers -Body $body
    $dattoToken = $dattoResponse.access_token

    if (-not $dattoToken) {
        throw "Datto token is null or missing"
    }

    Write-Host "Datto RMM token retrieved successfully."
} catch {
    Write-Error "Error retrieving Datto RMM token: $_"
    exit 1
}

# Read UUIDs from File
if (-not (Test-Path $filePath)) {
    Write-Error "Error: UUID file not found at $filePath"
    exit 1
}
$uuids = Get-Content $filePath
$totalCount = $uuids.Count
$currentCount = 0

# Process Each UUID
foreach ($uuid in $uuids) {
    $currentCount++
    $progressPercent = [math]::Round(($currentCount / $totalCount) * 100)

    # Update Progress Bar
    Write-Progress -Activity "Processing UUIDs" -Status "Processing $currentCount of $totalCount" -PercentComplete $progressPercent

    # Fetch Device Info from Datto RMM
    $deviceUrl = "https://vidal-api.centrastage.net/api/v2/audit/device/$uuid"
    $deviceResponse = Invoke-RestMethod -Method Get -Uri $deviceUrl -Headers @{
        Authorization = "Bearer $dattoToken"
        "Content-Type" = "application/json"
    }
    $serialNumber = $deviceResponse.bios.serialNumber

    # Fetch Dell Asset Entitlement
    $dellUrl = $dellApiUrl + "?servicetags=" + $serialNumber + "&Method=GET"
    $dellResponse = Invoke-RestMethod -Method Get -Uri $dellUrl -Headers @{
        Authorization = "Bearer $dellToken"
        Accept = "application/json"
    }

    if (-not $dellResponse) {
        Write-Warning "Error: Empty response from Dell API for Serial Number: $serialNumber"
        continue
    }

    $shipDate = $dellResponse[0].shipDate
    $supportEndDate = $dellResponse[0].entitlements | Select-Object -ExpandProperty endDate | Select-Object -Last 1
    $formattedDate = ($supportEndDate -split "T")[0]

    # Output Results
    Write-Host "Serial Number: $serialNumber, UUID: $uuid, Warranty End Date: $formattedDate"

    # Update Warranty in Datto RMM
    $warrantyUrl = "https://vidal-api.centrastage.net/api/v2/device/$uuid/warranty"
    $dattoheaders = @{
        "Authorization" = "Bearer $dattoToken"
        "Content-Type" = "application/json"
    }
    
    $dattobody = @{
        "warrantyDate" = $formattedDate
    } | ConvertTo-Json

    $warrantyResponse = Invoke-RestMethod -Method Post -Uri $warrantyUrl -Headers $dattoheaders -Body $dattobody 
    
    # Simulate Delay (Optional)
    Start-Sleep -Seconds 2
}

# Completion Message
Write-Host "Processing completed successfully!"
