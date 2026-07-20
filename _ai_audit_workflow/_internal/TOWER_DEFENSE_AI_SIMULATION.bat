@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "WORKFLOW_INTERNAL=%~dp0"
if "%WORKFLOW_INTERNAL:~-1%"=="\" set "WORKFLOW_INTERNAL=%WORKFLOW_INTERNAL:~0,-1%"
for %%I in ("%WORKFLOW_INTERNAL%\..\..") do set "PROJECT_ROOT=%%~fI"
set "AUDIT_REPORT_FILE=%WORKFLOW_INTERNAL%\TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md"
set "AUDIT_REPORT_RES=res://_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md"

set "GODOT_EXE=C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"
set "AI_SIM_DIR=%PROJECT_ROOT%\.godot\ai_simulation"
set "AI_SIM_DIR_RES=res://.godot/ai_simulation"
set "PROMPT_FILE="
set "LOG_DIR=%PROJECT_ROOT%\logs\godot"
set "LOG_FILE=%LOG_DIR%\godot_ai_simulation.log"
set "RAW_LOG_FILE=%LOG_DIR%\godot_ai_simulation_raw.log"
set "STDOUT_LOG=%LOG_DIR%\godot_ai_simulation_stdout.log"
set "ENGINE_STDERR_LOG=%LOG_DIR%\godot_ai_simulation_engine_stderr.log"
set "RECOMMENDATION_LOG=%LOG_DIR%\godot_ai_audit_recommendation.log"
set "RECOMMENDATION_ARGS_FILE=%LOG_DIR%\godot_ai_audit_recommendation_args.txt"
if defined TD_SIM_LOG_DIR set "LOG_DIR=%TD_SIM_LOG_DIR%"
set "REPORT_JSON_FILE="
set "REPORT_JSON_RES="
set "REPORT_MD_FILE="
set "REPORT_MD_RES="
set "SUMMARY_RUNS=unknown"
set "SUMMARY_ISSUES=unknown"
set "TEST_MODE=0"
set "SHOW_COMMAND=%TD_SIM_SHOW_COMMAND%"
set "RECOMMEND_ONLY=0"
set "FALLBACK_RECOMMENDED_ARGS=--profile=medium --scenario-probes=auto --record=flagged --report-only"
set "RECOMMENDED_ARGS=%FALLBACK_RECOMMENDED_ARGS%"
set "USER_ARGS="
set "TIER_NAME=Medium"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=normal research"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--test" (
    set "TEST_MODE=1"
) else if /I "%~1"=="--recommend" (
    set "RECOMMEND_ONLY=1"
) else if /I "%~1"=="--show-command" (
    set "SHOW_COMMAND=1"
) else if /I "%~1"=="--profile" (
    set "USER_ARGS=!USER_ARGS! --profile=%~2"
    shift
) else if /I "%~1"=="--ai-profile" (
    set "USER_ARGS=!USER_ARGS! --ai-profile=%~2"
    shift
) else if /I "%~1"=="--mode" (
    set "USER_ARGS=!USER_ARGS! --mode=%~2"
    shift
) else if /I "%~1"=="--scenario-probes" (
    set "USER_ARGS=!USER_ARGS! --scenario-probes=%~2"
    shift
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
    set "EXECUTION_LABEL=explicit command overrides"
    set "PURPOSE=custom run"
)
shift
goto parse_args

:args_done

set "OUTPUT_DIR_RES=!AI_SIM_DIR_RES!"
for %%A in (!USER_ARGS!) do (
    set "USER_ARG=%%~A"
    if /I "!USER_ARG:~0,13!"=="--output-dir=" set "OUTPUT_DIR_RES=!USER_ARG:~13!"
)
set "AI_SIM_DIR_RES=!OUTPUT_DIR_RES!"
if /I "!AI_SIM_DIR_RES:~0,6!"=="res://" (
    set "AI_SIM_DIR=%PROJECT_ROOT%\!AI_SIM_DIR_RES:~6!"
    set "AI_SIM_DIR=!AI_SIM_DIR:/=\!"
) else (
    set "AI_SIM_DIR=!AI_SIM_DIR_RES!"
)

set "LOG_FILE=%LOG_DIR%\godot_ai_simulation.log"
set "RAW_LOG_FILE=%LOG_DIR%\godot_ai_simulation_raw.log"
set "STDOUT_LOG=%LOG_DIR%\godot_ai_simulation_stdout.log"
set "ENGINE_STDERR_LOG=%LOG_DIR%\godot_ai_simulation_engine_stderr.log"
set "RECOMMENDATION_LOG=%LOG_DIR%\godot_ai_audit_recommendation.log"
set "RECOMMENDATION_ARGS_FILE=%LOG_DIR%\godot_ai_audit_recommendation_args.txt"
if defined TD_SIM_ENGINE_STDERR_PATH set "ENGINE_STDERR_LOG=%TD_SIM_ENGINE_STDERR_PATH%"

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
echo   Contract: config.json
echo   Execution: !EXECUTION_LABEL!
echo   Purpose: !PURPOSE!
echo.

if not exist "%PROJECT_ROOT%\project.godot" (
    echo ERROR: Wrong project root or launcher location.
    echo Expected Godot project file:
    echo %PROJECT_ROOT%\project.godot
    echo.
    echo Run the repo launcher from:
    echo C:\Users\donny\Desktop\tower_defense_godot\_ai_audit_workflow\_internal\TOWER_DEFENSE_AI_SIMULATION.bat
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
echo   Runner stdout: %STDOUT_LOG%
echo   Output: .godot\ai_simulation
if /I "!SHOW_COMMAND!"=="1" (
    echo.
    echo Command:
    echo "%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 "--output-dir=res://.godot/ai_simulation" !USER_ARGS!
)
echo.
echo Progress:
echo.

"%GODOT_EXE%" --headless --no-header --log-file "%RAW_LOG_FILE%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/run_ai_simulation_batch.gd" -- --seed=12345 "--output-dir=res://.godot/ai_simulation" !USER_ARGS! 1> "%STDOUT_LOG%" 2> "%ENGINE_STDERR_LOG%"
set "RUN_EXIT=%ERRORLEVEL%"
call :clean_log

for /f "tokens=3" %%F in ('findstr /I /C:"Report JSON " "%LOG_FILE%" 2^>nul') do set "REPORT_JSON_RES=%%F"
if defined REPORT_JSON_RES (
    set "REPORT_JSON_FILE=!REPORT_JSON_RES!"
    set "REPORT_JSON_FILE=!REPORT_JSON_FILE:res://=%PROJECT_ROOT%\!"
    set "REPORT_JSON_FILE=!REPORT_JSON_FILE:/=\!"
    for %%F in ("!REPORT_JSON_FILE!") do set "AI_SIM_DIR=%%~dpF"
    set "AI_SIM_DIR=!AI_SIM_DIR:~0,-1!"
    for %%F in ("!REPORT_JSON_FILE!") do set "JSON_BASENAME=%%~nxF"
    set "PACKET_SUFFIX=!JSON_BASENAME:ai_simulation_data_=!"
    set "PACKET_SUFFIX=!PACKET_SUFFIX:.json=!"
    set "REPORT_MD_FILE=!AI_SIM_DIR!\ai_simulation_report_!PACKET_SUFFIX!.md"
    set "REPORT_MD_RES=!REPORT_JSON_RES:ai_simulation_data_=ai_simulation_report_!"
    set "REPORT_MD_RES=!REPORT_MD_RES:.json=.md!"
    set "PROMPT_FILE=!AI_SIM_DIR!\ai_simulation_codex_prompt_!PACKET_SUFFIX!.md"
    set "MANIFEST_FILE=!AI_SIM_DIR!\ai_simulation_manifest_!PACKET_SUFFIX!.json"
)

if not "%RUN_EXIT%"=="0" (
    echo.
    echo Summary:
    echo   Result: failed with exit code %RUN_EXIT%
    echo   Godot log: %LOG_FILE%
    echo   Runner stdout: %STDOUT_LOG%
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
for /f "delims=" %%F in ('dir /b /a-d /o-d "%AI_SIM_DIR%\ai_simulation_data_*.json" 2^>nul') do (
    if not defined REPORT_JSON_FILE (
        set "REPORT_JSON_FILE=%AI_SIM_DIR%\%%F"
        set "REPORT_JSON_RES=!AI_SIM_DIR_RES!/%%F"
    )
)
for /f "delims=" %%F in ('dir /b /a-d /o-d "%AI_SIM_DIR%\ai_simulation_report_*.md" 2^>nul') do (
    if not defined REPORT_MD_FILE (
        set "REPORT_MD_FILE=%AI_SIM_DIR%\%%F"
        set "REPORT_MD_RES=!AI_SIM_DIR_RES!/%%F"
    )
)

if not defined PROMPT_FILE (
    echo.
    echo ERROR: AI simulation finished, but no timestamped Codex prompt was found under:
    echo %AI_SIM_DIR%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)
if not defined REPORT_JSON_FILE (
    echo.
    echo ERROR: AI simulation finished, but no timestamped report JSON was found under:
    echo %AI_SIM_DIR%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)
if not defined REPORT_MD_FILE (
    echo.
    echo ERROR: AI simulation finished, but no timestamped markdown report was found under:
    echo %AI_SIM_DIR%
    if "%TEST_MODE%"=="0" pause
    exit /b 1
)

for %%F in ("%REPORT_JSON_FILE%") do set "JSON_BASENAME=%%~nxF"
set "PACKET_SUFFIX=!JSON_BASENAME:ai_simulation_data_=!"
set "PACKET_SUFFIX=!PACKET_SUFFIX:.json=!"
set "REPORT_MD_FILE=%AI_SIM_DIR%\ai_simulation_report_!PACKET_SUFFIX!.md"
if not defined REPORT_MD_RES set "REPORT_MD_RES=!AI_SIM_DIR_RES!/ai_simulation_report_!PACKET_SUFFIX!.md"
set "PROMPT_FILE=%AI_SIM_DIR%\ai_simulation_codex_prompt_!PACKET_SUFFIX!.md"
set "MANIFEST_FILE=%AI_SIM_DIR%\ai_simulation_manifest_!PACKET_SUFFIX!.json"
if not exist "!REPORT_MD_FILE!" (
    echo ERROR: JSON packet has no matching markdown report for packet !PACKET_SUFFIX!.
    exit /b 1
)
if not exist "!PROMPT_FILE!" (
    echo ERROR: JSON packet has no matching Codex prompt for packet !PACKET_SUFFIX!.
    exit /b 1
)
if not exist "!MANIFEST_FILE!" (
    echo ERROR: JSON packet has no matching manifest for packet !PACKET_SUFFIX!.
    exit /b 1
)

call :load_report_summary

echo.
echo Summary:
echo   Result: completed
echo   Runs: %SUMMARY_RUNS%
echo   Issues: %SUMMARY_ISSUES%
echo   Report JSON: %REPORT_JSON_RES%
echo   Report Markdown: %REPORT_MD_RES%
echo   Codex Prompt: %PROMPT_FILE%
echo   Godot Log: %LOG_FILE%
echo.

if "%TEST_MODE%"=="0" (
    start "" notepad.exe "%PROMPT_FILE%"
    echo Prompt opened in Notepad.
    echo.
    pause
)

exit /b 0

:choose_profile
echo Tower Defense AI simulation launcher
echo.
call :load_recommended_args
echo.
echo Choose a run tier:
echo   #  Profile            Purpose
echo   -----------------------------------------------
echo   0  Recommended         use the current contract recommendation
echo   1  Smoke               bounded report-only sanity check
echo   2  Medium              standard report-only audit
echo   3  Deep                deeper report-only audit
echo   4  Overnight           full report-only audit
echo   5  Cancel              exit launcher
echo.
set "PROFILE_CHOICE="
set /p "PROFILE_CHOICE=Choose a tier [0]: "
if "!PROFILE_CHOICE!"=="" set "PROFILE_CHOICE=0"

if "!PROFILE_CHOICE!"=="5" (
    echo Cancelled.
    exit /b 2
)
if "!PROFILE_CHOICE!"=="4" (
    set "USER_ARGS= --profile=overnight --record=flagged --report-only"
    call :set_overnight_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="3" (
    set "USER_ARGS= --profile=deep --record=flagged --report-only"
    call :set_deep_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="2" (
    set "USER_ARGS= --profile=medium --record=flagged --report-only"
    call :set_medium_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="1" (
    set "USER_ARGS= --profile=smoke --runs=14 --max-waves=2 --report-label=strategy_smoke --record=flagged --report-only"
    call :set_smoke_display
    exit /b 0
)
if "!PROFILE_CHOICE!"=="0" (
    set "USER_ARGS= !RECOMMENDED_ARGS!"
    call :set_recommended_display
    exit /b 0
)

echo Invalid choice.
exit /b 2

:set_recommended_display
set "TIER_NAME=Recommended audit"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=audit recommendation"
exit /b 0

:set_smoke_display
set "TIER_NAME=Smoke"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=quick sanity check"
exit /b 0

:set_medium_display
set "TIER_NAME=Medium"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=normal research"
exit /b 0

:set_deep_display
set "TIER_NAME=Deep"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=deeper evidence"
exit /b 0

:set_overnight_display
set "TIER_NAME=Overnight"
set "EXECUTION_LABEL=canonical profile from config.json"
set "PURPOSE=full research"
exit /b 0

:clean_log
if exist "%RAW_LOG_FILE%" (
    findstr /V /C:"ERROR: Failed to read the root certificate store." /C:"at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)" "%RAW_LOG_FILE%" > "%LOG_FILE%"
) else (
    break > "%LOG_FILE%"
)
exit /b 0

:load_report_summary
for /f "usebackq tokens=1,2 delims=|" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = '%REPORT_JSON_FILE%'; try { $r = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; $runs = $r.summary.total_runs; if ($null -eq $runs) { $runs = $r.runs.Count }; $issues = @($r.issues).Count; Write-Output ('' + $runs + '|' + $issues) } catch { Write-Output 'unknown|unknown' }"`) do (
    set "SUMMARY_RUNS=%%A"
    set "SUMMARY_ISSUES=%%B"
)
exit /b 0

:show_recommendation_if_available
exit /b 0

:load_recommended_args
set "RECOMMENDED_ARGS=%FALLBACK_RECOMMENDED_ARGS%"
exit /b 0

:show_recommendation
if not exist "%GODOT_EXE%" (
    echo Current audit recommendation
    echo   Recommended command args:
    echo     %FALLBACK_RECOMMENDED_ARGS%
    echo   Confidence: low
    echo   Reason:
    echo     Godot executable was not found, so the report helper could not run.
    exit /b 0
)
if not exist "%PROJECT_ROOT%\scripts\tools\recommend_ai_audit_settings.gd" (
    echo Current audit recommendation
    echo   Recommended command args:
    echo     %FALLBACK_RECOMMENDED_ARGS%
    echo   Confidence: low
    echo   Reason:
    echo     Audit recommendation helper was not found.
    exit /b 0
)
"%GODOT_EXE%" --headless --no-header --log-file "%RECOMMENDATION_LOG%" --path "%PROJECT_ROOT%" --script "res://scripts/tools/recommend_ai_audit_settings.gd" -- "--report-path=%AUDIT_REPORT_RES%" 2>nul
if not "%ERRORLEVEL%"=="0" (
    echo Current audit recommendation
    echo   Recommended command args:
    echo     %FALLBACK_RECOMMENDED_ARGS%
    echo   Confidence: low
    echo   Reason:
    echo     Audit recommendation helper failed; see %RECOMMENDATION_LOG%.
)
exit /b 0
