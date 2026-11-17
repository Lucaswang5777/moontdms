# 原始采样到裁剪重写

输入 `fixtures/daqmx/voltage.tdms` 具有版本4713、DAQmx raw ToC、I16 scaler 0 和完整线性缩放属性。它由本项目 Python struct 构造，属于可重复的合成测试数据。

1. 宿主读取文件 Bytes 后调用 `read_acquisition`；`raw_channel(ObjectPath::channel("acq", "voltage"))` 得到 counts [-100,0,100,200]，元数据保存 `NI_Number_Of_Scales=2`、scale 1 Linear、input=0、slope=0.25、intercept=1.5、unit_string=V。
2. 调用 `physical()`：最后缩放节点作为输出，得到 [-23.5,1.5,26.5,51.5] V。结果是普通 Document，并标记已缩放，原 Acquisition 的 counts 不变。
3. 调用 `select([path], start=1, end=3)`：同时选取 scaler 原始流，结果 [0,100]；wf_start_offset 从0.5变成0.51，wf_increment仍是0.01。
4. 调用所选 Acquisition 的 `write(big_endian=false)` 保存原始采样文件；或 `write(selected.physical())` 保存已转换物理量文件。前者仍有 scaler 与 NI 属性，后者普通值为 [1.5,26.5] V。
5. 用 npTDMS 1.10.0 独立读取两种输出，断言原始 scaler 切片、物理值、单位和时间属性。`scripts/daqmx_differential.py` 自动执行这些断言，并覆盖 LE/BE 输出与数值边界。

运行 `moon run examples/daqmx --target js --deny-warn`，或把 target 换成 wasm、wasm-gc、native。示例的每一步都有断言，输出包含上述结果。编译后的 JSON CLI 也支持 `raw`、`physical`、`crop_raw`，字段见 README。

这是保持采样语义的规范化重写；原始 bit packing、padding、buffer 与段布局可变化。未知传感器缩放可 raw 读写，物理解释明确报错。全部未完成标准项见 format-coverage.md。
