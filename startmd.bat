@echo off
echo "check run or release..."
echo.

if "%~1"=="" (
    echo "Release app"
    call flutter build windows --release
    echo.
)
echo "run ..."
start "" "%devprj%\md_viewer\build\windows\x64\runner\Release\md_viewer.exe"
goto :eof