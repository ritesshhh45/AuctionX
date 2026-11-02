@echo off
REM Builds the web app and publishes it to Vercel (run from the project folder).
call flutter build web --release
if errorlevel 1 exit /b 1
copy /Y web_deploy\vercel.json build\web\vercel.json
cd build\web
call vercel deploy --prod
