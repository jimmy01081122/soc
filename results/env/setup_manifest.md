# Chipyard 環境紀錄

由 `scripts/setup_chipyard.sh` 產生，2026-10-30 13:45 UTC。

## 主機

| 項目 | 值 |
|---|---|
| OS | Ubuntu 24.04.5 LTS，kernel 6.18.44-fc-v185 |
| glibc | 2.39 |
| CPU | 4 核 |
| 記憶體 | 15 GiB |
| 磁碟可用（/home/user） | 21G |

## 版本

| 項目 | 版本 |
|---|---|
| Miniforge | 26.7.2-1 |
| conda | 26.7.2 |
| conda-lock | 4.0.4 |
| conda lockfile | `conda-reqs/conda-lock-reqs/conda-requirements-riscv-tools-linux-64-lean.conda-lock.yml` |
| Chipyard | 1.15.0（`157dd69e49b9866be2bf8db390ee78bc38cd4438`） |
| generators/gemmini | `8c3f9923a44a2fe2c7930587be297d6d4f8c09ca` |
| generators/gemmini/software/gemmini-rocc-tests | `7c540b3adf1b86ad93d07f893abe3a73489b568e` |
| generators/gemmini/software/libgemmini | `ea8f7ed7afd68e001fb06ddccad9a023c990961d` |
| generators/rocket-chip | `ece7b9ad544b07df39cd13b6fd7236562a26355d` |
| generators/testchipip | `555ff3fbc12f81a8feff7a4801930fb384ddd2ae` |
| toolchains/riscv-tools/riscv-isa-sim | `9c190a07c6838f6392bafa4ad83acea462c7f759` |
| toolchains/riscv-tools/riscv-pk | `9c61d29846d8521d9487a57739330f9682d5b542` |
| riscv64-unknown-elf-gcc | riscv64-unknown-elf-gcc (g6afcc4f6d-dirty) 16.1.0 |
| Verilator | Verilator 5.022 2024-02-24 rev conda-forge build 1 |
| firtool |  |
| Java | openjdk version "20.0.2-internal" 2023-07-18 |

## 步驟耗時

| 步驟 | 狀態 | 開始（UTC） | 秒數 |
|---|---|---|---|
| miniforge | ok | 2026-10-30 13:37 | 15 |
| clone | ok | 2026-10-30 13:37 | 2 |
| conda | ok | 2026-10-30 13:37 | 86 |
| submodules | ok | 2026-10-30 13:39 | 74 |
| buildsetup | failed(2) | 2026-10-30 13:40 | 286 |

## 磁碟用量

| 路徑 | 大小 |
|---|---|
| `/home/user/chipyard` | 7.4G |
| `/home/user/chipyard/.conda-env` | 4.7G |
| `/home/user/miniforge3` | 5.2G |
