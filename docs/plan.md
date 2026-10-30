# RISC-V SoC + 自製 NPU 開發計畫

版本 v0.1（2026-10-30）。這份是整體計畫；NPU 的詳細規格在第 2 階段另寫一份。

## 0. 摘要

- 參考論文是 **Gemmini**（Genc et al., "Gemmini: Enabling Systematic Deep-Learning Architecture Evaluation via Full-Stack Integration", DAC 2021, arXiv:1911.09925v3）。
- 這個專案要回答兩個問題：
  1. **NPU 優化**：用 SystemVerilog 重寫一顆和 Gemmini 指令集相容的 NPU，在微架構上做簡易優化，能比 Gemmini 好多少（效能、FPGA 資源、Fmax）？
  2. **整合方式**：同一顆 NPU 放在晶片內（RoCC 或 SoC 匯流排）和外接 PCIe（DMA 受 PCIe 影響）的差異有多大？這一題排在最後。
- 平台：Chipyard（Rocket + RoCC）、Verilator 跑 baremetal 的 cycle-accurate 模擬、Spike + libgemmini 當功能參考、Vivado 對 xc7z020（PYNQ-Z2）合成。
- 不用 FireSim：手上只有 PYNQ-Z2，FireSim 不支援。

## 1. 已定的事

| 日期 | 項目 | 決定 |
|---|---|---|
| 10-30 | 參考論文 | Gemmini（arXiv:1911.09925v3） |
| 10-30 | SoC 框架 | Chipyard：Rocket 核心，NPU 經 RoCC 接入 |
| 10-30 | NPU 語言 | SystemVerilog；Chisel 只用在整合的膠水 |
| 10-30 | NPU 指令集 | 和 Gemmini 相容（先做子集），只改微架構 |
| 10-30 | 優化方向 | 先用 Gemmini 做 profiling，看瓶頸再決定 |
| 10-30 | FPGA | 只有 PYNQ-Z2；主力是 Verilator baremetal 加 Vivado 合成，上板是選做 |
| 10-30 | Vivado | 由你在本地手動操作；這邊提供檔案清單與 TCL 範本，你回傳報告 |
| 10-30 | Workload | MLPerf Tiny 加代表性單層 |
| 10-30 | PCIe | 要做，含硬體與 baremetal driver 的開銷；排在最後 |
| 10-30 | 開發環境 | 目前這個雲端環境（見 §3.3） |
| 10-30 | platform 專案 | 只當旁觀參考，不耦合（見 §9.6） |

## 2. 參考基準：Gemmini 重點

以下對照過 Gemmini 與 Chipyard 的原始碼和文件（2026-10-30）。

- **主機 CPU**：Rocket（in-order RV64GC）或 BOOM，放在 Chipyard 裡，用 Chisel 寫。
- **接法**：RoCC，CPU 用自訂指令（custom opcode）下命令。
- **指令**：
  - 資料搬移：`mvin`／`mvin2`／`mvin3`、`mvout`
  - 設定：`config_ex`、`config_mvin`、`config_mvout`、`config_norm`
  - 計算：`preload`、`compute_preloaded`、`compute_accumulated`
  - 其他：`flush`（清 TLB）
  - 迴圈：`loop_ws`、`loop_conv_ws`（硬體展開大矩陣與卷積）
- **加速器內部**：
  - 兩層的 systolic array（tile 內是組合邏輯，tile 之間有 pipeline 暫存器）
  - 支援 WS 與 OS 兩種 dataflow
  - 軟體管理的 scratchpad 和 accumulator，每一列 DIM 個元素
  - load／execute／store 三條 pipeline 彼此解耦，用 ROB 追蹤相依
  - DMA 走 TileLink，和 CPU 共用 L2
  - DMA 用虛擬位址，有自己的 TLB，miss 時借 CPU 的 PTW
- **預設設定**：16×16 int8 陣列、scratchpad 256 KB、accumulator 64 KB；`mvin` 與 accumulator 的縮放用浮點。
- **軟體**：
  - `gemmini.h`：分塊 matmul／conv 函式
  - gemmini-rocc-tests：baremetal、pk、Linux 三種版本
  - Spike 擴充 libgemmini：功能模擬，不給效能數字
- **論文論點**：加速器要放在完整的 SoC 裡評估。L2 競爭、OS、虛擬記憶體、軟體堆疊都會明顯影響最終效能。
- **README 的提醒**：完整 DNN 在 Verilator 上要跑好幾天，官方建議用 FireSim。我們沒有 FireSim，所以 workload 要縮小（§6）。

## 3. 平台與工具

### 3.1 工具

| 用途 | 工具 | 備註 |
|---|---|---|
| SoC 產生器 | Chipyard | 版本照 Gemmini README 指定的組合；`build-setup.sh` 跳過 FireSim（`-s 6 -s 7`）與 FireMarshal（`-s 8 -s 9`） |
| cycle-accurate 模擬 | Verilator | 只跑 baremetal |
| 功能參考 | Spike + libgemmini | 拿來和 RTL 逐位元比對結果 |
| NPU 單元驗證 | Verilator + cocotb | Python 測試，對 golden model |
| FPGA 合成 | Vivado（你在本地手動跑） | 目標 xc7z020-1clg400c；先做 out-of-context 合成 |
| 效能／功能模型 | Python（NumPy） | 第 2 階段起 |

### 3.2 PYNQ-Z2（XC7Z020）資源

| 資源 | 數量 |
|---|---|
| LUT／FF | 53,200／106,400 |
| BRAM | 140 塊 36Kb（約 630 KB） |
| DSP48E1 | 220 |
| ARM 端（PS） | 雙核 Cortex-A9 650 MHz、512 MB DDR3 |

- 預設版 Gemmini（16×16、320 KB SRAM）加上 Rocket 放不下。FPGA 目標是 8×8、約 64 KB／32 KB 的量級；實際能不能放，以第 1 階段的合成結果為準。
- 陣列大小做成參數：模擬時用 16×16 和論文比較，FPGA 上用 8×8。
- Chipyard 支援的板子（VCU118、ZCU104、Arty35T／100T、Genesys2、Nexys Video）沒有 PYNQ-Z2。要上板得自己做 Vivado 專案，所以列為選做（第 5 階段）。

### 3.3 開發環境

- **雲端環境**：Ubuntu 24.04、4 核、15 GB RAM、可用磁碟約 31 GB；沒有預裝 conda、Verilator、RISC-V 工具鏈。
- **環境是暫時性的**：閒置一段時間會被回收。所以：
  - 所有安裝與建置都寫成 `scripts/` 裡的腳本，並固定版本（commit hash）。
  - Chipyard 本身不進 repo，由腳本抓指定版本。
  - 結果（CSV、報告、合成報告）要 commit。
  - 如果每次重建太久，可以考慮把安裝寫進雲端環境的 Setup script。
- **資源偏緊**：
  - Gemmini 16×16 的 Chisel elaboration 加 Verilator 編譯，可能吃掉大部分的 15 GB 記憶體。
  - 磁碟要省著用：不裝 FireSim／FireMarshal，舊的建置產物要清掉。
  - 實測（2026-10-30，Chipyard 1.15.0 加 Gemmini）：安裝完成後磁碟多用了約 12.5 GB（`df` 差額），剩約 18 GB；成功的步驟合計約 13 分鐘。16×16 的 Verilator 建置用量還沒量。
  - Verilator 建置（`-j4`）：8×8 約 250 秒、16×16 約 234 秒，各增加約 0.5～0.6 GB 磁碟，最低可用記憶體都在 10 GB 以上（取樣值，含可回收的快取）。模擬速度實測約 2.6 k 週期／秒（8×8、單執行緒，同時還有兩個模擬在跑），所以約一千萬週期的程式要跑一小時以上；profiling 以單層為主，整個模型要先估週期數。
  - Maven Central 對這個環境的共用出口會回 HTTP 429（約三成請求）。`setup_chipyard.sh` 讓 sbt 改用 Google 的 Maven 鏡像並重試；之後在這個環境新增 sbt 依賴也要走同一條路（`source scripts/chipyard_env.sh` 會帶上設定）。

## 4. 系統架構

### 4.1 第 4 階段的 SoC（組態 A，和 Gemmini 同一個接法）

```
+----------------------------- ChipTop（Chipyard）------------------------------+
|  Rocket tile                                                                  |
|  +-------------+  RoCC cmd/resp  +-----------------------------------------+  |
|  | Rocket core |<--------------->| LazyRoCC 包裝（Chisel）                 |  |
|  | L1 I$ / D$  |                 |  +-----------------------------------+  |  |
|  +------+------+                 |  | npu_top.sv（BlackBox）            |  |  |
|         |                        |  |  命令解碼 → 相依追蹤 → 三條 pipeline |  |  |
|         |                        |  |  PE 陣列、scratchpad、accumulator  |  |  |
|         |                        |  |  DMA（AXI4 master）               |  |  |
|         |                        |  +-----------------+-----------------+  |  |
|         |                        |              AXI4ToTL → tlNode          |  |
|         |                        +--------------------+--------------------+  |
|  =======+======================= system bus（TileLink）===+=================  |
|                                   |                                           |
|                         L2（inclusive cache）                                 |
|                                   |                                           |
|                      memory bus → DRAM 模型（Verilator）                      |
+-------------------------------------------------------------------------------+
```

- rocket-chip 的 `LazyRoCC` 有 `tlNode`、`atlNode`、`stlNode` 可以接記憶體 master。SV NPU 的 AXI4 master 經 `AXI4ToTL` 接到 `tlNode`。
- baremetal 在 machine mode 下沒有位址轉換，虛擬位址就是實體位址，所以第一版 NPU **不做 TLB**。RoCC 的 PTW 介面先接空。

### 4.2 NPU 核心的介面原則

- **命令輸入**：NPU 核心只吃「Gemmini 指令流」，每道指令是 funct 加 rs1、rs2 兩個 64-bit 值。前面接一層薄的轉接：
  - 第 4 階段：RoCC 轉接（組態 A）
  - 第 6 階段：MMIO 暫存器加 descriptor ring 的轉接（組態 B、C、D），NPU 核心不用改
- **記憶體**：一個 AXI4 master，位址寬度和資料寬度做成參數。
- **完成通知**：保留 RoCC 的 `busy`／`interrupt`。MMIO 版本則是把狀態寫回主記憶體，再發中斷。
- **計數器**：從第一版就內建效能計數器（計算忙碌、DMA 忙碌、兩者重疊、各種等待），第 6 階段也會用到。

## 5. NPU 方向（細節在第 2 階段和你討論）

### 5.1 指令集相容的範圍

- **第一版子集**：`config_ex`、`config_mvin`、`config_mvout`、`mvin`（含 2／3）、`mvout`、`preload`、`compute_preloaded`、`compute_accumulated`、`flush`（無 TLB 時是 no-op）。
- **之後再補**：`loop_ws`、`loop_conv_ws`、`config_norm`。
- **相容的定義**：子集內的指令，在同一個 baremetal 測試裡和 Spike + libgemmini 的結果逐位元相同。
- 如果某項優化會改變數值（例如縮放從浮點改成整數），就做成 `config_ex` 的擴充模式，預設保持 Gemmini 的行為，舊測試照樣能比。

### 5.2 優化候選（先 profiling，再挑 1～2 項）

| 方向 | 內容 | 主要收益 |
|---|---|---|
| Depthwise conv | depthwise 時 systolic array 使用率很低，MobileNet、DS-CNN 吃虧；可以加 depthwise 模式或小型向量單元 | 效能 |
| 整數 requant | 浮點縮放改成 TFLite 式的整數乘法加位移 | 面積，FPGA 上特別明顯 |
| DSP 打包 | 一顆 DSP48E1 做兩個 int8 MAC；7 系列的 25×18 乘法器限制較多，要再評估 | FPGA 上的 MAC 數 |
| 只留 WS | 拿掉 OS dataflow，簡化 PE | 面積、Fmax |

## 6. Workload

- **MLPerf Tiny**（Banbury et al., 2021）：
  - ResNet-8（CIFAR-10）
  - MobileNetV1-0.25（Visual Wake Words）
  - DS-CNN（Keyword Spotting）
  - FC AutoEncoder（Anomaly Detection）
- **代表性單層**：ResNet-50 的 conv、MobileNetV1 的 depthwise／pointwise、一個全連接層的 GEMM。
- **精度**：int8（TFLite 的 int8 量化模型）。
- **要寫的工具**：把 TFLite int8 模型轉成 `gemmini.h` 呼叫序列和權重 header 的 Python 腳本。量化參數的對應（per-channel scale → Gemmini 的縮放）要在第 1 階段處理。
- Verilator 很慢：先跑單層，整個模型看時間允許再跑。

## 7. 階段計畫

| 階段 | 內容 | 完成條件 |
|---|---|---|
| **1. Gemmini 基準** | 見 §7.1 | 基準表、瓶頸排序、選定 1～2 項優化 |
| **2. NPU 規格**（和你討論） | 指令子集、微架構、選定的優化、Python 效能模型（用第 1 階段的週期數校正）、8×8 在 Z7020 的資源預估 | 你核可規格書 |
| **3. SV RTL 與單元驗證** | 見 §7.2 | 回歸測試全過；8×8 版本在 Vivado OOC 合成放得進 Z7020 並達到第 2 階段定的 Fmax |
| **4. 整合與比較** | LazyRoCC 包裝、BlackBox、`AXI4ToTL`；跑和第 1 階段相同的測試，在相同陣列大小、相同 SRAM 大小下和 Gemmini 比 | 子集測試全過；比較表（週期、使用率、LUT／FF／BRAM／DSP、Fmax） |
| **5. 上板（選做）** | 自製 PYNQ-Z2 Vivado 專案：SoC 放 PL，經 S_AXI_HP 用 PS 的 DDR，A9 載入程式 | 實機跑完一個 MLPerf Tiny 模型 |
| **6. PCIe 研究** | 見 §9 | 晶片內和外接的比較報告 |
| **7. 收尾** | 整理結果、報告 | 最終報告 |

### 7.1 第 1 階段細項

1. **環境**：`scripts/setup_chipyard.sh` 照 Gemmini README 指定的 Chipyard 版本安裝（跳過 FireSim／FireMarshal），記下所有 commit hash，量磁碟與記憶體用量。
2. **功能**：用 Spike + libgemmini 跑 gemmini-rocc-tests 的 baremetal 測試（`mvin_mvout`、matmul、conv）。
3. **RTL 模擬**：用 Verilator 建兩個設定：
   - `GemminiRocketConfig`（16×16，256 KB／64 KB）
   - 自訂 8×8 int8 設定（以 `defaultConfig.copy` 改成 8×8、64 KB／32 KB）
4. **Workload**：寫 §6 的 TFLite 轉換腳本，先跑單層。
5. **Profiling**：每層的週期數、PE 使用率、DMA 等待、留在 CPU 上算的部分、mvin／mvout 頻寬。
6. **Vivado**：匯出 Gemmini 的 Verilog 和檔案清單（含 SRAM 的行為模型），附 OOC 合成的 TCL 範本。你在本地對 xc7z020 合成，把 utilization／timing 報告放進 `results/vivado/`。

### 7.2 第 3 階段細項

- **模組**：PE 與陣列、scratchpad／accumulator（分 bank）、load／store DMA（AXI4）、execute 控制、命令解碼與相依追蹤（簡化版 ROB）、requant／activation、效能計數器。
- **SV 寫法**：只用 Verilator 和 Vivado 都支援的語法；SRAM 寫成 Vivado 能推成 BRAM 的形式。
- **驗證**：
  - 用 Verilator `--lint-only` 做 lint
  - 用 cocotb 跑隨機測試，對 Python golden model
  - 整顆 NPU 的結果再和 libgemmini 的輸出比對

## 8. 驗證策略

- **三層參考**：
  1. Python golden model（第 2 階段起，逐位元）
  2. Spike + libgemmini（指令層級的功能參考）
  3. Gemmini RTL（效能參考）
- **回歸**：每次改 RTL 都跑 cocotb 單元測試；整合後再跑 gemmini-rocc-tests 子集。
- **確定性**：Verilator 模擬是確定性的，同一輸入的週期數固定。但改參數時要看敏感度，不能只報單一點。

## 9. PCIe 研究設計（第 6 階段）

### 9.1 組態

| 組態 | NPU 位置 | 下命令 | 資料路徑 | Cache 一致性 |
|---|---|---|---|---|
| A. 緊耦合 | CPU 核心旁（RoCC） | 自訂指令 | 經 L2 | 一致 |
| B. 晶片內匯流排 | 同一顆晶片，掛在 SoC 匯流排 | MMIO + descriptor ring | DMA 走系統匯流排、共用 L2 | 一致 |
| C. 外接，直接讀主記憶體 | PCIe 後面 | MMIO 經 PCIe | 每次 DMA 都經 PCIe 讀主機 DRAM | 不一致，要 flush |
| D. 外接，卡上有 DRAM | PCIe 後面，加本地 DRAM | MMIO 經 PCIe | 先整批搬到本地 DRAM 再算 | 不一致 |

每兩組之間只差一個變因：

- **B 對 C**：只差 PCIe 連線（命令介面相同），這是核心比較。
- **C 對 D**：資料放哪裡。
- **A 對 B**：緊耦合對鬆耦合。

### 9.2 PCIe 時序模型

用 SV 寫一個可合成的 AXI4 中介模組，插在 NPU 和系統之間（命令路徑與資料路徑都要過）。

- **參數**：
  - 單向延遲 L
  - 有效頻寬 BW
  - MPS（128／256 B）、MRRS
  - 每個 TLP 的 header 開銷（約 20～26 B）
- **行為**：
  - 讀取（non-posted）要等 completion，約 2L 加傳輸時間
  - 寫入（posted）約 L 加傳輸時間
  - CPU 的 MMIO 讀是 2L
  - 中斷（類似 MSI）是 L，再加上處理時間
- **時脈換算**：模擬是以週期計，ns 轉週期要假設目標時脈。至少掃兩點：
  - 100 MHz（像 FPGA）
  - 1 GHz（像 ASIC）

  時脈假設會直接改變 PCIe 相對於 CPU 的快慢，所以結論一定要附上時脈。
- **三檔**：保守／名目／樂觀，三組常數。報告時並排列出「板子實際做得到的連線」和「理想的滿寬連線」，後者標明是推算。
- **初始參數**（之後校正）：
  - 頻寬：Gen3 x4、Gen4 x4、Gen4 x16。platform 專案在 x86 + GPU 上量到 Gen4 x16 有效 23.6 GB/s（另一個平台的實測，見 §9.6）。
  - 硬體單向延遲：數百 ns 等級，用 pcie-bench（Neugebauer et al., SIGCOMM 2018）的數據校正。
  - 含軟體的延遲：platform 專案經 CUDA 量到單向 p50 4.6 µs、連發每個命令 2.09 µs、逐次同步 4.36 µs。這些含驅動堆疊，只當「含軟體」那一檔的上界參考，不當硬體延遲。

### 9.3 掃描軸

- 連線延遲、頻寬、MPS
- **工作集和 NPU 本地記憶體的比例**：決定要不要跨連線搬資料，也決定交叉點
- batch size
- offload 粒度：逐層下命令，或用 descriptor ring 一次交整個模型
- 輪詢或中斷
- 資料擺放（C 對 D）

### 9.4 量測

- 總週期數
- 連線忙碌週期、NPU 計算週期，以及**兩者重疊的部分**
- 每次推論跨連線的位元組數
- CPU 花在 driver 上的週期：doorbell、cache flush、等待

### 9.5 軟體開銷

- **baremetal 量得到的**：doorbell、輪詢或中斷、cache flush（Rocket 的 L1 flush 指令、L2 的 flush 暫存器，第 6 階段確認可用性）。
- **OS 的部分**（系統呼叫、記憶體 pin、中斷處理的排程）：選做。可以在 PYNQ-Z2 的 ARM Linux 上實測再加進模型，或短期租 AWS EC2 F2 跑 FireSim。

### 9.6 旁觀參考：platform 專案

只當參考，不耦合。來源是 `jimmy01081122/platform` 的 coord-round5 分支，commit d23118fb：

- `round6/stage5/STAGE5_REPORT_R6.md`
- `round6/research/STAGE5_BOX_BRIEF_R6.md`
- `round5/research/STAGE5_5_2_POSITIONS_DESIGN_R5.md`
- `round3/LEDGER_ROUND3.md`（R3-152）

可借的做法：

- **交接延遲的形狀**：每次交接約為「倍率 × (2 × 單向延遲 + descriptor 數 × 每個 descriptor 的成本)」，三檔倍率 ×1.5／×1／×0.7。我們的時序模型可以用同樣的形狀，方便對照。
- **主項不一定是延遲**：在他們的 box 推算裡，每個 token 的 box 時間約 25.6 ms，連線交接只占 0.945 ms，主項是跨連線和讀自帶記憶體的位元組。所以除了延遲，位元組數也一定要掃。
- **本地記憶體容量不是越大越好**：他們的自帶記憶體容量對效益不是單調的。我們的 D 組態也要掃容量，不能只看單一點。
- **標示方式**：結果標【實測】／【算式】／【推定】／【假設】，推算值和實測值分開。
- **他們缺的一點**：「封裝內、核心外的引擎」那個位置的交接延遲，在他們的平台上沒有實體可量，只能用文獻假設（Intel IAA 的最小 offload 開銷 4.2 µs，三檔 8.4／4.2／1 µs）。我們的組態 B 可以在模擬裡直接量到週期數。這只是觀察，不改變兩個專案的範圍。

注意：他們的數字是 x86 加 GPU（CUDA）上量的，含驅動堆疊，不能直接搬到 RISC-V 加 FPGA 端點的情境。

## 10. Repo 結構

```
docs/            計畫、決策紀錄、規格書
hw/npu/rtl/      NPU 的 SystemVerilog
hw/npu/tb/       cocotb 測試
hw/chipyard/     Chisel 膠水（LazyRoCC 包裝、設定），由腳本放進 Chipyard
hw/pcie_model/   第 6 階段的 PCIe 時序模型
model/           Python golden model、效能模型、TFLite 轉換工具
sw/              baremetal 測試、gemmini.h 的擴充
scripts/         安裝、建置、執行、收集結果
results/         profiling 數據、比較表、Vivado 報告（results/vivado/）
```

## 11. 風險與對策

| 風險 | 對策 |
|---|---|
| 雲端環境會被回收，Chipyard 要重裝 | 腳本化、固定版本；結果都 commit；必要時寫進環境的 Setup script |
| 15 GB 記憶體不夠 16×16 Gemmini 的 elaboration 或 Verilator 編譯 | 先試 8×8；調 JVM heap、Verilator 的平行度；真的不行，16×16 只用 Spike 與效能模型 |
| 31 GB 磁碟不夠 | 不裝 FireSim／FireMarshal；清掉舊的建置。安裝後剩約 18 GB，Verilator 建置會再用掉一部分（待量） |
| Verilator 太慢 | 單層優先；小模型；Spike 先驗功能 |
| Gemmini 的 Verilog 進 Vivado 時 SRAM 推不成 BRAM | 用行為模型；必要時改寫 SRAM 包裝 |
| 8×8 也放不進 Z7020 | 縮 SRAM、縮陣列，或只做 NPU 本體的 OOC 合成 |
| 數值優化（整數 requant）破壞和 Gemmini 的逐位元相容 | 做成擴充模式，預設行為不變 |
| TFLite 量化參數和 Gemmini 縮放對不上 | 第 1 階段先處理，用 Spike 驗證 |

## 12. 待討論

- 第 1 階段的 profiling 結果出來後：選哪 1～2 項優化、NPU 的 Fmax 與大小目標。
- 第 2 階段的 NPU 規格書。
- 第 5 階段（上板）做不做：等合成結果再決定。

## 13. 參考資料

- H. Genc et al., "Gemmini: Enabling Systematic Deep-Learning Architecture Evaluation via Full-Stack Integration," DAC 2021. arXiv:1911.09925v3.
- Chipyard：https://github.com/ucb-bar/chipyard
- Gemmini：https://github.com/ucb-bar/gemmini
- libgemmini（Spike 擴充）：https://github.com/ucb-bar/libgemmini
- R. Neugebauer et al., "Understanding PCIe performance for end host networking," SIGCOMM 2018（pcie-bench）。
- Y. S. Shao et al., "Co-Designing Accelerators and SoC Interfaces using gem5-Aladdin," MICRO 2016。
- C. Banbury et al., "MLPerf Tiny Benchmark," NeurIPS 2021 Datasets and Benchmarks Track。
