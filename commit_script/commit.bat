@echo off
chcp 65001 >nul
rem add -> commit -> push 를 한 번에 실행한다. (명령 프롬프트 / PowerShell / 탐색기 더블클릭)
rem
rem 사용법
rem   commit_script\commit.bat                      .commit_msg\ 에서 가장 최근 메시지 파일 사용
rem   commit_script\commit.bat 2026-11-04_xxx.txt   메시지 파일 지정
rem
rem 커밋에 쓴 메시지 파일은 .commit_msg\done\ 으로 옮겨서 다시 쓰이지 않게 한다.
setlocal EnableExtensions

rem 어디서 실행해도 프로젝트 루트에서 동작
cd /d "%~dp0.."

set "MSG_DIR=.commit_msg"
set "RC=0"
set "MSG="

if not "%~1"=="" (
  if exist "%MSG_DIR%\%~1" (
    set "MSG=%MSG_DIR%\%~1"
  ) else (
    set "MSG=%~1"
  )
) else (
  for /f "delims=" %%F in ('dir /b /a-d /o-d "%MSG_DIR%\*.txt" 2^>nul') do (
    if not defined MSG set "MSG=%MSG_DIR%\%%F"
  )
)

if not defined MSG goto no_msg
if not exist "%MSG%" goto no_msg

git add -A
if errorlevel 1 goto fail

git diff --cached --quiet
if not errorlevel 1 (
  echo 커밋할 변경사항이 없어요.
  goto end
)

set "TITLE="
set /p TITLE=<"%MSG%"
echo 메시지 파일: %MSG%
echo    제목: %TITLE%

git commit -F "%MSG%"
if errorlevel 1 goto fail

if not exist "%MSG_DIR%\done" mkdir "%MSG_DIR%\done"
move /y "%MSG%" "%MSG_DIR%\done\" >nul

git push
if errorlevel 1 goto fail

echo add / commit / push 완료
goto end

:no_msg
echo 커밋 메시지 파일이 없어요. %MSG_DIR%\ 에 .txt 파일을 만들어 주세요.
set "RC=1"
goto end

:fail
echo 실패했어요. 위 git 메시지를 확인해 주세요.
set "RC=1"

:end
rem 탐색기에서 더블클릭으로 실행한 경우 창이 바로 닫히지 않게 한다.
setlocal EnableDelayedExpansion
if /i not "!CMDCMDLINE:/c=!"=="!CMDCMDLINE!" pause
endlocal
endlocal & exit /b %RC%
