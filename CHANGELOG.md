# 变更记录

## 0.2.0

- 新增 DAQmx analog/digital raw scaler、typed channel、多 buffer/重复 chunk 解码及精确原始采样 API。
- 有界 NI 缩放图解释，支持 Linear/Polynomial/Table/Add/Subtract/AdvancedAPI 与层级继承；规范化输出避免重复缩放。
- 原始流裁剪与规范化重写保留 scaler/NI 属性/波形时标；新增独立合成文件、公共 API 工作流与99场景验证。
- 40 个 MoonBit 测试块；四后端 CI 加入 DAQmx 演示与差分。完整标准终点和未完成项保留在覆盖矩阵。

## 0.1.0

- 原创 TDMS 2.0 读写与有界校验，支持大小端、连续/交错布局、多段属性和索引状态。
- 精确整数/时间戳、通道选取裁剪、波形轴、摘要和 CSV。
- moontdms/1 JSON 命令协议，三个公开 API 下游程序。
- 与 npTDMS 1.10.0 的 82 个独立互操作用例，包含短字符串索引标记兼容修正。
