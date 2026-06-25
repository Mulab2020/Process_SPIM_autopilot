@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ================================================
echo   SPIM Registration - Automatic Configuration
echo ================================================
echo.

REM ============================================================
REM Defaults
REM ============================================================
set "SERVER_IND=81"
set "EXT_REF=0"
set "RDIR=."

REM ============================================================
REM Check prerequisites
REM ============================================================
if not exist "Process_SPIM.exe" (
    echo [ERROR] Process_SPIM.exe not found here: %~dp0
    echo Place this script in the same directory as Process_SPIM.exe.
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
    echo [ERROR] No directory ending with "raw" found that contains .stack files.
    echo Current: %cd%
    pause
    exit /b 1
)

if !COUNT! GTR 1 (
    echo Found !COUNT! raw directories:
    for /l %%i in (1,1,!COUNT!) do echo   %%i. !RAW_%%i!
    echo.
    set /p CHOICE="Select one (1-!COUNT!): "
    set "SRC_DIR=!RAW_%CHOICE%!"
) else (
    set "SRC_DIR=!RAW_1!"
)

REM ============================================================
REM Target directory: raw -> registered
REM ============================================================
set "TGT_DIR=!SRC_DIR:raw=registered!"

REM ============================================================
REM Analyze a sample .stack file for naming pattern
REM ============================================================
set "FIRST=1"
for %%f in ("!SRC_DIR!\*.stack") do (
    if !FIRST! EQU 1 (
        set "SAMPLE=%%~nxf"
        set "FIRST=0"
    )
)

REM Format: TM{frame}_CM{cam}_CHN00.stack  (split by _)
for /f "tokens=1-3 delims=_" %%a in ("!SAMPLE!") do (
    set "PART_A=%%a"    REM e.g. TM0000009
    set "PART_B=%%b"    REM e.g. CM0
    set "PART_C=%%c"    REM e.g. CHN00.stack
)

REM Camera number from "CM{N}"
set "CAM_NUM=!PART_B:~2,1!"

REM Extract prefix and digit count from e.g. "TM0000009"
call :parse_frame_part "!PART_A!" PREFIX NAME_DIGIT

REM ============================================================
REM Find min / max frame number for this camera
REM ============================================================
set "MIN_FRAME=2147483647"
set "MAX_FRAME=0"

for %%f in ("!SRC_DIR!\*_CM!CAM_NUM!_CHN00.stack") do (
    set "FNAME=%%~nxf"
    for /f "tokens=1 delims=_" %%a in ("!FNAME!") do (
        set "FULL=%%a"
    )
    set "FRAME_STR=!FULL:%PREFIX%=!"
    call :str2num "!FRAME_STR!" FRAME_NUM
    if !FRAME_NUM! LSS !MIN_FRAME! set "MIN_FRAME=!FRAME_NUM!"
    if !FRAME_NUM! GTR !MAX_FRAME! set "MAX_FRAME=!FRAME_NUM!"
)

REM ============================================================
REM Derive reference frame (middle of range)
REM ============================================================
set /a REF_FRAME=(!MIN_FRAME! + !MAX_FRAME!) / 2


REM ============================================================
REM Display summary & ask confirmation
REM ============================================================
echo.
echo ================================================
echo   Detected Configuration
echo ================================================
echo   Sample file:  !SAMPLE!
echo   Prefix:       !PREFIX!
echo   Digit count:  !NAME_DIGIT!
echo   Camera:       !CAM_NUM!
echo.
echo   Source dir:   !SRC_DIR!
echo   Target dir:   !TGT_DIR!
echo   Ref  dir:     !RDIR!  (not used)
echo   Server:       !SERVER_IND!
echo   Frame range:  !MIN_FRAME! - !MAX_FRAME!
echo   Ref  frame:   !REF_FRAME!  (middle)
echo   Ref  mode:    internal
echo ================================================
echo.

set /p CONFIRM="Proceed? [Y/n]: "
if /i "!CONFIRM!"=="N" (
    echo Aborted.
    pause
    exit /b 0
)

REM ============================================================
REM Create target directory
REM ============================================================
if not exist "!TGT_DIR!" (
    mkdir "!TGT_DIR!"
    echo Created: !TGT_DIR!
    echo.
)

REM ============================================================
REM Build input file and run Process_SPIM.exe
REM ============================================================
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

echo Running Process_SPIM.exe...
echo.

Process_SPIM.exe < "!INPUTFILE!"
set "EXIT_CODE=!ERRORLEVEL!"

del "!INPUTFILE!" 2>nul

echo.
echo ================================================
if !EXIT_CODE! EQU 0 (
    echo   Completed successfully.
) else (
    echo   Program exited with code !EXIT_CODE!.
)
echo ================================================
pause
exit /b !EXIT_CODE!

REM ============================================================
REM Subroutines
REM ============================================================

REM ---- parse_frame_part: split "TM0000009" into prefix and digit count ----
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

REM ---- str2num: strip leading zeros so set /a treats it as decimal ----
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
