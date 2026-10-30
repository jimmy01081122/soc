# Verilator 模擬器建置：Gemmini8x8RocketConfig

由 `scripts/build_sim.sh` 產生，2026-10-30 14:12 UTC。

| 項目 | 值 |
|---|---|
| 結果 | ok |
| 平行度（make -j） | 4 |
| 總耗時 | 250 秒 |
| 建置期間最低可用記憶體 | 10287 MiB（共 16091 MiB） |
| 建置期間最高 swap 用量 | 0 MiB |
| 磁碟增加 | 603 MiB |
| generated-src 大小 | 441M |
| 模擬器執行檔 | 15M |

各階段時間（距建置開始的秒數，每 5 秒取樣一次）：

- 121 秒：Verilog 已產生（firtool 完成）
- 166 秒：Verilator 轉換完成，開始編譯 C++
