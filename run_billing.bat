@echo off
title Udupi Samruddhi Billing
cd /d "%USERPROFILE%\Documents\hotel_billing" || (echo Folder hotel_billing not found & pause & exit /b)
call flutter pub get
call flutter run -d windows
pause
