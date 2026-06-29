# Changelog

## [0.1.4] — 2026-06-29

### Fixed
- **`goto`-in-`for` call-stack corruption**: `goto :pv_got_min_file` and
  `goto :pv_got_max_file` inside `for /f` loops within `call :preview_and_ask`
  corrupt cmd.exe's `call` return stack, causing subsequent `call :str2num` and
  other `call :label` commands to fail with "The system cannot find the batch
  label." Replaced `goto` with `if not defined PV_MIN_FILE` / `if not defined
  PV_MAX_FILE` guards — the loop processes all files but only captures the
  first match (the same effect, but without breaking the call stack).
- **Variable pollution across datasets**: all subroutines share a single
  `setlocal enabledelayedexpansion` scope. Variables set during dataset N
  can leak into dataset N+1, causing incorrect min/max values, stale exit
  codes, and other subtle corruption. Now `:preview_and_ask` explicitly
  clears `PV_MIN`, `PV_MAX`, `PV_MIN_FILE`, and `PV_MAX_FILE` before
  min/max detection; `:process_dataset` resets all per-dataset working
  variables (`PREFIX`, `NAME_DIGIT`, `CAM_NUM`, `MIN_FRAME`, `MAX_FRAME`,
  `REF_FRAME`, `TGT_DIR`, `H5_DIR`, `SPIM_EXIT`, `H5_EXIT`, `STEP_N`,
  `STEPS`, `STACK_COUNT`, `EXPECTED_COUNT`) at entry.

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
