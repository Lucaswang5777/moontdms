# MoonTDMS 选题与语义查重记录

检索日期：2026-11-11。结论仅覆盖本次公开检索和实际阅读范围，不代表绝对唯一或官方认可。项目为原创 TDMS 2.0 交换库，使用 MIT 许可证；参考公开标准和行为，不复制相邻项目实现。

## 候选与硬淘汰

三个不同领域的初始候选均先核对成熟软件与真实用户任务，再阅读 MoonBit 相邻项目核心源码与测试。出现直接能力重合即淘汰，不用评分推翻硬门槛。

|候选与用户任务|成熟设计基线与最小核心|实际阅读的 MoonBit 项目、版本与源码|判断|
|---|---|---|---|
|层级状态机：设备和交互流程的层级状态、事件冒泡和历史恢复|SCXML/statechart；层级转移、guard/action、history，验收完整事件轨迹|Lyl66655/moonbit-workflow-engine@0.1.4；原 Lyl66655/moonbit-statemachine 重定向至 WmmmQa/moonbit-statemachine，9477d29c1a73d4d57566f8b30e4b8dd94c9b1085 的 hsm/engine.mbt 与 hsm/hsm_test.mbt；2026-08-16 维护|层级、冒泡、history、guard/action 直接重合，淘汰|
|几何约束三角剖分：网格构建者输入边界和约束边得到有效三角网|约束 Delaunay；点插入、约束恢复、几何不变量和退化测试|walkzzz/moon-geometry@0.251.0，2b59b8b953ecf8764ef6009dc2f7697f2eec539a 的 constrained_delaunay 实现及测试；2026-11-05 维护|已有直接实现，淘汰|
|非线性曲线拟合：科研用户输入观测与模型，得到有界稳健拟合参数|Levenberg–Marquardt；残差、Jacobian、阻尼、有界/稳健迭代与合成数据恢复|yyyt0807/curvefit@0.2.1，yyyt0807/moonbit-curvefit 的 43d980b5429d9e5780adf7007fe7c278736104db，solver.mbt 与 solver_test.mbt；2026-10-01 维护|已有 bounded robust LM，淘汰|

额外检查并排除 GDSII 与 FCS：tanglong2001-2/moonbit-gdsii 的 e7af60d1f4353e15388cd94d6f69d0c24b5d1115（parser 与 deep06 测试，2026-11-05 维护）；mawei2018/fcs@0.2.2 对应 moonbit-fcs 的 55330e9a6d71873d7b5a0a0531b8f168afe77e4b（parse 与 core 测试，2026-09-30 维护）。MoonCakes 无结果不能替代 GitHub 语义检查。

## TDMS 需求与可用核心

NI 的 TDMS 格式用于测试、测量和采集数据交换；公开二进制规范与活跃的 npTDMS 提供成熟行为基线。用途依据来自标准说明、可读取的参考软件和可复现文件互操作，不把推测人数或下载量当作需求证据。

1. 实验数据接入者输入 TDMS 字节，读取分组、通道、属性与精确整数，获得可继续计算的类型化模型；examples/ingest 给出完整接入流程。
2. 台架分析者输入测量文件和通道/样本区间，按路径裁剪并调整波形时间偏移，再写回可独立读取的 TDMS；examples/crop 覆盖这一闭环。
3. 数据管道开发者读取多通道文件，执行有限值汇总和 CSV 导出，或通过版本化 JSON 命令协议集成其他语言；examples/report 与 CLI 验证端到端输出。

模型由文档、对象路径、属性和带精确标量类型的通道组成。最小可用核心包含 TDMS 2.0 分段解析、元数据覆盖、raw index 复用、大小端、连续与交织布局、完整元数据写出、字符串与 timestamp，以及有界输入校验。选择/裁剪、波形、汇总与 CSV 构成真实下游复用能力。

明确不做 TDMS 1.0、DAQmx 原始缩放、extended/complex、XML TDM、sidecar、硬件驱动、NI 自动缩放、out-of-core、未完成尾段恢复、跨段类型或字节序改变。细项与精度限制以根 README 为准。

## 检索矩阵与限制

- MoonCakes：limit 100，TDMS、LabVIEW、TDM、DAQmx、nptdms、TDMS segment 均未发现直接模块；measurement acquisition 仅得到 opentelemetry 等邻近项。raw data index 返回 74 个模糊结果，未逐项深读，不能据此声称全生态穷尽。
- GitHub repositories：limit 100，TDMS 与 MoonBit 的三种组合查询无直接结果，LabVIEW/acquisition 组合亦无直接结果。measurement + MoonBit 返回 metrology、measure、SenWeave、lesion-followup、roomacoustics 五个邻近方向。
- GitHub code：DAQmx、wf_increment、kTocMetaData、tdsTypeDoubleFloat 组合未发现 MoonBit TDMS 实现；TDMS 的 9 个结果与 TDSm 的 7 个结果包含生成 Win32、证书/base64、ffmpeg 二进制 fixtures 等噪声，未形成直接替代。
- 实读官方 awesome MoonBit README，未发现 TDMS；注册表 MoonC3D、MoonLAS、MoonWell、MoonNRRD 完整指纹已核对，C3D 的公开 API、header 与 binary 实际阅读，能力与格式边界不同。
- 发布前复核：TDMS language:MoonBit 无直接仓库，MoonCakes TDMS 无直接模块；目标 Lucaswang5777/moontdms GitHub 仓库及 MoonCakes 0.1.0 在创建前均返回权威不存在。

本次公开检索可能漏掉未索引、私有、改名或之后新增的项目。结论是所查范围内未发现成熟 MoonBit TDMS 直接替代；邻近二进制格式工具不等同于本项目。

## 参考与客观验收

- NI：TDMS File Format Internal Structure 与 The NI TDMS File Format；标准参考，链接与许可边界见 THIRD_PARTY.md。
- npTDMS：研究源码 939f32a4bb37cc7404eab4255a305ed54ca98f1d，2026-11-07 维护，LGPL-3.0-or-later；仅行为参考，未复制源码。差分使用固定 npTDMS 1.10.0 与 NumPy 2.3.5。
- 验收包含 32 个 MoonBit 测试块、82 个独立构造/参考实现双向互操作场景、精确通道集合/类型/属性/值检查、CLI 成功与拒绝路径、三个可运行工作流和四后端真实 CI。当前远程 CI 状态请查仓库 Actions，不以本地通过代替。
- 独立参考数据暴露的字符串索引 marker 20/28 差异已纳入回归；writer 保持规范的 28。整数与 timestamp 保留原始精确表示；Double 汇总的低位损失边界有明确说明。

评分为工程判断，非用户调查或评委评分：广度、用户任务、复用、低重合风险、实现深度、可验证性、工期、维护成本八项依次为 4/4/5/4/5/5/4/4，总计 35/40。已硬淘汰的候选不参加分数翻盘。最终交付是否通过，以公开源码、测试、CI、精确版本新消费者和私有审计的真实结果为准。
