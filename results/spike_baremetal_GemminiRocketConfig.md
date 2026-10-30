# Spike 功能測試：GemminiRocketConfig（DIM=16）

由 `scripts/spike_baremetal.sh` 產生，2026-10-30 14:21 UTC。
Spike 以 `--extension=gemmini` 執行，libgemmini 與測試程式都依這個設定的 `gemmini_params.h` 建置。
結束碼 0 算通過；這只驗證功能，不給效能數字。

- gemmini：`8c3f9923a44a2fe2c7930587be297d6d4f8c09ca`
- gemmini-rocc-tests：`7c540b3adf1b86ad93d07f893abe3a73489b568e`
- libgemmini：`ea8f7ed7afd68e001fb06ddccad9a023c990961d`
- 結果：通過 54、失敗 0、略過 2

| 測試 | 結果 | 結束碼 |
|---|---|---|
| aligned | pass | 0 |
| conv | pass | 0 |
| conv_dw | pass | 0 |
| conv_dw_perf | pass | 0 |
| conv_first_layer | pass | 0 |
| conv_perf | pass | 0 |
| conv_rect | pass | 0 |
| conv_rect_pool | pass | 0 |
| conv_stride | pass | 0 |
| conv_trans_input_3120 | pass | 0 |
| conv_trans_input_3120_with_kernel_dilation | pass | 0 |
| conv_trans_output_1203 | pass | 0 |
| conv_trans_weight_0132 | pass | 0 |
| conv_trans_weight_1203 | pass | 0 |
| conv_with_input_dilation | pass | 0 |
| conv_with_input_dilation_and_neg_padding | pass | 0 |
| conv_with_input_dilation_and_rot180 | pass | 0 |
| conv_with_kernel_dilation | pass | 0 |
| conv_with_pool | pass | 0 |
| conv_with_rot180 | pass | 0 |
| gemmini_counter | pass | 0 |
| global_average | pass | 0 |
| matmul | pass | 0 |
| matmul_os | pass | 0 |
| matmul_spad | skipped (needs ext spad) | 57 |
| matmul_ws | pass | 0 |
| matrix_add | pass | 0 |
| mvin_mvout | pass | 0 |
| mvin_mvout_acc | pass | 0 |
| mvin_mvout_acc_full | pass | 0 |
| mvin_mvout_acc_full_stride | pass | 0 |
| mvin_mvout_acc_stride | pass | 0 |
| mvin_mvout_acc_zero_stride | pass | 0 |
| mvin_mvout_block_stride | pass | 0 |
| mvin_mvout_spad | skipped (needs ext spad) | 57 |
| mvin_mvout_stride | pass | 0 |
| mvin_mvout_zeros | pass | 0 |
| mvin_scale | pass | 0 |
| padded | pass | 0 |
| raw_hazard | pass | 0 |
| resadd | pass | 0 |
| resadd_stride | pass | 0 |
| template | pass | 0 |
| tiled_matmul_cpu | pass | 0 |
| tiled_matmul_option | pass | 0 |
| tiled_matmul_os | pass | 0 |
| tiled_matmul_ws | pass | 0 |
| tiled_matmul_ws_At | pass | 0 |
| tiled_matmul_ws_Bt | pass | 0 |
| tiled_matmul_ws_full_C | pass | 0 |
| tiled_matmul_ws_igelu | pass | 0 |
| tiled_matmul_ws_layernorm | pass | 0 |
| tiled_matmul_ws_low_D | pass | 0 |
| tiled_matmul_ws_perf | pass | 0 |
| tiled_matmul_ws_softmax | pass | 0 |
| transpose | pass | 0 |
