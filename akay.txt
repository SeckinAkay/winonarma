@echo off
:: https://akayseckin.blogspot.com/
:: www.youtube.com/@akayseckin
:: https://github.com/SeckinAkay/winonarma
:: Flash diskin çalıştığı ana dizine geçiş yap bu kodu oynamayın, otomatik flasdiski bulur
cd /d "%~dp0"

:: PowerShell dosyanızın adı (Tırnak işaretlerini set komutunun dışına aldık)
set ScriptName=akay01.ps1

:: Yönetici yetkilerini kontrol et
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunScript
) else (
    goto :UACPrompt
)

:UACPrompt
    echo Yonetici yetkileri aliniyor...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b

:RunScript
    echo PowerShell betigi baypas modunda calistiriliyor...
    
    :: Yoldaki tırnak işaretlerini temizleyerek PowerShell'e gönderiyoruz
    powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0%ScriptName%"
    
    echo Islem bitti.
    pause
