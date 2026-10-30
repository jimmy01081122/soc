# soc

RISC-V SoC 加自製 NPU 的研究專案。以 Gemmini（DAC 2021）為參考基準：

1. 用 SystemVerilog 重寫一顆和 Gemmini 指令集相容的 NPU，並在微架構上做優化。
2. 比較同一顆 NPU 整合在晶片內和外接 PCIe 的差異。

整體計畫見 [docs/plan.md](docs/plan.md)。
