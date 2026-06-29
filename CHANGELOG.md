# Changelog

## [0.2.3] — 2026-06-29

### Fixed
- **Exit code misread as stale errorlevel**: the `call echo %%%%errorlevel%%%%` pattern
  inside the `for /f` backtick pipeline expanded `%errorlevel%` at `cmd /c` parse time —
  *before* the process ran — so the exit file always contained whatever errorlevel was
  left by the previous command (usually 0, causing false FAILED verdicts for successful
  runs).  Changed to `%%^^errorlevel%%` so the `^` blocks first-pass expansion and
  `call` re-expands it correctly after the process exits.  Applied to both
  `Process_SPIM.exe` and `mpiexec`/`stack2h5_v2.exe` pipelines.

## [0.2.2] — 2026-06-29

### Fixed
- **False "stack count mismatch" warning in log**: `>> "file" echo ...` placed at the
  start of a line inside an `if (...) else (...)` block causes cmd.exe to detach the
  command from the block scope, executing it unconditionally.  The warning line always
  landed in the log even when the `else` branch ran correctly on terminal — producing
  messages like `expected 31, found 31`.  All 12 redirects moved to end-of-line
  (`echo ... >> "file"`), the safe idiomatic form.

### Added
- **Real-time streaming output**: both `Process_SPIM.exe` and `stack2h5_v2.exe`
  stdout+stderr are now displayed line-by-line on terminal and written to the log
  as they run, via `for /f` loops.  Exit code is preserved through a tiny temp file
  (`%TEMP%\spim_exit_*.txt` / `h5_exit_*.txt`) written by `call echo %%^^errorlevel%%`
  inside the command pipe and read back with `set /p`.
- **MPI core count validation**: before compression, warn when `MPI_CORES` exceeds
  `1 + frame_count` (the useful upper limit — extra workers would crash on unmatched
  frames).

### Changed
- **`SUMMARY_LOG` → `LOG_FILE`**: the separate `SPIM_LOG` / `H5_LOG` temp logs were
  removed by the streaming change, so there is now a single log file — "summary" was
  redundant.
- **Improved "no raw directory" error**: when `data\` exists but has no `*raw` folders,
  the current contents are listed with a hint about expected naming.
- **gitignore**: add `archive/*.md` (agent notes, not for distribution).
- Removed dead `SPIM_LOG` / `H5_LOG` variable initialization, clearing, and cleanup.
  `ERRLOG_*` now points to `LOG_FILE` for failure reporting.

## [0.2.1] — 2026-06-27 — `56d2bd9`

### Changed
- `.gitignore`: drop `bin/` + `*.exe` + `*.dll` + `*.pdb` ignores; add `data/`.
  **Purpose:** the `bin/` executables and runtime DLLs (30 MB) are now tracked in git
  so the repository is self-contained and can be cloned onto a lab server without
  separately copying binaries. `data/` is excluded since it holds user datasets.
- `bin/` (12 files: Process_SPIM.exe, stack2h5_v2.exe, mpiexec.exe, CUDA / HDF5 /
  Intel runtime DLLs, debug symbols) committed to the repository.

### Added
- `CHANGELOG.md` documenting all commits and the initial state.

---

## [0.2.0] — 2026-06-27 — `c4eb9ea`

### Added
- **Per-step log capture**: `Process_SPIM.exe` and `mpiexec`/`stack2h5_v2` stdout/stderr
  redirected to files in `%TEMP%`. On success the log is deleted; on failure it's kept
  and the path is printed so the error output survives past the terminal session.
- **Stack count pre-flight check**: before processing, the script counts actual
  `*_CM{n}_CHN00.stack` files and compares to `max−min+1`. A mismatch warns about
  missing frames before the tools encounter them.
- **`stack_dimension.log` check**: before compression, warns if the required file
  is missing from the source directory.
- **Per-dataset error tracking**: exit codes and log paths recorded in `ERR_n` /
  `ERRCODE_n` / `ERRLOG_n` arrays, printed in a results table at the end.
- **Master run log**: written to `data\logs\autopilot_<timestamp>.log` with a
  summary header and per-dataset results so errors are never lost.
- **Variable pollution clearing**: all per-dataset working variables explicitly
  reset at the top of `:process_dataset` to prevent values leaking across runs.

### Changed
- Final `pause` now preceded by `*** Some datasets FAILED ***` banner so a user
  who glances at the bottom of the screen knows something went wrong.
- Failures show both the exit code and the path to the saved tool log.

---

## [0.1.3] — 2026-06-27 — `0a65e94`

### Changed
- **Eliminated duplicate analysis**: `:preview_and_ask` already computes prefix,
  digits, camera, and min/max frame. Those values are now stored in `SEL_PREFIX_n` /
  `SEL_DIGITS_n` / `SEL_CAM_n` / `SEL_MIN_n` / `SEL_MAX_n` arrays when the user
  confirms a dataset. `:process_dataset` reads them via `call set` double-indirection
  instead of re-parsing `.stack` files and re-running dir-sort scans.
  — 43 lines removed, 12 added.

---

## [0.1.2] — 2026-06-26 — `f3f554e`

### Performance
- **Min/max frame scan: O(N) → O(1)**. Replaced the `for %%f in (...)` loop over
  every `.stack` file with two `dir /b /on` (ascending) / `dir /b /o-n` (descending)
  calls, each breaking after the first output line via `goto`. Zero-padded filenames
  sort alphabetically = numerically, so first-in-ascending = min, first-in-descending = max.
  Only 2 filenames are ever parsed (2 `:str2num` calls total).
  **Measured on 5k files: 20 s → 0.23 s.**  
  Projected for 18k frames (2 h @ 2.5 Hz): 72 s → < 1 s.

---

## [0.1.1] — 2026-06-26 — `b302262`

### Performance
- **Min/max frame scan: 2 `:str2num` calls instead of N**. Zero-padded frame
  strings have a fixed digit count, so lexicographic comparison (`LSS` / `GTR`)
  equals numeric comparison. The loop now compares frame strings directly and only
  calls the character-by-character `:str2num` subroutine on the final winners.
  **For 100k files: 100k subroutine calls → 2.**

---

## [0.1.0] — 2026-06-25 — `af64fd8`

### Added
- **Server selection prompt** (first prompt): choose `.6` (index 6), `.7` (index 7),
  or `.81` (index 81, default). The selected index is passed to `Process_SPIM.exe`
  as `server_ind`.
- **Processing mode prompt** (after dataset confirmation):
  `1` Registration only, `2` Compression only, `3` Both (default).
  Step labels (`[Step n/m]`) and the MPI-core prompt adapt to the chosen mode.
- **README** in English and Chinese covering the new prompts, workflow, and defaults.
- **`.gitignore`**: `sample_data/`, `*.exe`, `*.dll`, `*.pdb`, `*.h5`, `*.tmp`, `%TEMP%/`.

### Changed
- **Directory layout**: all `.exe`, `.dll`, and `.pdb` files moved into `bin\`.
  Root exposes only the `.bat` and README. Script references exes via `BIN_DIR=bin`.
  DLLs are found automatically by Windows (they live alongside their exe).
- **Prerequisite checks** updated to look in `bin\`.
- **`archive/`** (old `run_process_spim.bat` + README) included as historical reference.

---

## [Initial] — pre-2026-06-25

- Original monolithic `run_process_spim_and_compress_batch.bat` with hardcoded
  `SERVER_IND=81`, no mode selection, per-file `:str2num` calls in the frame scan,
  and duplicate analysis between preview and processing.
- Executables and DLLs scattered at repository root.
- Errors scrolled off-screen with `pause` only on the final "ALL DONE" line,
  no log capture or error summary.
