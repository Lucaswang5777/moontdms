# MoonTDMS

纯 MoonBit 的 TDMS 2.0 测量数据交换库，模块 `Lucaswang5777/moontdms@0.1.0`。它把内存中的 TDMS 字节转换成有类型的对象、属性和通道，供采集接入、实验室数据整理和报表系统复用。核心库只依赖 MoonBit core，不依赖 Python、NI 运行时或本机动态库。

## 已实现范围

- 读取版本 4713 的 TDMS 2.0 lead-in、对象路径、属性、原始索引和多段数据；检查偏移与数据边界。
- 属性覆盖、缓存索引复用、数据参与状态切换、无元数据追加段、完整重复 chunk、新对象列表和重排。
- 连续与交错布局、大小端；交错布局支持混合宽度但要求各通道等长，字符串只能连续存储。
- I8/I16/I32/I64、U8/U16/U32/U64、F32/F64、Boolean、UTF-8 字符串和 TDMS 时间戳。带单位的单/双精度类型码映射为 F32/F64；保留对象属性，不执行缩放。
- 写出规范完整元数据段和多段文件，支持交错写出；选取/裁剪通道并重写文件。
- 波形相对时间轴、有限数值摘要、长表 CSV、版本化 JSON 协议与命令入口。
- 输入/输出字节、段、对象、属性记录、单字符串 UTF-8 字节、累计样本数预算；错误分为 `Invalid`、`Unsupported`、`Budget`。

这是内存交换库。读取会物化全文件，不提供文件系统、硬件采集或真正的流式处理。`inspect` 仅检查段边界，不替代 `read` 的元数据/内容验证。库不保留原始字节布局；重写保留支持范围内的语义。

## 环境与安装

验证工具链：`moonc v0.10.18+6c83a7f62`，`moon 0.1.20261028 (e1e1f15)`。CI 固定安装 `0.10.18+6c83a7f62`。目标为 wasm-gc、wasm、js、native；JS 需要 Node.js，Linux native 需要 C 工具链。本机 Windows 未安装 MSVC/Windows SDK，native 的执行结果以 Linux CI 为准。

在新 MoonBit 模块中固定版本：

```sh
moon add Lucaswang5777/moontdms@0.1.0
```

在消费者 `moon.pkg` 中导入：

```moonbit
import {
  "Lucaswang5777/moontdms" @tdms,
}

pkgtype(kind: "executable")
```

## 可运行快速开始

消费者 `main.mbt`：

```moonbit
fn main raise {
  let doc : @tdms.Document = {
    objects: [@tdms.DataObject::new(
      @tdms.ObjectPath::channel("run", "voltage"),
      kind=@tdms.F64,
      values=[@tdms.Real(1.25), @tdms.Real(1.5)],
    )],
  }
  let bytes = @tdms.write(doc)
  let restored = @tdms.read(bytes)
  println(restored.csv())
}
```

```sh
moon run . --target js
```

输出 CSV 含 `run, voltage` 通道的两个样本，值为 1.25 和 1.5。路径和字符串字段始终加引号，行结尾为 CRLF。库接收 `Bytes`，读取真实文件的 I/O 由宿主程序处理。

## 三个下游工作流

| 用户与入口 | 输入与处理 | 可断言结果 |
| --- | --- | --- |
| 采集/测试接入作者：`examples/ingest` | 构造带单位的采集文档，写为 TDMS，再读取类型化通道 | 三个电压样本与 V 单位保留 |
| 实验室流水线：`examples/crop` | 选择温度通道样本 `[1,3)`，重算波形偏移，写回 TDMS | 两个样本，对应相对时刻 10.25、10.5 |
| 报表系统：`examples/report` | 对电流通道求摘要并输出 CSV | 均值 4、最小值 2、最大值 6，CSV 含单位和样本 |

```sh
moon run examples/ingest --target js --deny-warn
moon run examples/crop --target js --deny-warn
moon run examples/report --target js --deny-warn
```

这些示例通过公开接口构建，不依赖库的私有测试函数。每个程序对输出执行断言。

## API 和精度约定

公开接口清单见 [pkg.generated.mbti](pkg.generated.mbti)，模型和处理顺序见 [ARCHITECTURE.md](ARCHITECTURE.md)。

- `read(bytes, limits=...)` / `inspect(bytes, limits=...)`：完整解码 / 段边界检查。
- `write(doc, big_endian=false)` / `write_interleaved(doc, ...)` / `write_segments(parts, ...)`：输出 TDMS 字节。多段写出使用每段完整对象列表与元数据。
- `doc.find(path)`、`obj.property(name)`、`doc.channel_paths()`：查询测量文档。
- `doc.select(paths, start=0, end=...)`：每个选中通道使用同一半开样本区间；省略 end 时取各自末尾。保留相关 root/group，复制数组；裁剪非零起点时用 `wf_increment` 调整 `wf_start_offset`。
- `obj.waveform()`、`axis.at(i)`、`axis.values(max_samples=...)`：正有限增量与有限偏移，相对时间为 `offset + i * increment`。`wf_start_time` 原始时间戳单独保存。
- `obj.summary()`：有限样本的总体方差、均值、极值与 RMS；统计排除 NaN/Inf 并计数，空集合返回 None。中间数值溢出返回错误。
- `doc.csv(waveform_time=false)`：列为 group、channel、index、value、unit、relative_time。启用波形列时每个通道均须有合法波形增量；单位来自 `unit_string`，时间量纲由调用方属性约定。

I64/U64 与时间戳原字段始终保留整数精度。时间戳为 1904-01-01 纪元有符号秒和 64 位无符号秒小数；大端时间戳按 seconds/fractions 写入，小端按 fractions/seconds 写入。`unix_seconds()`、`as_double()` 和统计摘要是 Double 近似转换，大整数可能损失低位；CSV 整数文本和 JSON 十进制字符串保持精确。CSV 时间戳为 `seconds:fractions`，不冒充 ISO 时间。

`DataObject` / `Document` 含可变数组，调用方须避免并发修改正在处理的数据。`select` 的路径、属性与样本数组复制；值自身不可变。

## JSON 协议和 CLI

```sh
moon build --target js --deny-warn
node _build/js/debug/build/cmd/main/main.js '{"protocol":"moontdms/1","op":"encode","objects":[{"path":"/\u0027g\u0027/\u0027c\u0027","type":3,"values":["1","2"]}]}'
```

POSIX shell 示例；PowerShell 建议由脚本通过参数数组传递 JSON，避免引号解释差异。返回 `{"protocol":"moontdms/1","result":{"hex":"..."}}`。错误输出含 `error` 字符串并以非零状态退出；库 `process_json` 则抛出 `TdmsError`。命令仅接收一个 JSON 参数，受 OS 命令行长度限制，大文件用库 API。

| op | 字段 | result |
| --- | --- | --- |
| encode | objects，可选 big_endian/interleaved | hex |
| decode | hex | objects |
| inspect | hex | segments |
| select | hex、paths，可选 start/end | hex |
| csv | hex，可选 waveform_time | csv |

对象字段：`path`、`type`（TDMS 数值码，root/group 为 null）、`values`、`properties`。属性为 `{name,type,value}`。所有有/无符号整数值使用十进制字符串；浮点用 JSON number 或 `"NaN"`/`"Infinity"`/`"-Infinity"`；布尔用 JSON boolean；时间戳用 `{"seconds":"...","fractions":"..."}`。拒绝重复 JSON key，嵌套深度限 32。默认预算见 `Limits::default()`。

## 预算与已知限制

默认 max_bytes=64 MiB、max_segments=10000、max_objects=10000、max_properties=100000、max_string_bytes=1 MiB、max_samples=4000000。跨段累计样本包含所有通道、所有重复 chunk；属性预算按出现的记录累计，而非最终去重数量。写出/选择会验证调用方构造的类型、路径与字符串预算。

`max_bytes` 约束单次输入或生成的输出字节，不是进程峰值内存保证。数组、JSON、临时缓冲与复制会额外分配；JSON 的请求上限按 UTF-16 code units 检查，hex 与 JSON 响应会膨胀。生产宿主仍须设置请求/并发限制。未提供性能或覆盖率百分比承诺。

明确不支持 TDMS 1.0（4712）、DAQmx 原始块与缩放、扩展/复数浮点、XML TDM、索引 sidecar、NI 隐式缩放、硬件驱动、尾部不完整 chunk 恢复、unfinished segment sentinel、跨段改变同一通道类型或端序、`name` 属性触发的对象重命名。这些输入返回错误。读取兼容 npTDMS 1.10.0 的字符串长度标记 20，但仍读取并校验其 8 字节总大小；自身字符串索引写出标记 28。

CSV 为数据交换文本，不执行电子表格公式转义；不可信数据导入电子表格时由宿主采用文本列策略。

## 验证与开发

```sh
moon info --target all
moon fmt --check
moon check --target js --deny-warn
moon test --target js --deny-warn
moon build --target js --deny-warn
python -m pip install numpy==2.3.5 npTDMS==1.10.0
python scripts/differential.py
python scripts/cli_smoke.py
python scripts/audit.py
```

将 target 分别替换为 wasm-gc、wasm、js、native 进行四后端验证。当前 32 个 MoonBit 测试块含标量边界、大小端、Unicode、重复 chunk、属性覆盖、对象重排、失效后恢复索引、全部前缀截断、预算与恶意偏移/类型/布尔/字符串检查。82 个独立 Python 差分样本使用 `struct` 自建字节和 npTDMS 1.10.0 写出数据，双向核对通道值和属性。npTDMS/numpy 仅为开发测试依赖。

[CI](https://github.com/Lucaswang5777/moontdms/actions) 会运行四后端和三个工作流；实际状态以对应提交的绿色运行记录为准。[查重与选题记录](docs/competition/duplicate-check.md) 说明检索范围与邻近项目边界，不代表生态绝对唯一。

## 许可与参考

MIT，见 [LICENSE](LICENSE)。原创实现依据 NI 公开规范；npTDMS 的 LGPL 代码仅供行为研究/外部测试，没有移植或复制其源码与测试 fixture，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。AI 辅助实现与验证披露见 [AI_USE.md](AI_USE.md)。
