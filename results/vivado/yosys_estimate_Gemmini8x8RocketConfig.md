# Yosys 資源估計：Gemmini8x8RocketConfig／Gemmini（XC7Z020）

**這是估計，不是 Vivado 的結果。** 用 Yosys 0.69 的 `synth_xilinx -family xc7 -flatten` 對匯出的
`vivado/Gemmini8x8RocketConfig/Gemmini` 合成（2026-10-31，約 26 分鐘）。Yosys 與 Vivado 的對應演算法不同，
LUT 數字通常差一成到三成；它的用處是提早看出量級，不能取代 Vivado 的報告。

為了讓 Yosys 讀得進去，只在暫存副本裡把 SystemVerilog 的賦值樣式 `'{...}` 改成串接 `{...}`
（賦值對象是封裝向量，兩者等價）；匯出的檔案本身沒有改。

| 資源 | Yosys 估計 | XC7Z020 上限 | 占比 |
|---|---:|---:|---:|
| LUT（LUT1–LUT6） | 69,048 | 53,200 | 130% |
| 分散式 RAM（RAM32M，每個約占 4 個 LUT） | 688 個 | — | — |
| 移位暫存器（SRL16E） | 216 個 | — | — |
| FF（FDRE＋FDSE） | 35,214 | 106,400 | 33% |
| DSP48E1 | 306 | 220 | 139% |
| RAMB18E1 | 96（= 48 個 36Kb） | 280（= 140 個 36Kb） | 34% |
| CARRY4 | 4,666 | — | — |

說明：

- LUT 和 DSP 都超出 XC7Z020 的容量。差距大過工具間常見的誤差，所以預期 Vivado 也會超出；請以 Vivado 的報告為準。
- RAMB18 的 96 個，正好等於 scratchpad 32 個位元組通道加 accumulator 64 個位元組通道各占一個：
  Yosys 沒有把 accumulator 的 512×8 通道併成寬的 BRAM。Vivado 可能不同。
- 報告中的 IBUF（1031）／OBUF（296）是 Yosys 替每個埠加的 I/O 緩衝，Vivado 的 out-of-context 模式不會有，請忽略。
- 這是 Gemmini 的預設功能集：兩種 dataflow、浮點縮放、訓練用卷積、max-pool、非線性激活。
