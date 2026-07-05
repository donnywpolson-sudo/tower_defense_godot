@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

set "GODOT_EXE=C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"
set "PROMPT_FILE=%PROJECT_ROOT%\.godot\ai_simulation\latest\ai_simulation_latest_codex_prompt.md"
set "LOG_DIR=%PROJECT_ROOT%\logs\godot"
set "LOG_FILE=%LOG_DIR%\godot_ai_simulation.log"
set "RAW_LOG_FILE=%LOG_DIR%\godot_ai_simulation_raw.log"
set "ENGINE_STDERR_LOG=%LOG_DIR%\godot_ai_simulation_engine_stderr.log"
set "TEST_MODE=0"
set "USER_ARGS="

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--test" (
    set "TEST_MODE=1"
) else if /I "%~1"=="smoke" (
    set "USER_ARGS=!USER_ARGS! --runs=14 --max-waves=2 --report-label=strategy_smoke"
) else if /I "%~1"=="--smoke" (
    set "USER_ARGS=!USER_ARGS! --runs=14 --max-waves=2 --report-label=strategy_smoke"
) else (
    set "USER_ARGS=!USER_ARGS! %1"
)
shift
goto parse_args

:args_done

if "%TEST_MODE%"=="0" if "!USER_ARGS!"=="" (
    call :choose_profile
    if errorlevel 1 exit /b !ERRORLEVEL!
)

echo Running AI simulation prompt generator...
if not "!USER_ARGS!"=="" echo Options:!USER_ARGS!
echo.

if not exist "%PROJECT_ROOT%\project.godot" (
    echo ERROR: Wrong project root or launcher location.
    echo Expected Godot project file:
    echo %PROJECT_ROOT%\project.godot
    echo.
    echo Run the repo launcher from:
    echo C:\Users\donny\Desktop\tower_defense_godot\RUN_AI_SIMULATION_PROMPT.bat
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

if not exist "%PROJECT_ROOT%\scripts\tools\run_ai_simulation_batch.gd" (
    echo ERROR: AI simulation script was not found under the project root.
    echo Expected script:
    echo %PROJECT_ROOT%\scripts\tools\run_ai_simulation_batch.gd
    echo.
    echo This usually means the launcher is pointing at the wrong folder.
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

if not exist "%GODOT_EXE%" (
    echo ERROR: Godot executable was not found:
    echo %GODOT_EXE%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo Progress will print below.
echo Godot log:
echo %LOG_FILE%
echo.

"%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 --output-dir=res://.godot/ai_simulation!USER_ARGS! 2> "%ENGINE_STDERR_LOG%"
set "RUN_EXIT=%ERRORLEVEL%"
call :clean_log

if not "%RUN_EXIT%"=="0" (
    echo.
    echo ERROR: AI simulation failed with exit code %RUN_EXIT%.
    echo Check the logs here:
    echo %LOG_FILE%
    echo %RAW_LOG_FILE%
    echo %ENGINE_STDERR_LOG%
    if "%TEST_MODE%"=="0" pause
    exit /b %RUN_EXIT%
)

if not exist "%PROMPT_FILE%" (
    echo.
    echo ERROR: AI simulation finished, but the Codex prompt was not created:
    echo %PROMPT_FILE%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

echo.
echo YOUR CODEX PROMPT IS HERE:
echo %PROMPT_FILE%
echo.

if "%TEST_MODE%"=="0" (
    start "" notepad.exe "%PROMPT_FILE%"
    echo Notepad opened. Press Ctrl+A, then Ctrl+C, then paste into Codex.
    echo.
    pause
)

exit /b 0

:choose_profile
echo Choose an AI simulation tier:
echo.
echo      Tier             Time       Runs   Waves  Seeds  Purpose
echo      ---------------------------------------------------------------
echo   1. Strategy Smoke   5 sec      14     2      1      quick bot check
echo   2. Medium           5 min      420    6      5      normal research
echo   3. Deep             2 hr       2500   20     8      deeper evidence
echo   4. Overnight        8+ hr      6000   50     12     full research
echo.
echo   5. Cancel
echo.
set "PROFILE_CHOICE="
set /p "PROFILE_CHOICE=Enter 1, 2, 3, 4, or 5, then press Enter: "

if "!PROFILE_CHOICE!"=="5" (
    echo Cancelled.
    exit /b 2
)
if "!PROFILE_CHOICE!"=="4" (
    set "USER_ARGS= overnight"
    exit /b 0
)
if "!PROFILE_CHOICE!"=="3" (
    set "USER_ARGS= deep"
    exit /b 0
)
if "!PROFILE_CHOICE!"=="2" (
    set "USER_ARGS= medium"
    exit /b 0
)
if "!PROFILE_CHOICE!"=="1" (
    set "USER_ARGS= --runs=14 --max-waves=2 --report-label=strategy_smoke"
    exit /b 0
)

echo Invalid choice.
exit /b 2

:clean_log
if exist "%RAW_LOG_FILE%" (
    findstr /V /C:"ERROR: Failed to read the root certificate store." /C:"at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)" "%RAW_LOG_FILE%" > "%LOG_FILE%"
) else (
    break > "%LOG_FILE%"
)
exit /b 0
