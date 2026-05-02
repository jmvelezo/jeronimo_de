Set-Location $PSScriptRoot\..
flutter config --enable-windows-desktop
if (!(Test-Path windows)) { flutter create --platforms=windows . }
flutter pub get
flutter build windows --release
