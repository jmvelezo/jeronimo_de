Set-Location $PSScriptRoot\..
flutter config --enable-windows-desktop
flutter create --platforms=windows,web,android .
flutter pub get
