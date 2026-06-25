已创建 run_spim.bat。逻辑如下：

  自动化流程

  1. 查找源目录 — 扫描data/目录下所有以 raw 结尾且包含 .stack 文件的文件夹；多个时让用户选择
  2. 生成目标目录 — 将 raw 替换为 registered，与源目录在同一父目录下
  3. 解析文件命名 — 从第一个 .stack 文件自动识别：
    - 前缀（如 TM）
    - 帧编号位数（如 7）
    - 相机编号（从 _CM0_ 或 _CM1_ 提取）
  4. 扫描帧范围 — 遍历所有匹配 *_CM{cam}_CHN00.stack 的文件，找出最小/最大帧号
  5. 计算中间帧 — (min + max) / 2 作为参考帧
  6. 显示确认 — 列出所有检测到的参数，等待用户确认
  7. 运行程序 — 将参数写入临时文件，通过 < 重定向传给 Process_SPIM.exe

  使用方式

  将 run_spim.bat 放在与 Process_SPIM.exe 同一目录下，双击运行即可。程序默认：
  - server_ind = 7
  - extRef = 0（内部参考，使用中间帧）
  - rdir = .（不用外部参考时随便给一个即可）

  注意事项

  - 需要用户手动指定 server_ind 如果不是 7 的话——目前是硬编码默认值，你可以改成实际常用的值
  - 如果 camera 或命名格式不是 TM{frame}_CM{cam}_CHN00.stack，脚本的解析逻辑需要调整（代码里 fname_head/fname_tail
  是写死的，见 kernel2.cu:242-245）