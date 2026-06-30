@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM Binaries (exes + DLLs) live in this subfolder so the script
REM directory stays clean (only this .bat + README at the root).
set "BIN_DIR=bin"

echo.
echo ================================================
echo   SPIM Registration + h5 Compression - Batch
echo ================================================
echo.

REM ============================================================
REM Defaults (edit these to match your environment)
REM ============================================================
set "SERVER_IND=81"
set "EXT_REF=0"
set "RDIR=."
set "MPI_CORES=64"

REM ============================================================
REM Step 0: Select server (first prompt)
REM The chosen index is passed to Process_SPIM.exe as server_ind.
REM ============================================================
:ask_server
echo --------------------------------------------
echo  Select server (server index for Process_SPIM)
echo   1) .6   (index 6)
echo   2) .7   (index 7)
echo   3) .81  (index 81)   [default]
echo --------------------------------------------
set "SRV_CHOICE="
set /p SRV_CHOICE="Enter choice [3]: "
if "!SRV_CHOICE!"=="" set "SRV_CHOICE=3"
if "!SRV_CHOICE!"=="1" (
    set "SERVER_IND=6"
) else if "!SRV_CHOICE!"=="2" (
    set "SERVER_IND=7"
) else if "!SRV_CHOICE!"=="3" (
    set "SERVER_IND=81"
) else (
    echo [ERROR] Invalid choice. Please enter 1-3.
    echo.
    goto ask_server
)
echo Using server index: !SERVER_IND!
echo.

REM ============================================================
REM Check prerequisites (executables live in %BIN_DIR%)
REM ============================================================
if not exist "%BIN_DIR%\Process_SPIM.exe" (
    echo [ERROR] Process_SPIM.exe not found in: %~dp0%BIN_DIR%
    echo Place Process_SPIM.exe and its DLLs in the %BIN_DIR% subfolder.
    pause
    exit /b 1
)
if not exist "%BIN_DIR%\stack2h5_v2.exe" (
    echo [ERROR] stack2h5_v2.exe not found in: %~dp0%BIN_DIR%
    pause
    exit /b 1
)
if not exist "%BIN_DIR%\mpiexec.exe" (
    echo [ERROR] mpiexec.exe not found in: %~dp0%BIN_DIR%
    pause
    exit /b 1
)

REM ============================================================
REM Find source directories (ending with "raw", containing .stack)
REM ============================================================
set "COUNT=0"
for /f "delims=" %%d in ('dir /s /b /ad "data\*raw" 2^>nul') do (
    if exist "%%d\*.stack" (
        set /a COUNT+=1
        set "RAW_!COUNT!=%%d"
    )
)

if !COUNT! EQU 0 (
    echo [ERROR] No directory ending with "raw" found in data\.
    if exist "data\" (
        echo Current:
        dir /b /ad "data\*"
        echo   Make sure your datasets are in subfolders of data\ and that each dataset folder ends with "raw".
    ) else (
        echo   The data\ folder does not exist. Create it and place your datasets inside.
    )
    pause
    exit /b 1
)

REM ============================================================
REM Ask user to confirm each dataset one by one
REM (shows full detected configuration for each)
REM ============================================================
echo Found !COUNT! raw director(y/ies) with .stack files:
echo.

set "SELECTED=0"
for /l %%i in (1,1,!COUNT!) do (
    call :preview_and_ask "!RAW_%%i!" %%i !COUNT!
    if "!INC_RESULT!"=="1" (
        set /a SELECTED+=1
        set "SEL_!SELECTED!=!RAW_%%i!"
        set "SEL_PREFIX_!SELECTED!=!PV_PREFIX!"
        set "SEL_DIGITS_!SELECTED!=!PV_DIGITS!"
        set "SEL_CAM_!SELECTED!=!PV_CAM!"
        set "SEL_MIN_!SELECTED!=!PV_MIN!"
        set "SEL_MAX_!SELECTED!=!PV_MAX!"
        echo   [ADDED]
    ) else (
        echo   [SKIPPED]
    )
    echo.
)

if !SELECTED! EQU 0 (
    echo No datasets selected. Exiting.
    pause
    exit /b 0
)

REM ============================================================
REM Select processing mode (after datasets are confirmed)
REM ============================================================
:ask_mode
echo --------------------------------------------
echo  What should be done with the selected datasets?
echo   1) Registration only   (raw -^> registered)
echo   2) Compression only    (raw -^> h5)
echo   3) Both                (registration then compression)  [default]
echo --------------------------------------------
set "MODE_CHOICE="
set /p MODE_CHOICE="Enter choice [3]: "
if "!MODE_CHOICE!"=="" set "MODE_CHOICE=3"
set "DO_REG=0"
set "DO_COMPRESS=0"
if "!MODE_CHOICE!"=="1" (
    set "DO_REG=1"
) else if "!MODE_CHOICE!"=="2" (
    set "DO_COMPRESS=1"
) else if "!MODE_CHOICE!"=="3" (
    set "DO_REG=1"
    set "DO_COMPRESS=1"
) else (
    echo [ERROR] Invalid choice. Please enter 1-3.
    echo.
    goto ask_mode
)
set "MODE_LABEL="
if "!DO_REG!"=="1" if "!DO_COMPRESS!"=="1" set "MODE_LABEL=Both (registration + compression)"
if "!DO_REG!"=="1" if not "!DO_COMPRESS!"=="1" set "MODE_LABEL=Registration only"
if not "!DO_REG!"=="1" if "!DO_COMPRESS!"=="1" set "MODE_LABEL=Compression only"
echo Mode: !MODE_LABEL!
echo.

REM ============================================================
REM Confirm MPI core count (only relevant when compressing)
REM ============================================================
echo ================================================
echo   Summary
echo ================================================
echo   Datasets to process: !SELECTED!
if "!DO_COMPRESS!"=="1" (
    echo   MPI cores for h5 compression: !MPI_CORES!
) else (
    echo   MPI cores: not used (registration only)
)
echo ================================================
echo.
if "!DO_COMPRESS!"=="1" (
    set "ADJUST="
    set /p ADJUST="Adjust MPI cores? Enter new value or press Enter to keep [!MPI_CORES!]: "
    if not "!ADJUST!"=="" set "MPI_CORES=!ADJUST!"
    echo.
    echo Using !MPI_CORES! MPI cores for compression.
    echo.
)

REM ============================================================
REM Process each selected dataset in serial
REM ============================================================
for /l %%s in (1,1,!SELECTED!) do (
    call :process_dataset "!SEL_%%s!" %%s !SELECTED!
)

echo.
echo ================================================
echo   All datasets processed. Logs saved in %~dp0logs\.
echo   Please manually verify the registration and/or compression results.
echo   Then you may proceed cell segmentation with MATLAB codes.
echo ================================================
echo.
pause
exit /b 0

REM ============================================================
REM === SUBROUTINES ===
REM ============================================================

REM === preview_and_ask: analyze one dataset, show info, ask Y/n ===
REM Args: %1 = source dir, %2 = current index, %3 = total count
REM Sets INC_RESULT = 1 (include) or 0 (skip)
:preview_and_ask
set "PV_SRC=%~1"
set "PV_IDX=%~2"
set "PV_TOT=%~3"

echo ================================================
echo   [%PV_IDX%/%PV_TOT%] !PV_SRC!
echo ================================================

REM ---- Quick analysis of .stack files ----
set "PV_FIRST=1"
for %%f in ("!PV_SRC!\*.stack") do (
    if !PV_FIRST! EQU 1 (
        set "PV_SAMPLE=%%~nxf"
        set "PV_FIRST=0"
    )
)

for /f "tokens=1-3 delims=_" %%a in ("!PV_SAMPLE!") do (
    set "PV_PART_A=%%a"
    set "PV_PART_B=%%b"
)

set "PV_CAM=!PV_PART_B:~2,1!"
call :parse_frame_part "!PV_PART_A!" PV_PREFIX PV_DIGITS

REM Clear frame numbers (defense against pollution from previous calls)
set "PV_MIN="
set "PV_MAX="

REM Find min / max frame via dir sort (first item only, constant time)
REM No goto — would corrupt call stack inside call :preview_and_ask
set "PV_MIN_FILE="
set "PV_MAX_FILE="
for /f "delims=" %%a in ('dir /b /on "!PV_SRC!\*_CM!PV_CAM!_CHN00.stack" 2^>nul') do if not defined PV_MIN_FILE (
    set "PV_MIN_FILE=%%a"
)
for /f "delims=" %%a in ('dir /b /o-n "!PV_SRC!\*_CM!PV_CAM!_CHN00.stack" 2^>nul') do if not defined PV_MAX_FILE (
    set "PV_MAX_FILE=%%a"
)

REM Parse frame strings from those two filenames
for /f "tokens=1 delims=_" %%a in ("!PV_MIN_FILE!") do set "PV_FULL=%%a"
set "PV_FSTR=!PV_FULL:%PV_PREFIX%=!"
call :str2num "!PV_FSTR!" PV_MIN

for /f "tokens=1 delims=_" %%a in ("!PV_MAX_FILE!") do set "PV_FULL=%%a"
set "PV_FSTR=!PV_FULL:%PV_PREFIX%=!"
call :str2num "!PV_FSTR!" PV_MAX

REM Display detected config
echo   Sample:      !PV_SAMPLE!
echo   Prefix:      !PV_PREFIX!
echo   Digits:      !PV_DIGITS!
echo   Camera:      !PV_CAM!
echo   Frame range: !PV_MIN! - !PV_MAX!
echo   Reg dir:     !PV_SRC:raw=registered!
echo   H5 dir:      !PV_SRC:raw=h5!
echo.

set "PV_INC="
set /p PV_INC="  Include this dataset? [Y/n]: "
if /i "!PV_INC!"=="N" (
    set "INC_RESULT=0"
) else (
    set "INC_RESULT=1"
)
goto :eof

REM === process_dataset: run SPIM and/or h5 compression for one dataset ===
REM Args: %1 = source dir, %2 = current index, %3 = total count
REM Honors global DO_REG / DO_COMPRESS flags set by the mode prompt.
:process_dataset
set "SRC_DIR=%~1"
set "DS_IDX=%~2"
set "DS_TOT=%~3"

REM ---- Clear per-dataset state (no pollution from previous run) ----
set "PREFIX="
set "NAME_DIGIT="
set "CAM_NUM="
set "MIN_FRAME="
set "MAX_FRAME="
set "REF_FRAME="
set "TGT_DIR="
set "H5_DIR="
set "SPIM_EXIT="
set "H5_EXIT="
set "STEP_N="
set "STEPS="
set "STACK_COUNT="
set "EXPECTED_COUNT="
set "SKIP_DATASET="
set "EFF_CORES="

echo.
echo ##################################################
echo   [%DS_IDX%/%DS_TOT%] Processing: !SRC_DIR!
echo ##################################################
echo.

REM ---- Restore values computed during preview (no re-analysis) ----
call set "PREFIX=%%SEL_PREFIX_!DS_IDX!%%"
call set "NAME_DIGIT=%%SEL_DIGITS_!DS_IDX!%%"
call set "CAM_NUM=%%SEL_CAM_!DS_IDX!%%"
call set "MIN_FRAME=%%SEL_MIN_!DS_IDX!%%"
call set "MAX_FRAME=%%SEL_MAX_!DS_IDX!%%"

REM Derive reference frame (middle of range)
set /a REF_FRAME=(!MIN_FRAME! + !MAX_FRAME!) / 2

REM ---- Compute target directories ----
set "TGT_DIR=!SRC_DIR:raw=registered!"
set "H5_DIR=!SRC_DIR:raw=h5!"

REM ---- Total steps for this dataset (for [Step n/m] labels) ----
set "STEPS=0"
if "!DO_REG!"=="1" set /a STEPS+=1
if "!DO_COMPRESS!"=="1" set /a STEPS+=1
set "STEP_N=0"

REM ---- Display (all values confirmed during preview) ----
echo   Prefix:      !PREFIX!
echo   Digits:      !NAME_DIGIT!
echo   Camera:      !CAM_NUM!
echo   Frame range: !MIN_FRAME! - !MAX_FRAME!
echo   Ref frame:   !REF_FRAME!  (middle)
echo.
echo   Source dir:  !SRC_DIR!
if "!DO_REG!"=="1" echo   Regist dir:  !TGT_DIR!
if "!DO_COMPRESS!"=="1" echo   H5 dir:      !H5_DIR!
echo.

REM ============================================================
REM Pre-flight: count .stack files, warn if incomplete
REM ============================================================
REM Simple for-loop counter — locale-independent (do not use find /c /v).
set "STACK_COUNT=0"
for %%f in ("!SRC_DIR!\*_CM!CAM_NUM!_CHN00.stack") do set /a STACK_COUNT+=1
set /a EXPECTED_COUNT=!MAX_FRAME! - !MIN_FRAME! + 1

if !STACK_COUNT! NEQ !EXPECTED_COUNT! (
    echo  [SKIP] Stack count mismatch for camera !CAM_NUM!:
    echo    Expected: !EXPECTED_COUNT!  (frames !MIN_FRAME! - !MAX_FRAME!)
    echo    Found:    !STACK_COUNT!  (missing frames will cause tool errors)
    echo    Skipping dataset: !SRC_DIR!
    echo.
    set "STACK_MISMATCH=YES"
    set "SKIP_DATASET=1"
) else (
    echo   Stack count OK: !STACK_COUNT! files for camera !CAM_NUM!.
    echo.
    set "STACK_MISMATCH=NO"
    set "SKIP_DATASET=0"
)

REM ============================================================
REM Step A: Run Process_SPIM.exe (registration)
REM ============================================================
if "!DO_REG!"=="1" if "!SKIP_DATASET!" == "1" (
    set /a STEP_N+=1

    if not exist "!TGT_DIR!" (
        mkdir "!TGT_DIR!"
        echo Created: !TGT_DIR!
        echo.
    )

    set "INPUTFILE=%TEMP%\spim_input_%RANDOM%.txt"

    REM Input order (matching kernel2.cu main()):
    REM   getline: sdir, tdir, rdir
    REM   cin >>:  server_ind, name_digit, cam_num, mintime, maxtime, extRef
    REM   if !extRef -> cin >> reftime
    (
        echo !SRC_DIR!
        echo !TGT_DIR!
        echo !RDIR!
        echo !SERVER_IND!
        echo !NAME_DIGIT!
        echo !CAM_NUM!
        echo !MIN_FRAME!
        echo !MAX_FRAME!
        echo !EXT_REF!
        echo !REF_FRAME!
    ) > "!INPUTFILE!"

    echo [Step !STEP_N!/!STEPS!] Running Process_SPIM.exe...
    "%BIN_DIR%\Process_SPIM.exe" < "!INPUTFILE!"

    del "!INPUTFILE!" 2>nul

    echo   Process_SPIM.exe completed for dataset !SRC_DIR!. 
    echo.
)

REM ============================================================
REM Step B: Run stack2h5_v2.exe via mpiexec (compression)
REM ============================================================
if "!DO_COMPRESS!"=="1" if "!SKIP_DATASET!" == "1" (
    set /a STEP_N+=1

    REM ---- Pre-flight: check for dimension log (required by stack2h5) ----
    set "HAS_DIM_LOG=0"
    if exist "!SRC_DIR!\Stack dimensions.log" set "HAS_DIM_LOG=1"
    if exist "!SRC_DIR!\stack_dimension.log"  set "HAS_DIM_LOG=1"
    if exist "!SRC_DIR!\stack_dimensions.log" set "HAS_DIM_LOG=1"
    if exist "!SRC_DIR!\Stack dimension.log"  set "HAS_DIM_LOG=1"
    if "!HAS_DIM_LOG!"=="0" (
        echo  [WARNING] dimension log not found in !SRC_DIR!
        echo    (checked: Stack dimensions.log, stack_dimension.log)
        echo    stack2h5 requires this file -- compression may fail.
        echo.
    )

    REM ---- Validate MPI core count against frame count ----
    REM Use a local copy so the global MPI_CORES is not polluted for
    REM subsequent datasets.
    set "EFF_CORES=!MPI_CORES!"
    set /a MAX_USEFUL_CORES=!EXPECTED_COUNT! + 1
    if !EFF_CORES! GTR !MAX_USEFUL_CORES! (
        echo  [ADJUST] MPI cores (!EFF_CORES!^) exceed useful limit for !EXPECTED_COUNT! frames.
        echo    Maximum useful cores: !MAX_USEFUL_CORES! (1 master + !EXPECTED_COUNT! workers)
        echo    Capping from !EFF_CORES! to !MAX_USEFUL_CORES! for this dataset.
        set EFF_CORES=!MAX_USEFUL_CORES!
        echo.
    )

    if not exist "!H5_DIR!" (
        mkdir "!H5_DIR!"
        echo Created: !H5_DIR!
        echo.
    )

    set "H5_INPUT=%TEMP%\h5_input_%RANDOM%.txt"

    REM Input order for stack2h5_v2.exe:
    REM   a) source folder (raw, with trailing backslash)
    REM   b) target folder (h5,  with trailing backslash)
    REM   c) digits of filename
    REM   d) camera index
    REM   e) min frame number
    REM   f) max frame number
    (
        echo !SRC_DIR!\
        echo !H5_DIR!\
        echo !NAME_DIGIT!
        echo !CAM_NUM!
        echo !MIN_FRAME!
        echo !MAX_FRAME!
    ) > "!H5_INPUT!"

    echo [Step !STEP_N!/!STEPS!] Running stack2h5_v2.exe with !EFF_CORES! MPI cores...
    "%BIN_DIR%\mpiexec.exe" -n !EFF_CORES! "%BIN_DIR%\stack2h5_v2.exe" < "!H5_INPUT!"

    del "!H5_INPUT!" 2>nul

    echo   mpiexec.exe -n !EFF_CORES! stack2h5_v2.exe completed for dataset !SRC_DIR!.
    echo.
)

    REM ============================================================
    REM Write per-dataset log
    REM ============================================================

    REM Ensure fallback values for variables that may not be set
    REM (HAS_DIM_LOG is only set inside the compression block)
    if not defined HAS_DIM_LOG set "HAS_DIM_LOG=0"

    REM Timestamp (locale-independent via wmic)
    for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul') do set "DT=%%I"
    set "TS=!DT:~0,4!-!DT:~4,2!-!DT:~6,2!_!DT:~8,2!!DT:~10,2!!DT:~12,2!"

    REM Extract dataset folder name from source dir
    for %%a in ("!SRC_DIR!") do set "DS_NAME=%%~nxa"

    REM Ensure logs directory exists
    set "LOG_DIR=%~dp0logs"
    if not exist "!LOG_DIR!" mkdir "!LOG_DIR!"
    set "LOG_FILE=!LOG_DIR!\!DS_NAME!_!TS!.log"

    REM Determine what modes actually ran
    set "RAN_REG=no"
    set "RAN_COMPRESS=no"
    if "!DO_REG!"=="1" set "RAN_REG=yes"
    if "!DO_COMPRESS!"=="1" set "RAN_COMPRESS=yes"

    REM Format MPI cores display (use local EFF_CORES if compression ran)
    set "MPI_DISPLAY=N/A"
    if defined EFF_CORES set "MPI_DISPLAY=!EFF_CORES!"

    REM Format dimension log as yes/no
    set "DIM_LOG_DISPLAY=NO"
    if "!HAS_DIM_LOG!"=="1" set "DIM_LOG_DISPLAY=YES"

    echo   Writing log...
    (
        echo ================================================
        echo   SPIM Processing Log
        echo   Dataset: !DS_NAME!
        echo   Timestamp: !TS!
        echo ================================================
        echo   Source dir:       !SRC_DIR!
        echo   Registered dir:   !TGT_DIR!
        echo   H5 dir:           !H5_DIR!
        echo   Frame range:      !MIN_FRAME! - !MAX_FRAME!
        echo   Reference frame:  !REF_FRAME!
        echo   Mode:             !MODE_LABEL!
        echo   MPI cores:        !MPI_DISPLAY!
        echo   Stack count:      !STACK_COUNT! found / !EXPECTED_COUNT! expected
        echo   Stack mismatch:   !STACK_MISMATCH!
        echo   Dimension log:    !DIM_LOG_DISPLAY!
        echo   Operations run:
        echo     Registration:   !RAN_REG!
        echo     Compression:    !RAN_COMPRESS!
        echo ================================================
    ) > "!LOG_FILE!"

    echo   Log saved: !LOG_FILE!
    echo.

goto :eof

REM === parse_frame_part: split "TM0000009" into prefix and digit count ===
:parse_frame_part
set "s=%~1"
set "pfx="
set "dig="
set "in_d=0"
set "n=0"

:p_loop
call set "ch=%%s:~!n!,1%%"
if "!ch!"=="" goto :p_done
if not "!in_d!"=="1" (
    for %%d in (0 1 2 3 4 5 6 7 8 9) do if "!ch!"=="%%d" set "in_d=1"
)
if "!in_d!"=="0" (
    set "pfx=!pfx!!ch!"
) else (
    set "dig=!dig!!ch!"
)
set /a n+=1
goto :p_loop

:p_done
set "%~2=!pfx!"
REM Count digits
set "cnt=0"
if "!dig!"=="" goto :p_cnt_done
:p_cnt
set "dig=!dig:~1!"
set /a cnt+=1
if not "!dig!"=="" goto :p_cnt
:p_cnt_done
set "%~3=!cnt!"
goto :eof

REM === str2num: strip leading zeros so set /a treats it as decimal ===
:str2num
set "num=%~1"
:strip
if "!num:~0,1!"=="0" (
    if not "!num!"=="0" (
        set "num=!num:~1!"
        goto :strip
    )
)
if "!num!"=="" set "num=0"
set "%~2=!num!"
goto :eof
