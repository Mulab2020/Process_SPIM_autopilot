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

1. Create a folder under `data\` with a name ending in **`_raw`**, e.g.
   `data\tm_20250601_raw\`.
2. Place your `.stack` files inside.  The naming convention is:

   ```
   <prefix><frame>_CM<camera>_CHN00.stack
   ```

   Examples: `TM0000001_CM0_CHN00.stack`, `TM0000001_CM1_CHN00.stack`

3. If you plan to run the compression step, also place `stack_dimension.log`
   in the same directory (required by `stack2h5`).

4. Run the script — it will scan `data\*_raw`, detect your datasets, and
   prompt you to confirm each one.

### Deliverables

| Step | Input | Output | Location |
|---|---|---|---|
| Registration | `data\*_raw\*.stack` | Registered TIFF stacks | `data\*_registered\` |
| Compression | `data\*_raw\*.stack` + `stack_dimension.log` | h5 datasets | `data\*_h5\` |

Both output directories are created automatically alongside the source
directory (the script replaces `raw` with `registered` / `h5` in the
path).


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

Searches `data\*raw` recursively.  Every matching directory is collected into
a candidate list.

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

If `stack_dimension.log` is absent from the source directory, the script warns
(it is required by `stack2h5`).

#### d) Registration step — `Process_SPIM.exe` *(if selected)*

- Target directory: `<raw>` → `<registered>` (created automatically).
- Input is fed via a temporary text file.
- stdout/stderr captured to a log file in `%TEMP%`.
- In **Both** mode, a non-zero exit code skips compression for this dataset.
- On success the log is deleted; on failure the log path is printed.

#### e) Compression step — `stack2h5_v2.exe` (MPI) *(if selected)*

- Target directory: `<raw>` → `<h5>` (created automatically).
- Executed as: `bin\mpiexec.exe -n <cores> bin\stack2h5_v2.exe`
- Input values passed via stdin:
  1. Source folder (raw, trailing backslash)
  2. Target folder (h5, trailing backslash)
  3. Digit count of file name
  4. Camera index (0 or 1)
  5. Min frame number
  6. Max frame number
- stdout/stderr captured to a log file in `%TEMP%`.
- On success the log is deleted; on failure the log path is printed.

### 8. Results summary

A table prints at the end listing every dataset:

```
================ RESULTS ================
[1] OK      data\tm_001_raw
[2] FAILED  REG_FAIL  (exit 5)
     Log: %TEMP%\spim_log_12345.log
========================================
1 of 2 succeeded, 1 FAILED
```

If any dataset failed, an extra pause holds the screen so you can read the
error output before the terminal closes.

A master run log is also written to `data\logs\autopilot_<timestamp>.log`
with per-dataset results and references to the per-step log files.


## Logging

| Log | Location | Lifecycle |
|---|---|---|
| Per-step tool output | `%TEMP%\spim_log_*.log` / `h5_log_*.log` | Deleted on success; kept on failure |
| Master run summary | `data\logs\autopilot_<timestamp>.log` | Always kept |

On error the script prints the exact log path.  On success the per-step logs
are cleaned up automatically.


## Configurable defaults (edit the `.bat` file)

| Variable | Default | Purpose |
|---|---|---|
| `SERVER_IND` | `81` | Server index passed to Process_SPIM (overridden by the first prompt) |
| `EXT_REF` | `0` | `0` = internal reference; `1` = external |
| `RDIR` | `.` | Reference directory (unused when `EXT_REF=0`) |
| `MPI_CORES` | `64` | Number of MPI cores for `stack2h5_v2` (must be ≥ 2) |
| `BIN_DIR` | `bin` | Subfolder holding the exes and DLLs |


## Important notes

- The server index and the registration/compression mode are both chosen
  interactively at the start of each run.
- The MPI core count is adjusted interactively only when a compression step
  will run.
- `stack_dimension.log` must exist in each source directory before running
  the compression step (checked automatically; a warning is printed if
  missing).
- If a dataset fails during `Process_SPIM` in **Both** mode, its compression
  step is skipped so the remaining datasets can still be processed.
- Directories passed to `stack2h5_v2.exe` end with a backslash (`\`) as
  required by that tool.
- At least 2 MPI cores are needed: 1 master + N−1 workers.
- If MPI jobs crash with more cores but succeed with fewer, other users may
  be occupying cores on the same server — reduce the count and retry.
- The exes load their DLLs from `bin\` automatically; do not move DLLs out
  of `bin\`.
- **Per-step logs** are saved in `%TEMP%` on failure.  The script prints the
  full path so you can review the tool's output even after the terminal
  closes.
- **Master run log** is written to `data\logs\` for every run.  It lists
  each dataset's outcome and references the per-step logs for failures.


---

## 概述 (中文)

此批处理脚本对每个选定的数据集依次完成 SPIM 配准和/或 h5 压缩：

1. 通过 `Process_SPIM.exe` 进行 SPIM 配准（raw → registered）
2. 通过 `stack2h5_v2.exe` / MPI 进行 h5 压缩（raw → h5）

所有处理均为串行 — 同一时间仅运行一个 GPU / MPI 任务。一次运行可
排队处理多个数据集；脚本会在处理开始前逐个询问确认。


## 目录结构

脚本根目录仅暴露两个用户文件：

- `run_process_spim_and_compress_batch.bat` — 本脚本
- `README.md` — 本文档

所有可执行文件及其 DLL 位于 `bin\` 子文件夹：

| 文件 | 用途 |
|---|---|
| `bin\Process_SPIM.exe`    | SPIM 配准（CUDA） |
| `bin\stack2h5_v2.exe`     | h5 压缩工作进程（MPI） |
| `bin\stack2h5_mpi.exe`    | 旧版 MPI 工作进程（保留备查） |
| `bin\mpiexec.exe`         | MPI 启动器 |
| `bin\*.dll`               | CUDA / HDF5 / Intel 运行时 DLL |
| `bin\Process_SPIM.pdb`    | 调试符号 |
| `bin\stack2h5.readme.txt` | stack2h5 说明 |

脚本通过 `BIN_DIR=bin` 自动定位这些文件，通常无需手动改动 `bin\` 内
的任何内容。

源数据必须位于 `data\` 文件夹下。脚本会扫描每个以 **`raw`** 结尾且
包含至少一个 `.stack` 文件的目录。


## 使用方法

### 准备数据

1. 在 `data\` 下创建以 **`_raw`** 结尾的文件夹，如 `data\tm_20250601_raw\`。
2. 将 `.stack` 文件放入其中。命名规范为：

   ```
   <前缀><帧号>_CM<相机>_CHN00.stack
   ```

   示例：`TM0000001_CM0_CHN00.stack`、`TM0000001_CM1_CHN00.stack`

3. 如需运行压缩步骤，请同时将 `stack_dimension.log` 放入同一目录
   （`stack2h5` 依赖此文件）。

4. 运行脚本 — 它会自动扫描 `data\*_raw`，检测到数据集后逐个提示确认。

### 输出产物

| 步骤 | 输入 | 输出 | 位置 |
|---|---|---|---|
| 配准 | `data\*_raw\*.stack` | 配准后的 TIFF 栈 | `data\*_registered\` |
| 压缩 | `data\*_raw\*.stack` + `stack_dimension.log` | h5 数据集 | `data\*_h5\` |

两个输出目录会自动在源目录旁创建（脚本将路径中的 `raw` 替换为
`registered` / `h5`）。


## 工作流程

### 1. 选择服务器（首个提示）

```
1) .6   (索引 6)
2) .7   (索引 7)
3) .81  (索引 81)   [默认]
```

所选值作为 `server_ind` 参数传给 `Process_SPIM.exe`。按 Enter 接受默认
（`.81`），或输入 `1` / `2`。输入无效会重新询问。

### 2. 前置检查

验证 `Process_SPIM.exe`、`stack2h5_v2.exe` 和 `mpiexec.exe` 是否都
存在于 `bin\` 中。

### 3. 扫描数据集

递归搜索 `data\*raw`。每个匹配的目录都会被收集到候选列表中。

### 4. 逐个确认数据集

对于每个候选目录，脚本会分析其中的 `.stack` 文件并显示完整信息：

> 样本文件名、前缀、位数、相机编号、帧范围、配准目标目录、h5 目标目录。

然后询问：

```
Include this dataset? [Y/n]
```

- 按 Enter（或除 **N** / **n** 外的任意键）→ **加入处理队列**
- 按 **N**（或 **n**）→ **跳过**

此时计算得到的值（前缀、位数、相机、最小/最大帧号）会被保存，后续步骤
直接复用，无需重新扫描。

### 5. 选择处理模式（确认数据集之后）

```
1) 仅配准   (raw -> registered)
2) 仅压缩   (raw -> h5)
3) 两者都做 (registration then compression)  [默认]
```

- 选项 **1** 只运行 `Process_SPIM.exe`。
- 选项 **2** 只运行 `stack2h5_v2.exe`（会用到 MPI 核数）。
- 选项 **3** 两者都运行；若某数据集配准失败，则跳过其压缩步骤，继续处理
  下一个数据集。

步骤标签显示 `[Step n/m]`，其中 *m* 为所选模式实际运行的步骤数（1 或 2）。

### 6. 调整 MPI 核数（仅当需要压缩时）

显示当前默认值（64）。按 Enter 保留，或输入其他数值（必须 ≥ 2；其中
1 个保留为 MPI master）。仅配准模式下会跳过此步。

### 7. 串行处理循环

按顺序对每个已确认的数据集执行：

#### a) 恢复预计算值

从步骤 4 保存的值中读取前缀、位数、相机编号和最小/最大帧号 — 无需重新
扫描源目录。

#### b) 预检：栈文件数量校验

统计实际的 `*_CM{n}_CHN00.stack` 文件数并与 `(max − min + 1)` 对比。
数量不匹配时发出警告，在工具遇到缺失帧之前提示用户。

#### c) 预检：`stack_dimension.log` 检查（压缩前）

如果源目录缺少 `stack_dimension.log`，脚本会发出警告（`stack2h5` 依赖
此文件）。

#### d) 配准步骤 — `Process_SPIM.exe`（若选中）

- 目标目录：`<raw>` → `<registered>`（自动创建）。
- 通过临时文本文件传入参数。
- stdout/stderr 捕获到 `%TEMP%` 下的日志文件。
- 在「两者都做」模式下，若返回非零退出码，则跳过该数据集的压缩步骤。
- 成功时删除日志；失败时打印日志路径。

#### e) 压缩步骤 — `stack2h5_v2.exe`（MPI）（若选中）

- 目标目录：`<raw>` → `<h5>`（自动创建）。
- 执行命令：`bin\mpiexec.exe -n <核数> bin\stack2h5_v2.exe`
- 通过标准输入传入以下值：
  1. 源文件夹（raw，末尾带反斜杠）
  2. 目标文件夹（h5，末尾带反斜杠）
  3. 文件名位数
  4. 相机编号（0 或 1）
  5. 最小帧号
  6. 最大帧号
- stdout/stderr 捕获到 `%TEMP%` 下的日志文件。
- 成功时删除日志；失败时打印日志路径。

### 8. 结果汇总

最后打印每个数据集的处理结果表格：

```
================ RESULTS ================
[1] OK      data\tm_001_raw
[2] FAILED  REG_FAIL  (exit 5)
     Log: %TEMP%\spim_log_12345.log
========================================
1 of 2 succeeded, 1 FAILED
```

若有任何数据集失败，会额外暂停等待用户按键，确保在终端关闭前能查看
错误输出。

同时会向 `data\logs\autopilot_<timestamp>.log` 写入一份主运行日志，
记录每个数据集的结果及对应步骤日志的路径。


## 日志

| 日志 | 位置 | 生命周期 |
|---|---|---|
| 各步骤工具输出 | `%TEMP%\spim_log_*.log` / `h5_log_*.log` | 成功时删除，失败时保留 |
| 主运行摘要 | `data\logs\autopilot_<timestamp>.log` | 始终保留 |

出错时脚本会打印具体日志路径。步骤成功时日志自动清理。


## 可配置的默认值（编辑 `.bat` 文件修改）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SERVER_IND` | `81` | 传给 Process_SPIM 的服务器编号（会被首个提示覆盖） |
| `EXT_REF` | `0` | `0` = 内部参考；`1` = 外部参考 |
| `RDIR` | `.` | 参考目录（`EXT_REF=0` 时未使用） |
| `MPI_CORES` | `64` | `stack2h5_v2` 的 MPI 核数（必须 ≥ 2） |
| `BIN_DIR` | `bin` | 存放 exe 与 DLL 的子文件夹 |


## 重要提示

- 服务器编号与「配准 / 压缩」模式均在每次运行开始时交互选择。
- MPI 核数仅在有压缩步骤时才会交互调整。
- 压缩前会自动检查 `stack_dimension.log` 是否存在；缺少时会打印警告。
- 在「两者都做」模式下，若某数据集在 `Process_SPIM` 阶段失败，其压缩
  步骤将被跳过，其余数据集仍可继续处理。
- 传给 `stack2h5_v2.exe` 的目录路径末尾带有反斜杠（`\`），以符合该工具
  的要求。
- 至少需要 2 个 MPI 核：1 个 master + N−1 个 worker。
- 如果 MPI 作业在较多核数时崩溃，但用较少核数可以成功，可能是服务器上
  其他用户正在占用部分核心 — 请减少核数后重试。
- 可执行文件会自动从 `bin\` 加载所需 DLL，请勿将 DLL 移出 `bin\`。
- **步骤日志**：失败时保存在 `%TEMP%` 下，脚本会打印完整路径，关闭终端
  后仍可查看。
- **主运行日志**：每次运行都会写入 `data\logs\`，记录每个数据集的结果
  及失败步骤日志的路径。
