# 参考与许可边界

MoonTDMS 是原创 MoonBit 实现，核心只依赖 moonbitlang/core（Apache-2.0）。本仓库整体采用 MIT；没有将第三方实现重新标为 MIT。

| 参考 | 版本/固定提交 | 用途及边界 |
| --- | --- | --- |
| [NI TDMS File Format Internal Structure](https://www.ni.com/en/support/documentation/supplemental/07/tdms-file-format-internal-structure.html) | 2026-11-11 读取 | lead-in、ToC、元数据、通道分块和类型语义；不复制文档大段文字、表格或图示 |
| [NI TDMS overview](https://www.ni.com/en/support/documentation/supplemental/06/the-ni-tdms-file-format.html) | 2026-11-11 读取 | 测量文件用户需求与层级依据 |
| [npTDMS](https://github.com/adamreeve/npTDMS) | 源码研究 `939f32a4bb37cc7404eab4255a305ed54ca98f1d`；运行对照 1.10.0 | LGPL-3.0-or-later；阅读格式行为、writer、timestamp 和边界。仅作为独立开发测试依赖，不复制或派生其源码、测试、fixture，不随 MoonCakes 包分发 |
| [NumPy](https://numpy.org/) | 测试 2.3.5 | BSD-3-Clause，差分脚本开发依赖，不是 MoonBit 运行依赖 |

测试文件和 Python struct 测量字节由本项目自行构造。npTDMS 生成的数据仅在测试进程内存中使用；没有把上游 fixture 纳入发行包。兼容 npTDMS 的字符串索引长度标记 20 是观测到的互操作行为，自身写出遵守长度 28 的规范索引。

不宣称与 NI 官方认证、商标授权或全量 npTDMS 功能等价。DAQmx、自动缩放、文件流式 I/O 等明确不在范围内。
