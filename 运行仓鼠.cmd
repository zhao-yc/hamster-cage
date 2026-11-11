@echo off
setlocal
set "APPDATA=%~dp0dist\desktop-profile"
if not exist "%APPDATA%" mkdir "%APPDATA%"
start "" "%~dp0dist\tools\godot\Godot_v4.5.1-stable_win64.exe" --path "%~dp0." --position 120,100 --resolution 1280x800 --log-file "%~dp0dist\desktop-preview-1.5.1.log"
endlocal
