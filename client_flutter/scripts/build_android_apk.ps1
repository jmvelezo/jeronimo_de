Set-Location $PSScriptRoot\..
if (!(Test-Path android)) { flutter create --platforms=android . }
flutter pub get
flutter build apk --release
