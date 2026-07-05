@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

set "GODOT_EXE=C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"
set "AI_SIM_DIR=%PROJECT_ROOT%\.godot\ai_simulation"
set "PROMPT_FILE="
set "LOG_DIR=%PROJECT_ROOT%\logs\godot"
set "LOG_FILE=%LOG_DIR%\godot_ai_simulation.log"
set "RAW_LOG_FILE=%LOG_DIR%\godot_ai_simulation_raw.log"
set "ENGINE_STDERR_LOG=%LOG_DIR%\godot_ai_simulation_engine_stderr.log"
set "RECOMMENDATION_LOG=%LOG_DIR%\godot_ai_audit_recommendation.log"
set "TEST_MODE=0"
set "SHOW_COMMAND=%TD_SIM_SHOW_COMMAND%"
set "RECOMMEND_ONLY=0"
set "USER_ARGS="
set "TIER_NAME=Medium"
set "RUNS_LABEL=420"
set "SCOPE_LABEL=6 waves"
set "SEEDS_LABEL=5"
set "EST_RUNTIME_LABEL=5 min"
set "PURPOSE=normal research"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--test" (
    set "TEST_MODE=1"
) else if /I "%~1"=="--recommend" (
    set "RECOMMEND_ONLY=1"
) else if /I "%~1"=="--show-command" (
    set "SHOW_COMMAND=1"
) else if /I "%~1"=="debug" (
    set "SHOW_COMMAND=1"
) else if /I "%~1"=="smoke" (
    set "USER_ARGS=!USER_ARGS! --runs=14 --max-waves=2 --report-label=strategy_smoke"
    call :set_smoke_display
) else if /I "%~1"=="--smoke" (
    set "USER_ARGS=!USER_ARGS! --runs=14 --max-waves=2 --report-label=strategy_smoke"
    call :set_smoke_display
) else if /I "%~1"=="medium" (
    set "USER_ARGS=!USER_ARGS! medium"
    call :set_medium_display
) else if /I "%~1"=="deep" (
    set "USER_ARGS=!USER_ARGS! deep"
    call :set_deep_display
) else if /I "%~1"=="overnight" (
    set "USER_ARGS=!USER_ARGS! overnight"
    call :set_overnight_display
) else (
    set "USER_ARGS=!USER_ARGS! %1"
    set "TIER_NAME=Custom"
    set "RUNS_LABEL=custom"
    set "SCOPE_LABEL=custom"
    set "SEEDS_LABEL=custom"
    set "EST_RUNTIME_LABEL=custom"
    set "PURPOSE=custom run"
)
shift
goto parse_args

:args_done

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if "%RECOMMEND_ONLY%"=="1" (
    call :show_recommendation
    goto recommend_done
)

if "%TEST_MODE%"=="0" if "!USER_ARGS!"=="" (
    call :choose_profile
    set "PROFILE_RESULT=!ERRORLEVEL!"
    if not "!PROFILE_RESULT!"=="0" (
        if "!PROFILE_RESULT!"=="2" exit /b 0
        exit /b !PROFILE_RESULT!
    )
)

:recommend_done
if "%RECOMMEND_ONLY%"=="1" exit /b 0

echo Tower Defense AI simulation launcher
echo Godot: 4.7 stable
echo.
echo Selected:
echo   Tier: !TIER_NAME!
echo   Runs: !RUNS_LABEL!
echo   Scope: !SCOPE_LABEL!
echo   Seeds: !SEEDS_LABEL!
echo   Estimated runtime: !EST_RUNTIME_LABEL!
echo   Timeout: none; runs until configured runs complete
echo   Purpose: !PURPOSE!
echo.

if not exist "%PROJECT_ROOT%\project.godot" (
    echo ERROR: Wrong project root or launcher location.
    echo Expected Godot project file:
    echo %PROJECT_ROOT%\project.godot
    echo.
    echo Run the repo launcher from:
    echo C:\Users\donny\Desktop\tower_defense_godot\TOWER_DEFENSE_AI_SIMULATION.bat
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

echo Project:
echo   %PROJECT_ROOT%
echo.
echo Logs:
echo   Godot: %LOG_FILE%
echo   Output: .godot\ai_simulation
if /I "!SHOW_COMMAND!"=="1" (
    echo.
    echo Command:
    echo "%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 "--output-dir=res://.godot/ai_simulation" !USER_ARGS!
)
echo.
echo Progress:
echo.

"%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 "--output-dir=res://.godot/ai_simulation" !USER_ARGS! 2> "%ENGINE_STDERR_LOG%"
set "RUN_EXIT=%ERRORLEVEL%"
call :clean_log

if not "%RUN_EXIT%"=="0" (
    echo.
    echo Summary:
    echo   Result: failed with exit code %RUN_EXIT%
    echo   Godot log: %LOG_FILE%
    echo   Raw log: %RAW_LOG_FILE%
    echo   Engine stderr: %ENGINE_STDERR_LOG%
    echo   Command:
    echo   "%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 "--output-dir=res://.godot/ai_simulation" !USER_ARGS!
    if "%TEST_MODE%"=="0" pause
    exit /b %RUN_EXIT%
)

for /f "delims=" %%F in ('dir /b /a-d /o-d "%AI_SIM_DIR%\ai_simulation_codex_prompt_*.md" 2^>nul') do (
    if not defined PROMPT_FILE set "PROMPT_FILE=%AI_SIM_DIR%\%%F"
)

if not defined PROMPT_FILE (
    echo.
    echo ERROR: AI simulation finished, but no timestamped Codex prompt was found under:
    echo %AI_SIM_DIR%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

echo.
echo Summary:
echo   Result: completed
echo   Newest prompt: %PROMPT_FILE%
echo   Godot log: %LOG_FILE%
echo.

if "%TEST_MODE%"=="0" (
    start "" notepad.exe "%PROMPT_FILE%"
    echo Notepad opened for prompt copy.
    echo.
    pause
)

exit /b 0

:choose_profile
echo Tower Defense AI simulation launcher
echo.
call :show_recommendation_if_available
echo.
echo   #  Tier             Est. Runtime    Runs   Scope      Seeds   Purpose
echo   1  Strategy Smoke   5 sec          14     2 waves    1       quick bot check
echo   2  Medium           5 min          420    6 waves    5       normal research
echo   3  Deep             2 hr           2,500  20 waves   8       deeper evidence
echo   4  Overnight        8+ hr          6,000  50 waves   12      full research
echo   5  Cancel
echo.
set "PROFILE_CHOICE="
set /p "PROFILE_CHOICE=Enter 1, 2, 3, 4, or 5, then press Enter: "

if "!PROFILE_CHOICE!"=="5" (
    echo Cancelled.
    exit /b 2
)
if "!PROFILE_CHOICE!"=="4" (
    set "USER_ARGS= overnight"
    call :set_overnight_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="3" (
    set "USER_ARGS= deep"
    call :set_deep_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="2" (
    set "USER_ARGS= medium"
    call :set_medium_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="1" (
    set "USER_ARGS= --runs=14 --max-waves=2 --report-label=strategy_smoke"
    call :set_smoke_display
    exit /b 0
)

echo Invalid choice.
exit /b 2

:set_smoke_display
set "TIER_NAME=Strategy Smoke"
set "RUNS_LABEL=14"
set "SCOPE_LABEL=2 waves"
set "SEEDS_LABEL=1"
set "EST_RUNTIME_LABEL=5 sec"
set "PURPOSE=quick bot check"
exit /b 0

:set_medium_display
set "TIER_NAME=Medium"
set "RUNS_LABEL=420"
set "SCOPE_LABEL=6 waves"
set "SEEDS_LABEL=5"
set "EST_RUNTIME_LABEL=5 min"
set "PURPOSE=normal research"
exit /b 0

:set_deep_display
set "TIER_NAME=Deep"
set "RUNS_LABEL=2,500"
set "SCOPE_LABEL=20 waves"
set "SEEDS_LABEL=8"
set "EST_RUNTIME_LABEL=2 hr"
set "PURPOSE=deeper evidence"
exit /b 0

:set_overnight_display
set "TIER_NAME=Overnight"
set "RUNS_LABEL=6,000"
set "SCOPE_LABEL=50 waves"
set "SEEDS_LABEL=12"
set "EST_RUNTIME_LABEL=8+ hr"
set "PURPOSE=full research"
exit /b 0

:clean_log
if exist "%RAW_LOG_FILE%" (
    findstr /V /C:"ERROR: Failed to read the root certificate store." /C:"at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)" "%RAW_LOG_FILE%" > "%LOG_FILE%"
) else (
    break > "%LOG_FILE%"
)
exit /b 0

:show_recommendation_if_available
if not exist "%PROJECT_ROOT%\TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md" exit /b 0
call :show_recommendation
exit /b 0

:show_recommendation
if not exist "%GODOT_EXE%" (
    echo Current audit recommendation:
    echo   Recommended command args: medium --scenario-probes=auto
    echo   Confidence: low
    echo   Reason: Godot executable was not found, so the report helper could not run.
    exit /b 0
)
if not exist "%PROJECT_ROOT%\scripts\tools\recommend_ai_audit_settings.gd" (
    echo Current audit recommendation:
    echo   Recommended command args: medium --scenario-probes=auto
    echo   Confidence: low
    echo   Reason: Audit recommendation helper was not found.
    exit /b 0
)
"%GODOT_EXE%" --headless --no-header --log-file "%RECOMMENDATION_LOG%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/recommend_ai_audit_settings.gd" 2>nul
if not "%ERRORLEVEL%"=="0" (
    echo Current audit recommendation:
    echo   Recommended command args: medium --scenario-probes=auto
    echo   Confidence: low
    echo   Reason: Audit recommendation helper failed; see %RECOMMENDATION_LOG%.
)
exit /b 0
