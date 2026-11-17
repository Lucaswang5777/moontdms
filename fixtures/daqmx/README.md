# DAQmx 独立字节样本

`voltage.tdms` 由本项目 scripts/daqmx_differential.py 的 Python struct 构造（MIT），不含真实采集/个人数据，不来自 npTDMS 上游 fixture。

4713 / LE / format-changing raw scaler I16 / four counts [-100,0,100,200]。
NI 缩放图：scaler 0 → linear scale 1，V = count × 0.25 + 1.5。
物理值 [-23.5,1.5,26.5,51.5] V；采样间隔0.01，起点0.5。
裁剪 [1,3) 后 count=[0,100]、V=[1.5,26.5]、起点0.51。

`examples/daqmx` 嵌入相同文件的十六进制，在四后端无需文件系统即可运行。差分脚本用 npTDMS 1.10.0 独立读取原文件、raw重写和物理值重写。
