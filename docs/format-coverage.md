# TDMS 2.0 完整兼容目标与当前覆盖

## 标准终点

格式目标是 NI 公开 TDMS File Format Internal Structure 中的版本 4713：按 ToC/lead-in/对象元数据/原始索引重建通道，覆盖普通及 DAQmx 原始流，并依据采集缩放信息解释物理量；裁剪后可由独立读取器恢复等价的选中样本、单位与时间轴。完整目标还包括合法的数据类型、各类传感器缩放和合法分段/尾块表达。兼容验收必须逐类有独立文件、参考解释及双向重读证据，不能用测试总数替代覆盖。

本表保留上述完整终点。0.2.0 完成下列 DAQmx 原始→物理→裁剪链路，但**尚未实现完整 TDMS 2.0 标准终点**。未完成行是实际技术差距，并非通过缩小标准定义消除。

| 标准维度 | 当前实现和可复现证据 | 余项 |
| --- | --- | --- |
| 4713 lead-in/元数据 | 大小端、有界偏移、路径/属性、多段索引复用；普通差分脚本 | unfinished segment sentinel、合法不完整尾块恢复 |
| 普通通道 | 有/无符号 8/16/32/64 位、F32/F64、Boolean、字符串、精确时间戳；连续/交错 | extended precision、complex；跨段改变类型/端序、对象重命名 |
| DAQmx 原始索引 | 0x1269 analog、0x126A digital；另识别 NI 文档 0x1369；typed/raw；多 buffer、scaler、通道；重复完整 chunk、raw-only 索引复用 | 非零 sample-format bitmap；buffer 样本数不一致 |
| 原始值精度 | numeric DAQmx scaler 10 类、双端序均差分；U64/I64 精确字符串；digital bit 0/9；timestamp 编解码复用通用标量实现 | DAQmx timestamp 尚无独立参考差分证据，不宣称该项兼容已验收 |
| 缩放图 | raw scaler、Linear、Polynomial、Table、Add、Subtract、AdvancedAPI；有界拓扑求值；通道/组/文件继承；显式 scaled 标记 | RTD、Strain、Thermistor、Thermocouple；已有样本后修改缩放属性明确拒绝 |
| 裁剪与写回 | 所有 scaler 同区间；保留属性、类型、id、精确原始值；更新波形偏移；独立 npTDMS 重读 raw/physical 两种输出 | 不保留输入 padding、bit packing、原 buffer/段布局，不保证逐字节复现 |
| 错误与预算 | 截断/恶意偏移、索引/图越界、重复 scaler、环、未知缩放拒绝；累计 raw 和图中间数组样本预算 | 预算不是进程峰值内存保证；无真正流式文件 I/O |

## 本轮可复验链路

`fixtures/daqmx/voltage.tdms` 是本项目独立 struct 合成的 ADC 采样，不是硬件实测；`examples/daqmx` 使用完全相同字节。原始 counts [-100,0,100,200] → 线性物理量 [-23.5,1.5,26.5,51.5] V → 裁剪 [1,3) → 原始 [0,100] 与物理量 [1.5,26.5] V，时间偏移 0.51。`scripts/daqmx_differential.py` 用 npTDMS 1.10.0 独立读取输入、raw 重写、physical 重写，覆盖 99 个场景；该数字含拒绝路径与重写操作，不代表 99 种标准特性或 99 份硬件文件。

完整兼容闭环仍需补齐所有余项及对应独立文件，不把本次局部验证描述成全标准认证。
