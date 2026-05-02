Set-Location $PSScriptRoot\..
if (!(Test-Path web)) { flutter create --platforms=web . }
flutter pub get
flutter build web --release
