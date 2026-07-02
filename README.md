# SPIM Autopilot — Batch Processing Script

**`run_process_spim_and_compress_batch.bat`** automates SPIM registration and
h5 compression for light-sheet microscopy datasets.

---

## Overview

This batch script performs SPIM registration and/or h5 compression for each
selected dataset:

1. SPIM registration via `Process_SPIM.exe` (raw → registered)
2. h5 compression  via `stack2h5_v2.exe` / MPI   (raw → h5)

All processing runs in serial — only one GPU / MPI task at a time.  Multiple
datasets can be queued in one run; the script asks you to confirm each one
individually before processing begins.


## Directory layout

The script directory contains two user-facing files:

- `run_process_spim_and_compress_batch.bat` — the script
- `README.md` — this documentation

All executables and DLLs live in `bin\`:

| File | Purpose |
|---|---|
| `bin\Process_SPIM.exe`    | SPIM registration (CUDA) |
| `bin\stack2h5_v2.exe`     | h5 compression worker (MPI) |
| `bin\stack2h5_mpi.exe`    | older MPI worker (kept for reference) |
| `bin\mpiexec.exe`         | MPI launcher |
| `bin\*.dll`               | CUDA / HDF5 / Intel runtime DLLs |
| `bin\Process_SPIM.pdb`    | debug symbols |
| `bin\stack2h5.readme.txt` | notes for stack2h5 |

The script finds them automatically via `BIN_DIR=bin`.  You normally do not
need to touch anything inside `bin\`.

Source data must live under the `data\` folder.  The script scans for every
directory whose name ends with **`raw`** and that contains at least one
`.stack` file.


## Usage

### Preparing your data

1. Create a folder whose name ends in **`_raw`** (flat) **or** a folder
   named **`raw`** inside a parent directory (nested).  Both layouts are
   detected automatically:

   - Flat: `data\tm_20250601_raw\`
   - Nested: `data\tm_20250601\raw\`
2. Place your `.stack` files inside.  The naming convention is:

   ```
   <prefix><frame>_CM<camera>_CHN00.stack
   ```

   Examples: `TM0000001_CM0_CHN00.stack`, `TM0000001_CM1_CHN00.stack`

3. If you plan to run the compression step, also place a dimension log file
   in the same directory (required by `stack2h5`).  Common names:
   `Stack dimensions.log`, `stack_dimension.log`.

4. Run the script — it will scan `data\` recursively for any directory
   ending in `raw`, detect your datasets, and prompt you to confirm each one.

### Deliverables

| Step | Input | Output | Location |
|---|---|---|---|
| Registration | `*.stack` in the `raw` folder | Registered TIFF stacks | Sibling `registered` folder |
| Compression | `*.stack` + dimension log in the `raw` folder | h5 datasets | Sibling `h5` folder |

Both output directories are created automatically.  The script replaces
`raw` with `registered` / `h5` in the source path, so:

- `data\tm_20250601\raw\` → `data\tm_20250601\registered\`, `data\tm_20250601\h5\`

> **Note:** According to the source code of `Process_SPIM.exe`, the registered
> TIFF files are **transposed** relative to the raw stack images.  The
> `plane.stackf` files, however, retain the original orientation.


## Workflow

### 1. Select server *(first prompt)*

```
1) .6   (index 6)
2) .7   (index 7)
3) .81  (index 81)   [default]
```

The chosen index is passed to `Process_SPIM.exe` as the `server_ind` argument.
Press Enter to accept the default (`.81`), or type `1` / `2`.  An invalid
entry re-asks.

### 2. Prerequisite check

Verifies that `Process_SPIM.exe`, `stack2h5_v2.exe`, and `mpiexec.exe` all
exist in `bin\`.

### 3. Scan for datasets

Searches `data\` recursively for any directory whose name ends in `raw`.
Every matching directory is collected into a candidate list.  If none are
found, the script lists the contents of `data\` with guidance on the
expected layout.

### 4. Confirm each dataset

For each candidate the script analyzes the `.stack` files and prints:

> Sample file name, prefix, digit count, camera index, frame range,
> registration target directory, h5 target directory.

Then it asks:

```
Include this dataset? [Y/n]
```

- Press Enter (or any key except **N** / **n**) → **ADDED**
- Press **N** (or **n**) → **SKIPPED**

The computed values (prefix, digits, camera, min/max frame) are saved at this
point so later steps reuse them without re-scanning.

### 5. Select processing mode *(after datasets are confirmed)*

```
1) Registration only   (raw -> registered)
2) Compression only    (raw -> h5)
3) Both                (registration then compression)  [default]
```

- Option **1** runs only `Process_SPIM.exe`.
- Option **2** runs only `stack2h5_v2.exe` (MPI cores are used).
- Option **3** runs both; if registration fails for a dataset, its compression
  is skipped and the script moves on.

Step labels show `[Step n/m]` where *m* is the number of steps actually run
for the chosen mode (1 or 2).

### 6. Adjust MPI core count *(only when compression will run)*

Shows the current default (64).  Press Enter to keep it, or type a different
number (must be ≥ 2; one core is reserved as the MPI master).  Skipped
entirely in registration-only mode.

### 7. Processing loop

For every confirmed dataset, in order:

#### a) Restore pre-computed values

The prefix, digit count, camera index, and min/max frame numbers are read
from the values saved during step 4 — no re-analysis of the source directory
is needed.

#### b) Pre-flight: stack count check

The script counts the actual `*_CM{n}_CHN00.stack` files and compares against
`(max − min + 1)`.  A mismatch warns about missing frames before the tools
encounter them.

#### c) Pre-flight: `stack_dimension.log` check *(before compression)*

If the dimension log is absent from the source directory (checked under 4
naming variants), the script warns — it is required by `stack2h5`.

#### d) Pre-flight: MPI core validation *(before compression)*

Warns when `MPI_CORES` exceeds `1 + frame_count` (the useful upper limit —
extra workers would crash on unmatched frames).

#### e) Registration step — `Process_SPIM.exe` *(if selected)*

- Target directory: `<raw>` → `<registered>` (created automatically).
- Input is fed via a temporary text file.
- In **Both** mode, a non-zero exit code skips compression for this dataset.

#### f) Compression step — `stack2h5_v2.exe` (MPI) *(if selected)*

- Target directory: `<raw>` → `<h5>` (created automatically).
- Executed as: `bin\mpiexec.exe -n <cores> bin\stack2h5_v2.exe`
- Input values passed via stdin:
  1. Source folder (raw, trailing backslash)
  2. Target folder (h5, trailing backslash)
  3. Digit count of file name
  4. Camera index (0 or 1)
  5. Min frame number
  6. Max frame number

### 8. Results summary

A table prints at the end listing every dataset:

```
================ RESULTS ================
[1] OK      data\tm_001_raw
[2] FAILED  REG_FAIL  (exit 5)
========================================
1 of 2 succeeded, 1 FAILED
```

If any dataset failed, a `*** Some datasets FAILED ***` banner holds the
screen so you can review the errors before the terminal closes.


## Configurable defaults (edit the `.bat` file)

| Variable | Default | Purpose |
|---|---|---|
| `SERVER_IND` | `81` | Server index passed to Process_SPIM (overridden by the first prompt) |
| `EXT_REF` | `0` | `0` = internal reference; `1` = external |
| `RDIR` | `.` | Reference directory (unused when `EXT_REF=0`) |
| `MPI_CORES` | `64` | Number of MPI cores for `stack2h5_v2` (must be ≥ 2) |
| `BIN_DIR` | `bin` | Subfolder holding the exes and DLLs |


## Important notes

- The server index and the registration/compression mode are both
  chosen interactively at the start of each run.
- The MPI core count is adjusted interactively only when a
  compression step will run.
- Ensure a dimension log file exists in each source directory
  before running the compression step (`stack2h5` requirement).
- If a dataset fails during `Process_SPIM` in "Both" mode, its
  compression step is skipped so the remaining datasets can still
  be processed.
- Directories passed to `stack2h5_v2.exe` end with a backslash (`\`)
  as required by that tool.
- At least 2 MPI cores are needed: 1 master + N−1 workers.
- If MPI jobs crash with more cores but succeed with fewer, other
  users may be occupying cores on the same server — reduce the
  count and retry.
- The exes load their DLLs from `bin\` automatically; do not move
  DLLs out of `bin\`.
