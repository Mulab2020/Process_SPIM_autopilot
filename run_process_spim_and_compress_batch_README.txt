================================================================
  run_process_spim_and_compress_batch.bat — Documentation
================================================================

  English
  ----------------------------------------------------------------
  Chinese (中文)
  ----------------------------------------------------------------

================================================================
  ENGLISH
  =================================================================

Overview
--------
This batch script performs SPIM registration and/or h5 compression
for each selected dataset:
  1. SPIM registration via Process_SPIM.exe   (raw -> registered)
  2. h5 compression  via stack2h5_v2.exe / MPI (raw -> h5)

All processing runs in serial — only one GPU / MPI task at a time.
Multiple datasets can be queued in one run; the script asks you
to confirm each one individually before processing begins.
[TODO] function to implement:
1. copy metadata to h5 folders
2. generate report whether each dataset is compressed successfully


Directory layout
----------------
Only two files are exposed at the script root:
  - run_process_spim_and_compress_batch.bat   (this script)
  - run_process_spim_and_compress_batch_README.txt

All executables and their DLLs live in the bin\ subfolder:
  bin\Process_SPIM.exe        SPIM registration (CUDA)
  bin\stack2h5_v2.exe         h5 compression worker (MPI)
  bin\stack2h5_mpi.exe        older MPI worker (kept for reference)
  bin\mpiexec.exe             MPI launcher
  bin\*.dll                   CUDA / HDF5 / Intel runtime DLLs
  bin\Process_SPIM.pdb        debug symbols
  bin\stack2h5.readme.txt     notes for stack2h5

The script finds them automatically via BIN_DIR=bin. You normally
do not need to touch anything inside bin\.

Source data must live under the data\ folder. The script scans for
every directory whose name ends with "raw" and that contains at
least one .stack file.


Workflow
--------
1. Select server  (first prompt)
   Choose which server Process_SPIM should target. The selected
   value is passed to Process_SPIM.exe as the server_ind argument.
       1) .6   (index 6)
       2) .7   (index 7)
       3) .81  (index 81)   [default]
   Press Enter to accept the default (.81), or type 1 or 2. An
   invalid entry re-asks.

2. Prerequisite check
   Verifies that Process_SPIM.exe, stack2h5_v2.exe, and mpiexec.exe
   all exist in bin\.

3. Scan for datasets
   Searches data\*raw recursively. Every matching directory is
   collected into a candidate list.

4. Confirm each dataset
   For each candidate the script analyzes the .stack files and
   prints the full detected configuration:
       Sample file name, prefix, digit count, camera index,
       frame range, and both target directories.
   Then it asks:
       Include this dataset? [Y/n]
   - Press Enter (or any key except N/n) -> ADDED
   - Press N (or n)                    -> SKIPPED

5. Select processing mode  (after datasets are confirmed)
       1) Registration only   (raw -> registered)
       2) Compression only    (raw -> h5)
       3) Both                (registration then compression) [default]
   - Option 1 runs only Process_SPIM.exe.
   - Option 2 runs only stack2h5_v2.exe (MPI cores are used).
   - Option 3 runs both; if registration fails for a dataset,
     its compression is skipped and the script moves on.

6. Adjust MPI core count  (only when compression will run)
   Shows the current default (64). Press Enter to keep it, or
   type a different number (must be >= 2; at least 2 cores are
   required because one core is reserved as the MPI master).
   Skipped entirely in registration-only mode.

7. Serial processing loop
   For every confirmed dataset, in order:

     a) Analyze .stack files
        - Parse file-name prefix (e.g. TM)
        - Detect digit count of frame number (e.g. 7)
        - Extract camera index from _CM{n}_ (0 or 1)
        - Scan min / max frame number
        - Compute reference frame = (min + max) / 2

     b) [registration step] Process_SPIM.exe   (if selected)
        - Target directory:  <raw> -> <registered>
        - Created automatically if it does not exist.
        - Input is fed via a temporary text file.
        - In "Both" mode, a non-zero exit code skips compression
          for this dataset and continues to the next one.

     c) [compression step] stack2h5_v2.exe (MPI)   (if selected)
        - Target directory:  <raw> -> <h5>
        - Created automatically if it does not exist.
        - Executed as:
            bin\mpiexec.exe -n <cores> bin\stack2h5_v2.exe
        - Input values passed via stdin:
            1. Source folder (raw, trailing backslash)
            2. Target folder (h5,  trailing backslash)
            3. Digit count of file name
            4. Camera index (0 or 1)
            5. Min frame number
            6. Max frame number

   Step labels show [Step n/m] where m is the number of steps
   actually run for the chosen mode (1 or 2).

8. Completion summary
   Prints how many datasets were processed.


Configurable defaults (edit the .bat file)
------------------------------------------
  SERVER_IND  = 81      (server index passed to Process_SPIM;
                         overridden by the first prompt)
  EXT_REF     = 0       (0 = internal reference; 1 = external)
  RDIR        = .       (reference directory, unused when EXT_REF=0)
  MPI_CORES   = 64      (number of MPI cores for stack2h5_v2;
                         must be >= 2)
  BIN_DIR     = bin     (subfolder holding the exes + DLLs)


Important notes
---------------
- The server index and the registration/compression mode are both
  chosen interactively at the start of each run.
- The MPI core count is adjusted interactively only when a
  compression step will run.
- Ensure stack_dimension.log exists in each source directory
  before running the compression step (stack2h5 requirement).
- If a dataset fails during Process_SPIM in "Both" mode, its
  compression step is skipped so the remaining datasets can still
  be processed. In "Compression only" mode there is no
  registration step to fail.
- Directories passed to stack2h5_v2.exe end with a backslash (\)
  as required by that tool.
- At least 2 MPI cores are needed: 1 master + N-1 workers.
- If MPI jobs crash with more cores but succeed with fewer, other
  users may be occupying cores on the same server — reduce the
  count and retry.
- The exes load their DLLs from bin\ automatically; do not move
  DLLs out of bin\.


================================================================
  中文 (CHINESE)
  =================================================================

概述
----
此批处理脚本对每个选定的数据集依次完成 SPIM 配准和/或 h5 压缩：
  1. 通过 Process_SPIM.exe 进行 SPIM 配准（raw -> registered）
  2. 通过 stack2h5_v2.exe / MPI 进行 h5 压缩（raw -> h5）

所有处理均为串行 — 同一时间仅运行一个 GPU / MPI 任务。
一次运行可排队处理多个数据集；脚本会在处理开始前逐个询问确认。
[TODO] function to implement:
1. copy metadata to h5 folders
2. generate report whether each dataset is compressed successfully


目录结构
--------
脚本根目录仅暴露两个文件：
  - run_process_spim_and_compress_batch.bat   （本脚本）
  - run_process_spim_and_compress_batch_README.txt

所有可执行文件及其 DLL 位于 bin\ 子文件夹：
  bin\Process_SPIM.exe        SPIM 配准（CUDA）
  bin\stack2h5_v2.exe         h5 压缩工作进程（MPI）
  bin\stack2h5_mpi.exe        旧版 MPI 工作进程（保留备查）
  bin\mpiexec.exe             MPI 启动器
  bin\*.dll                   CUDA / HDF5 / Intel 运行时 DLL
  bin\Process_SPIM.pdb        调试符号
  bin\stack2h5.readme.txt     stack2h5 说明

脚本通过 BIN_DIR=bin 自动定位这些文件，通常无需手动改动 bin\ 内
的任何内容。

源数据必须位于 data\ 文件夹下。脚本会扫描每个以 "raw" 结尾
且包含至少一个 .stack 文件的目录。


工作流程
--------
1. 选择服务器（首个提示）
   选择 Process_SPIM 要使用的服务器。所选值作为 server_ind 参数
   传给 Process_SPIM.exe：
       1) .6   （索引 6）
       2) .7   （索引 7）
       3) .81  （索引 81）  [默认]
   按 Enter 接受默认值（.81），或输入 1 或 2。输入无效会重新询问。

2. 前置检查
   验证 Process_SPIM.exe、stack2h5_v2.exe 和 mpiexec.exe
   是否都存在于 bin\ 中。

3. 扫描数据集
   递归搜索 data\*raw。每个匹配的目录都会被收集到候选列表中。

4. 逐个确认数据集
   对于每个候选目录，脚本会分析其中的 .stack 文件并显示完整
   的检测信息：
       样本文件名、前缀、位数、相机编号、帧范围及两个目标目录。
   然后询问：
       Include this dataset? [Y/n]
   - 按 Enter（或除 N/n 外的任意键）→ 加入处理队列
   - 按 N（或 n）                    → 跳过

5. 选择处理模式（确认数据集之后）
       1) 仅配准   （raw -> registered）
       2) 仅压缩   （raw -> h5）
       3) 两者都做 （先配准后压缩）  [默认]
   - 选项 1 只运行 Process_SPIM.exe。
   - 选项 2 只运行 stack2h5_v2.exe（会用到 MPI 核数）。
   - 选项 3 两者都运行；若某数据集配准失败，则跳过其压缩步骤，
     继续处理下一个数据集。

6. 调整 MPI 核数（仅当需要压缩时）
   显示当前默认值（64）。按 Enter 保留，或输入其他数值
   （必须 >= 2；至少需要 2 个核，其中 1 个保留为 MPI master）。
   仅配准模式下会跳过此步。

7. 串行处理循环
   按顺序对每个已确认的数据集执行：

     a) 分析 .stack 文件
        - 解析文件名前缀（如 TM）
        - 检测帧编号的位数（如 7）
        - 从 _CM{n}_ 中提取相机编号（0 或 1）
        - 扫描最小 / 最大帧号
        - 计算参考帧 = (最小 + 最大) / 2

     b) [配准步骤] Process_SPIM.exe（若选中）
        - 目标目录：<raw> → <registered>
        - 如不存在则自动创建。
        - 通过临时文本文件传入参数。
        - 在「两者都做」模式下，若返回非零退出码，则跳过该
          数据集的压缩步骤，继续处理下一个数据集。

     c) [压缩步骤] stack2h5_v2.exe（MPI）（若选中）
        - 目标目录：<raw> → <h5>
        - 如不存在则自动创建。
        - 执行命令：
            bin\mpiexec.exe -n <核数> bin\stack2h5_v2.exe
        - 通过标准输入传入以下值：
            1. 源文件夹（raw，末尾带反斜杠）
            2. 目标文件夹（h5，末尾带反斜杠）
            3. 文件名位数
            4. 相机编号（0 或 1）
            5. 最小帧号
            6. 最大帧号

   步骤标签显示 [Step n/m]，其中 m 为所选模式实际运行的步骤数
   （1 或 2）。

8. 完成汇总
   显示共处理了多少个数据集。


可配置的默认值（编辑 .bat 文件修改）
------------------------------------
  SERVER_IND  = 81      （传给 Process_SPIM 的服务器编号；
                         会被首个提示覆盖）
  EXT_REF     = 0       （0 = 内部参考；1 = 外部参考）
  RDIR        = .       （参考目录，EXT_REF=0 时未使用）
  MPI_CORES   = 64      （stack2h5_v2 的 MPI 核数；必须 >= 2）
  BIN_DIR     = bin     （存放 exe 与 DLL 的子文件夹）


重要提示
--------
- 服务器编号与「配准/压缩」模式均在每次运行开始时交互选择。
- MPI 核数仅在有压缩步骤时才会交互调整。
- 运行压缩步骤前，请确保每个源目录下存在 stack_dimension.log
  （stack2h5 的要求）。
- 在「两者都做」模式下，若某数据集在 Process_SPIM 阶段失败，
  其压缩步骤将被跳过，其余数据集仍可继续处理；在「仅压缩」
  模式下没有配准步骤可言。
- 传给 stack2h5_v2.exe 的目录路径末尾带有反斜杠（\），
  以符合该工具的要求。
- 至少需要 2 个 MPI 核：1 个 master + N-1 个 worker。
- 如果 MPI 作业在较多核数时崩溃，但用较少核数可以成功，可能是
  服务器上其他用户正在占用部分核心 — 请减少核数后重试。
- 可执行文件会自动从 bin\ 加载所需 DLL，请勿将 DLL 移出 bin\。
