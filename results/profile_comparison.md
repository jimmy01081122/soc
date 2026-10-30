# 逐層比較：Gemmini8x8RocketConfig 對 GemminiRocketConfig

暖機週期數與利用率來自 `results/profile_<config>.csv`。加速比 = 前者週期 ÷ 後者週期；
理想加速比是兩個陣列的 PE 數比（8×8 對 16×16 是 4×）；1.0 以下代表後者反而比較慢。

| 模型 | 層 | 類型 | Gemmini8x8RocketConfig 週期 | GemminiRocketConfig 週期 | 加速比 | Gemmini8x8RocketConfig 利用率 | GemminiRocketConfig 利用率 |
|---|---|---|---:|---:|---:|---:|---:|
| resnet8 | conv1_3to16 | conv | 24,914 | 15,178 | 1.64× | 27.7% | 11.4% |
| resnet8 | conv_16to16 | conv | 49,585 | 18,494 | 2.68× | 74.3% | 49.8% |
| resnet8 | conv_16to32_s2 | conv | 25,260 | 9,683 | 2.61× | 73.0% | 47.6% |
| resnet8 | conv_32to32 | conv | 47,012 | 13,684 | 3.44× | 78.4% | 67.3% |
| resnet8 | skip_16to32_s2 | conv | 6,207 | 3,814 | 1.63× | 33.0% | 13.4% |
| resnet8 | conv_32to64_s2 | conv | 25,394 | 9,717 | 2.61× | 72.6% | 47.4% |
| resnet8 | conv_64to64 | conv | 50,067 | 15,735 | 3.18× | 73.6% | 58.6% |
| resnet8 | skip_32to64_s2 | conv | 5,560 | 3,274 | 1.70× | 36.8% | 15.6% |
| resnet8 | fc_64to10 | matmul | 840 | 752 | 1.12× | 1.2% | 0.3% |
| dscnn | dw3x3_64 | dwconv | 62,233 | 78,213 | 0.80× | 1.8% | 0.4% |
| dscnn | pw1x1_64to64 | conv | 26,950 | 7,584 | 3.55× | 29.7% | 26.4% |
| dscnn | fc_64to12 | matmul | 813 | 747 | 1.09× | 1.5% | 0.4% |
| mobilenet | conv1_3to8_s2 | conv | 47,406 | 55,560 | 0.85× | 16.4% | 3.5% |
| mobilenet | dw3x3_8 | dwconv | 123,790 | 137,472 | 0.90× | 2.1% | 0.5% |
| mobilenet | pw1x1_8to16 | conv | 30,680 | 25,828 | 1.19× | 15.0% | 4.5% |
| mobilenet | dw3x3_16_s2 | dwconv | 162,294 | 178,884 | 0.91× | 0.8% | 0.2% |
| mobilenet | pw1x1_16to32 | conv | 14,702 | 10,666 | 1.38× | 31.3% | 10.8% |
| autoencoder | fc_640to128 | matmul | 16,264 | 10,231 | 1.59× | 7.9% | 3.1% |
| autoencoder | fc_128to128 | matmul | 5,032 | 2,871 | 1.75× | 5.1% | 2.2% |

## 已 profile 的層加總

只含有 profile 的卷積／矩陣乘法層（重複的層照真實模型的次數計），不含池化、殘差相加等沒有 profile 的部分。

| 模型 | Gemmini8x8RocketConfig 週期 | GemminiRocketConfig 週期 | 加速比 |
|---|---:|---:|---:|
| resnet8 | 284,422 | 108,826 | 2.61× |
| dscnn | 89,996 | 86,544 | 1.04× |
| mobilenet | 378,872 | 408,410 | 0.93× |
| autoencoder | 21,296 | 13,102 | 1.63× |
