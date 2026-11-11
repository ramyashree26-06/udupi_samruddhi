# Adds the Android part to this project (run once) and builds the APK.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

flutter create --platforms=android --org com.udupisamruddhi --project-name hotel_billing .
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }

# app icon (your logo)
Copy-Item -Recurse -Force 'android_extras\res\*' 'android\app\src\main\res\'

# app name and permission to reach a Wi-Fi printer
$f = 'android\app\src\main\AndroidManifest.xml'
$t = Get-Content $f -Raw
$t = $t -replace 'android:label="[^"]*"', 'android:label="Udupi Samruddhi"'
if ($t -notmatch 'android.permission.INTERNET') {
  $t = $t -replace '<application', ('<uses-permission android:name="android.permission.INTERNET"/>' + "`r`n    " + '<application')
}
if ($t -notmatch 'usb.host') {
  $t = $t -replace '<application', ('<uses-feature android:name="android.hardware.usb.host" android:required="false"/>' + "`r`n    " + '<application')
}
Set-Content -Path $f -Value $t -Encoding UTF8

# USB printer code
$k = 'android\app\src\main\kotlin\com\udupisamruddhi\hotel_billing'
New-Item -ItemType Directory -Force $k | Out-Null
Copy-Item -Force 'android_extras\MainActivity.kt' "$k\MainActivity.kt"

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

Copy-Item -Force 'build\app\outputs\flutter-apk\app-release.apk' 'Hotel_Billing.apk'
Write-Host ''
Write-Host 'DONE. Your app file is: Hotel_Billing.apk (in this folder)'
