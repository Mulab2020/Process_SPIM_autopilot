# Lessons Learned — SPIM Autopilot Batch Script

Written 2026-06-27/28 for the next agent working on
`run_process_spim_and_compress_batch.bat`.

## 1. Batch scripting gotchas

### Never use `goto` inside `for /f` inside a `call`ed subroutine

`goto` breaking out of a `for /f` loop while inside a `call` context can
corrupt cmd.exe's return stack.  Subsequent `call :label` commands may fail
with "The system cannot find the batch label" even though the label exists.

**Fix:** use `if not defined GUARD` to skip the loop body after the first
match instead of `goto :label`.

```bat
REM BROKEN — goto corrupts call stack
for /f %%a in ('dir /b /on "pattern"') do (set "X=%%a" & goto :got_it)
:got_it
call :str2num "!X!" V      ← "label not found" error here

REM SAFE — no goto
set "X="
for /f %%a in ('dir /b /on "pattern"') do if not defined X (set "X=%%a")
call :str2num "!X!" V      ← works
```

### Never use `find /c /v` to count lines in a cross-locale script

`find /c` output format varies by Windows locale.  On English systems it
prints a bare number; on Chinese systems it may include whitespace or
headers that corrupt `for /f` token parsing.

**Fix:** count files with a simple `for %%f in (glob) do set /a N+=1` loop.
For the min/max frame scan use `dir /b /on` (ascending) / `dir /b /o-n`
(descending) with the `if not defined` guard — only the first line matters.

### Variable pollution across dataset iterations

There is one `setlocal enabledelayedexpansion` at the top of the script.
All subroutines share the same variable scope.  Variables set during
processing of dataset N will leak into dataset N+1 unless explicitly
cleared.

**Fix:** clear all per-dataset working variables at the top of
`:process_dataset` (and similarly in `:preview_and_ask`).  The main ones:
`PREFIX`, `NAME_DIGIT`, `CAM_NUM`, `MIN_FRAME`, `MAX_FRAME`, `REF_FRAME`,
`SPIM_EXIT`, `H5_EXIT`, `STACK_COUNT`, `EXPECTED_COUNT`.

### Double-indirection requires `call set` or `for %%v`

When variable names embed another variable (like `SEL_PREFIX_!DS_IDX!`),
use the `call set` trick to force a second expansion:

```bat
call set "PREFIX=%%SEL_PREFIX_!DS_IDX!%%"
```

Or use `for %%v in ("!DS_IDX!") do set "PREFIX=!SEL_PREFIX_%%~v!"`.

### `)` must be escaped as `^)` in `echo` inside parenthesized blocks

When echoing text containing `)` inside a parenthesized `if` or `for` block,
the closing paren terminates the block.  Escape it: `^)`.

### Never put `>>` redirection at the start of a line inside a parenthesized block

When `>> "file" echo ...` appears at the **start** of a line inside a multi-line
`if (...) { } else { }` block, cmd.exe can detach that command from the block
scope, causing it to execute **unconditionally** regardless of the `if` condition.
This produces false warnings in log files even when the `else` branch runs
correctly for terminal output.

**Fix:** always place the redirection at the **end** of the command:

```bat
REM BROKEN — >> at line-start inside if block: command leaks out, always runs
if !A! NEQ !B! (
    >> "log.txt" echo   WARNING: mismatch ^(expected !B!, found !A!^)
) else (
    echo   OK
)

REM SAFE — redirection at end of line
if !A! NEQ !B! (
    echo   WARNING: mismatch ^(expected !B!, found !A!^) >> "log.txt"
) else (
    echo   OK
)
```

The same rule applies to block-level redirections — use `( ... ) >> "file"`
rather than `>> "file" ( ... )`.

## 2. Tool input conventions

### Process_SPIM.exe parameter order (kernel2.cu)

```
getline: sdir, tdir, rdir
cin >>:  server_ind, name_digit, cam_num, mintime, maxtime, extRef
if extRef: cin >> reftime
```

This was verified identical to the archived `run_process_spim.bat`.

### stack2h5_v2.exe input (stdin)

```
1. source folder (raw, trailing backslash)
2. target folder (h5,  trailing backslash)
3. digits of filename
4. camera index
5. min frame number
6. max frame number
```

### stack2h5 requires a dimension log file

The file is named **`Stack dimensions.log`** in the sample data (space,
capital S, plural "dimensions").  Other variants (`stack_dimension.log`)
also exist.  The script now checks four variants.

## 3. Directory layout convention

- `bin\` — executables + DLLs (may or may not be git-tracked depending on
  .gitignore state)
- `data\` — user datasets, each in a directory whose name ends with `_raw`
  and contains `.stack` files
- `logs\` — per-dataset processing logs (`<dataset>_<timestamp>.log`),
  written at the script root
- `archive\` — historical scripts and reference material

## 4. Git notes

- The `.gitignore` has changed multiple times across commits — check its
  current state before deciding what's tracked.
- Initial design kept `bin/` out of git (via `*.exe` + `*.dll` + `*.pdb`),
  then it was switched to track `bin/` (for lab GitHub push) and exclude
  `data/`.

## 5. Key states to check when debugging

1. **Min/max frame**: printed during preview → are they correct?
2. **Stack count**: does it match (max-min+1)?
3. **Dimension log**: present in the source directory?
4. **Per-dataset log**: `logs\<dataset>_<timestamp>.log` at the script root —
   written for every dataset (including skipped ones) with full config,
   stack counts, mismatch flag, and which operations ran.
5. **Temp input files**: `%TEMP%\spim_input_*.txt` and `%TEMP%\h5_input_*.txt`
   — written just before each tool run and deleted immediately after.  If a
   tool hangs or produces garbled output, comment out the `del` lines to
   inspect what was fed to it.
