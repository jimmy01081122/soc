// Per-layer profiler for Gemmini-compatible accelerators (docs/plan.md stage 1).
//
// Runs a table of MLPerf Tiny layer shapes through Gemmini's tiled_conv_auto /
// tiled_conv_dw_auto / tiled_matmul_auto (weight-stationary, batch 1) and prints
// one CSV row per pass, after each layer, so partial results survive a long
// simulation:
//
//   P,model,layer,kind,in_r,in_c,in_ch,out_ch,k,stride,pad,out_r,out_c,pass,cycles,c0..c7
//
// Three passes per layer:
//   0  cold: caches and TLB empty, no counters
//   1  warm, counter set A: execution breakdown (the seven exclusive MAIN_*
//      load/store/execute busy combinations, plus EXE_ACTIVE_CYCLE)
//   2  warm, counter set B: memory system and stall events
// Cycles come from rdcycle on the Rocket core, taken after gemmini_fence() so
// they include the accelerator finishing, not just the CPU issuing commands.
//
// Inputs and weights are never initialized: Gemmini has no data-dependent timing,
// and filling buffers would burn simulation time on the CPU. kind: 0 conv,
// 1 depthwise conv, 2 matmul (in_r = I, in_ch = K, out_ch = J).

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "include/gemmini_testutils.h"

#define KIND_CONV 0
#define KIND_DW 1
#define KIND_MATMUL 2

typedef struct {
    const char *model, *name;
    int kind, in_r, in_c, in_ch, out_ch, k, stride, pad;
} layer_t;

#define CONV(m, n, r, c, ci, co, k, s, p) {m, n, KIND_CONV, r, c, ci, co, k, s, p}
#define DW(m, n, r, c, ch, k, s, p)       {m, n, KIND_DW, r, c, ch, ch, k, s, p}
#define MATMUL(m, n, I, K, J)             {m, n, KIND_MATMUL, I, 1, K, J, 1, 1, 0}

// Shapes follow the MLPerf Tiny reference models. DS-CNN's first layer (10x4
// kernel) is omitted because Gemmini's conv wrappers only take square kernels.
static const layer_t layers[] = {
    // ResNet-8, CIFAR-10 32x32x3
    CONV("resnet8", "conv1_3to16",        32, 32,  3, 16, 3, 1, 1),
    CONV("resnet8", "conv_16to16",        32, 32, 16, 16, 3, 1, 1),
    CONV("resnet8", "conv_16to32_s2",     32, 32, 16, 32, 3, 2, 1),
    CONV("resnet8", "conv_32to32",        16, 16, 32, 32, 3, 1, 1),
    CONV("resnet8", "skip_16to32_s2",     32, 32, 16, 32, 1, 2, 0),
    CONV("resnet8", "conv_32to64_s2",     16, 16, 32, 64, 3, 2, 1),
    CONV("resnet8", "conv_64to64",         8,  8, 64, 64, 3, 1, 1),
    CONV("resnet8", "skip_32to64_s2",     16, 16, 32, 64, 1, 2, 0),
    MATMUL("resnet8", "fc_64to10",         1, 64, 10),
    // DS-CNN, keyword spotting (25x5x64 feature maps)
    DW("dscnn", "dw3x3_64",               25,  5, 64, 3, 1, 1),
    CONV("dscnn", "pw1x1_64to64",         25,  5, 64, 64, 1, 1, 0),
    MATMUL("dscnn", "fc_64to12",           1, 64, 12),
    // MobileNetV1 0.25, visual wake words 96x96x3
    CONV("mobilenet", "conv1_3to8_s2",    96, 96,  3,  8, 3, 2, 1),
    DW("mobilenet", "dw3x3_8",            48, 48,  8, 3, 1, 1),
    CONV("mobilenet", "pw1x1_8to16",      48, 48,  8, 16, 1, 1, 0),
    DW("mobilenet", "dw3x3_16_s2",        48, 48, 16, 3, 2, 1),
    CONV("mobilenet", "pw1x1_16to32",     24, 24, 16, 32, 1, 1, 0),
    // Anomaly-detection autoencoder (fully connected, batch 1)
    MATMUL("autoencoder", "fc_640to128",   1, 640, 128),
    MATMUL("autoencoder", "fc_128to128",   1, 128, 128),
};

#define NUM_LAYERS ((int)(sizeof(layers) / sizeof(layers[0])))

// Buffers: 128 KiB each for input, weights and output, plus bias. They sit at a
// fixed DRAM address OUTSIDE the ELF image instead of in a static array: the
// loader zero-fills .bss through the simulator's serial TSI link at roughly 25
// cycles per byte, so a 400 KB .bss cost ~10M cycles (over an hour) before main()
// even started. DRAM is 4 GiB at 0x80000000 in these configs (Spike has 2 GiB).
#define REGION (128 * 1024)
#define BUF_BASE 0x88000000UL

static const uint8_t SET_A[8] = {
    MAIN_LD_CYCLES, MAIN_ST_CYCLES, MAIN_EX_CYCLES, MAIN_LD_ST_CYCLES,
    MAIN_LD_EX_CYCLES, MAIN_ST_EX_CYCLES, MAIN_LD_ST_EX_CYCLES, EXE_ACTIVE_CYCLE,
};
static const uint8_t SET_B[8] = {
    LOAD_DMA_WAIT_CYCLE, STORE_DMA_WAIT_CYCLE, RDMA_BYTES_REC, WDMA_BYTES_SENT,
    RDMA_TOTAL_LATENCY, RESERVATION_STATION_FULL_CYCLES, EXE_CONTROL_Q_BLOCK_CYCLE,
    LOAD_SCRATCHPAD_WAIT_CYCLE,
};

static int out_dim(int in, const layer_t *l) { return (in + 2 * l->pad - l->k) / l->stride + 1; }

static void run_layer(const layer_t *l, int out_r, int out_c) {
    elem_t *input = (elem_t *)(BUF_BASE);
    elem_t *weights = (elem_t *)(BUF_BASE + REGION);
    elem_t *output = (elem_t *)(BUF_BASE + 2 * REGION);
    acc_t *bias = (acc_t *)(BUF_BASE + 3 * REGION);

    if (l->kind == KIND_CONV) {
        tiled_conv_auto(1, l->in_r, l->in_c, l->in_ch, l->out_ch, out_r, out_c,
                        l->stride, 1, 1, l->pad, l->k,
                        false, false, false, false, false,
                        input, weights, bias, output,
                        RELU, ACC_SCALE_IDENTITY, 0, 0, 0, WS);
    } else if (l->kind == KIND_DW) {
        tiled_conv_dw_auto(1, l->in_r, l->in_c, l->in_ch, out_r, out_c,
                           l->stride, l->pad, l->k,
                           input, weights, bias, output,
                           RELU, ACC_SCALE_IDENTITY, 1, 0, 0, WS);
    } else {
        tiled_matmul_auto(l->in_r, l->out_ch, l->in_ch,
                          input, weights, bias, output,
                          l->in_ch, l->out_ch, l->out_ch, l->out_ch,
                          MVIN_SCALE_IDENTITY, MVIN_SCALE_IDENTITY, MVIN_SCALE_IDENTITY,
                          RELU, ACC_SCALE_IDENTITY, 0, true,
                          false, false, false, false, 0, WS);
    }
    gemmini_fence();
}

int main(void) {
    gemmini_flush(0);
    printf("# DIM=%d BANK_NUM=%d BANK_ROWS=%d ACC_ROWS=%d layers=%d start_cycle=%llu\n",
           DIM, BANK_NUM, BANK_ROWS, ACC_ROWS, NUM_LAYERS, (unsigned long long)read_cycles());
    printf("# cols: P,model,layer,kind,in_r,in_c,in_ch,out_ch,k,stride,pad,out_r,out_c,pass,cycles,c0..c7\n");
    printf("# set A: MAIN_LD,MAIN_ST,MAIN_EX,MAIN_LD_ST,MAIN_LD_EX,MAIN_ST_EX,MAIN_LD_ST_EX,EXE_ACTIVE\n");
    printf("# set B: LOAD_DMA_WAIT,STORE_DMA_WAIT,RDMA_BYTES_REC,WDMA_BYTES_SENT,RDMA_TOTAL_LATENCY,RS_FULL,EXE_CTRLQ_BLOCK,LOAD_SPAD_WAIT\n");

    for (int i = 0; i < NUM_LAYERS; i++) {
        const layer_t *l = &layers[i];
        const int out_r = l->kind == KIND_MATMUL ? 0 : out_dim(l->in_r, l);
        const int out_c = l->kind == KIND_MATMUL ? 0 : out_dim(l->in_c, l);

        for (int pass = 0; pass < 3; pass++) {
            const uint8_t *set = pass == 1 ? SET_A : pass == 2 ? SET_B : NULL;
            if (set) {
                counter_reset();
                for (int c = 0; c < 8; c++) counter_configure(c, set[c]);
            }

            gemmini_fence();
            const uint64_t t0 = read_cycles();
            run_layer(l, out_r, out_c);
            const uint64_t t1 = read_cycles();

            uint32_t val[8] = {0};
            if (set) {
                counter_snapshot_take();
                for (int c = 0; c < 8; c++) val[c] = counter_read(c);
                counter_snapshot_reset();
            }

            printf("P,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%llu", l->model, l->name, l->kind,
                   l->in_r, l->in_c, l->in_ch, l->out_ch, l->k, l->stride, l->pad,
                   out_r, out_c, pass, (unsigned long long)(t1 - t0));
            for (int c = 0; c < 8; c++) printf(",%u", val[c]);
            printf("\n");
        }
    }
    printf("# done end_cycle=%llu\n", (unsigned long long)read_cycles());
    return 0;
}
