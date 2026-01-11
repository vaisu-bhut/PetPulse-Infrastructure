# Test-PetPulse.ps1
# Requires: curl (installed in PowerShell 7+ or aliased)
$BaseUrl = "http://localhost:3000"
$Username = "Test User " + (Get-Random)
$Email = "testuser" + (Get-Random) + "@example.com"
$Password = "password123"
$CookieJar = New-TemporaryFile

Write-Host "1. Registering user $Email..." -ForegroundColor Cyan
$RegBody = @{
    name = $Username
    email = $Email
    password = $Password
} | ConvertTo-Json

Invoke-RestMethod -Uri "$BaseUrl/register" -Method Post -Body $RegBody -ContentType "application/json"
Write-Host "   Registered." -ForegroundColor Green

Write-Host "2. Logging in..." -ForegroundColor Cyan
# store cookies in session variable for subsequent requests
$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$LoginBody = @{
    email = $Email
    password = $Password
} | ConvertTo-Json

try {
    Invoke-WebRequest -Uri "$BaseUrl/login" -Method Post -Body $LoginBody -ContentType "application/json" -WebSession $Session -UseBasicParsing | Out-Null
    Write-Host "   Logged in. Cookie captured." -ForegroundColor Green
} catch {
    Write-Error "Login failed: $_"
    exit 1
}

Write-Host "3. Creating Pet..." -ForegroundColor Cyan
$PetBody = @{
    name = "TestDog"
    species = "Dog"
    age = 5
    breed = "Labrador"
    bio = "Good boy"
} | ConvertTo-Json

try {
    $PetResponse = Invoke-RestMethod -Uri "$BaseUrl/pets" -Method Post -Body $PetBody -ContentType "application/json" -WebSession $Session
    $PetId = $PetResponse.id
    Write-Host "   Pet Created. ID: $PetId" -ForegroundColor Green
} catch {
    Write-Error "Create Pet failed: $_"
    exit 1
}

Write-Host "4. Uploading Multiple Videos (Queue Check)..." -ForegroundColor Cyan
# Create dummy file
$DummyFile = "dummy.mp4"
Set-Content -Path $DummyFile -Value "fake video content"

try {
    $UploadUrl = "$BaseUrl/pets/$PetId/upload_video"
    $BaseUri = New-Object System.Uri($BaseUrl)
    
    for ($i=1; $i -le 3; $i++) {
        # Using curl.exe for reliable multipart upload
        # Construct cookie string
        $CookieString = ""
        foreach ($cookie in $Session.Cookies.GetCookies($BaseUri)) {
            $CookieString += "$($cookie.Name)=$($cookie.Value); "
        }

        # curl.exe handles multipart/form-data via -F
        $CurlOutput = & curl.exe -s -X POST $UploadUrl -H "Cookie: $CookieString" -F "video=@$DummyFile"
        
        # Parse JSON output from curl
        try {
            $UploadResponse = $CurlOutput | ConvertFrom-Json
            $VideoId = $UploadResponse.video_id
            $Status = $UploadResponse.status
            Write-Host "   [$i/3] Video Uploaded. Status: $Status. ID: $VideoId" -ForegroundColor Green
        } catch {
             Write-Host "   [$i/3] Upload Failed (Parse Error). Output: $CurlOutput" -ForegroundColor Red
        }

        Start-Sleep -Milliseconds 500
    }

} catch {
    Write-Error "Upload failed: $_"
    exit 1
} finally {
    Remove-Item $DummyFile -ErrorAction SilentlyContinue
}

Write-Host "5. Verifying Worker Processing (Polling)..." -ForegroundColor Cyan
# We don't have a direct "get video status" endpoint exposed in the summary, 
# so we will check if the Daily Digest gets created or simply wait and assume success if no error in logs.
# NOTE: The worker updates `pet_video` status. But we might not have a public GET /videos/:id endpoint.
# Let's check the logs or just wait.

Start-Sleep -Seconds 5
Write-Host "   Waited 5 seconds. If worker is running, it should be processed." -ForegroundColor Yellow

# Ideally we fetch the digest
# Let's try to fetch user info to confirm session is still alive
$User = Invoke-RestMethod -Uri "$BaseUrl/users" -Method Get -WebSession $Session
Write-Host "   User Session Valid: $($User.username)" -ForegroundColor Green

Write-Host "Test Complete. Check Docker logs for 'Analysis successful'." -ForegroundColor Magenta
