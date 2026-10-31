# Vivado：Gemmini 的資源與時序評估（PYNQ-Z2／XC7Z020）

這個目錄放要在本地用 Vivado 合成的 Verilog，以及合成用的 TCL。目標是回答：
**8×8 的 Gemmini 放不放得進 XC7Z020，能跑多快？**

## 內容

| 路徑 | 說明 |
|---|---|
| `synth_ooc.tcl` | 合成腳本（out-of-context，可選擇再做 place & route） |
| `<CONFIG>/<TOP>/rtl/` | 從 Chipyard 產生的 Verilog 中，`TOP` 需要的檔案（SystemVerilog） |
| `<CONFIG>/<TOP>/files.txt` | 讀檔順序 |
| `<CONFIG>/<TOP>/lint.log` | 匯出時 Verilator 的檢查結果（沒有錯誤，代表檔案自足、沒缺模組） |
| `<CONFIG>/<TOP>/SOURCE.txt` | 這份 Verilog 對應的 Chipyard／Gemmini commit |

目前有：`Gemmini8x8RocketConfig/Gemmini`，也就是 8×8 陣列、64 KB scratchpad、32 KB accumulator 的 Gemmini 加速器本身（不含 Rocket 核心和 L2）。

重新產生：`scripts/export_vivado.sh CONFIG [TOP]`（需要先用 `scripts/build_sim.sh` 產生 Verilog）。

## 執行

在任一個空的工作目錄，先只做合成（幾分鐘到十幾分鐘）：

```bash
vivado -mode batch -source <repo>/vivado/synth_ooc.tcl -tclargs <repo>/vivado/Gemmini8x8RocketConfig/Gemmini 10.0
```

最後一個數字是時脈週期（ns），10.0 即 100 MHz。要再做 place & route，看真正的 Fmax：

```bash
vivado -mode batch -source <repo>/vivado/synth_ooc.tcl -tclargs <repo>/vivado/Gemmini8x8RocketConfig/Gemmini 10.0 impl
```

只合成的時序沒有走線延遲，數字偏樂觀；要引用 Fmax 請用 `impl` 之後的報告。若 100 MHz 就不過，可以改 12.0、15.0 重跑，看 slack 轉正的位置。

## 請回傳

工作目錄裡的 `*_utilization.rpt`、`*_utilization_hier.rpt`、`*_timing.rpt`（有 `impl` 時還有 `*_route_*`），以及 `*_ram.rpt`（新版 Vivado 才有）。放進 `results/vivado/` 並推上來，或直接把內容貼給我。

## 目標裝置（XC7Z020）的上限

| 資源 | 數量 |
|---|---|
| LUT | 53,200 |
| FF | 106,400 |
| BRAM（36 Kb） | 140（等於 280 個 RAMB18） |
| DSP48E1 | 220 |

## 預期結果（Yosys 的估計）

我用 Yosys 對同一份 Verilog 做過估計（`results/vivado/yosys_estimate_Gemmini8x8RocketConfig.md`，**不是 Vivado 的結果**）：
LUT 約 69,000（上限 53,200）、DSP48E1 306 個（上限 220）、FF 約 35,000、RAMB18 96 個。
也就是說，預設功能集的 8×8 Gemmini 很可能就已經超出 XC7Z020 的 LUT 和 DSP，所以 Vivado 的報告要看的是：
是不是真的超出、超出多少、哪些子模組吃最多（hierarchical utilization）。

## 看報告時請特別檢查

1. **BRAM 有沒有推成功。** Gemmini 的 scratchpad 和 accumulator 在 RTL 裡被切成一個個「位元組通道」（scratchpad 32 個 2048×8、accumulator 64 個 512×8，合計約 96 KiB）。Vivado 可能讓每個 512×8 的小記憶體各占一個 RAMB18，而不是併成寬的 BRAM，最壞情況 accumulator 就要 64 個 RAMB18。也可能被推成 LUTRAM 而吃掉大量 LUT。請看 `*_ram.rpt` 或 hierarchical utilization 裡 `mem` / `mem_0` 底下的 RAMB18／LUTRAM 數量。
2. **DSP 用量。** 8×8 陣列有 64 個 int8 乘加；另外 mvin／accumulator 的縮放用到浮點乘法，也可能吃 DSP。
3. **這只是加速器本身。** 沒有 Rocket 核心、沒有 L2。Chipyard 預設的 SoC 有 8 個 L2 bank，合計 512 KiB，已經占了 XC7Z020 約 630 KB BRAM 的八成，所以完整的預設 SoC 不可能和 Gemmini 一起放進去；FPGA 版本需要更小的 SoC 設定（去掉或縮小 L2、縮小 L1），這是之後要做的事。

## 注意

- `synth_ooc.tcl` 我沒有在 Vivado 上跑過（這個環境沒有 Vivado），匯出的 Verilog 只用 Verilator 檢查過語法與完整性。如果腳本出錯，請把錯誤訊息原樣貼給我。
- 這份 Verilog 用到 SystemVerilog 的 `'{...}` 賦值樣式和多維封裝陣列，Vivado 支援；但 Yosys 不支援前者（我只在暫存副本裡轉換後做過估算）。
