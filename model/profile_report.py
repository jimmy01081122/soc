#!/usr/bin/env python3
"""Turn sw/profile/layer_profile.c output into per-layer tables.

Reads the CSV rows ('P,...') that the profiler prints and writes
results/profile_<config>.csv and results/profile_<config>.md.

Derived columns, per layer (warm passes only, averaged where two passes agree):
  macs        multiply-accumulates of the layer
  util        macs / (DIM^2 * cycles): fraction of the PE array's peak
  breakdown   share of cycles by which of the load / store / execute controllers
              were busy (the seven MAIN_* counters are mutually exclusive); the rest
              is idle, i.e. none of them busy (CPU-side work, waiting on commands)
  bytes       DMA traffic read from / written to memory (RDMA/WDMA counters)

Usage: model/profile_report.py CONFIG LOGFILE [LOGFILE ...]
"""
import csv
import pathlib
import re
import sys

COLS = ["model", "layer", "kind", "in_r", "in_c", "in_ch", "out_ch", "k", "stride",
        "pad", "out_r", "out_c", "pass", "cycles"] + [f"c{i}" for i in range(8)]
SET_A = ["ld", "st", "ex", "ld_st", "ld_ex", "st_ex", "ld_st_ex", "exe_active"]
SET_B = ["load_dma_wait", "store_dma_wait", "rdma_bytes", "wdma_bytes",
         "rdma_latency", "rs_full", "exe_ctrlq_block", "load_spad_wait"]
KIND = {0: "conv", 1: "dwconv", 2: "matmul"}


def parse(paths):
    dim = None
    rows = []
    for path in paths:
        for line in pathlib.Path(path).read_text(errors="replace").splitlines():
            m = re.match(r"# DIM=(\d+)", line)
            if m:
                dim = int(m.group(1))
            if line.startswith("P,") and line.count(",") == len(COLS):
                parts = line.split(",")[1:]
                row = dict(zip(COLS, parts))
                for key in COLS[2:]:
                    row[key] = int(row[key])
                rows.append(row)
    if dim is None:
        sys.exit("no '# DIM=' header found; is this profiler output?")
    return dim, rows


def macs(r):
    if r["kind"] == 0:
        return r["out_r"] * r["out_c"] * r["out_ch"] * r["k"] * r["k"] * r["in_ch"]
    if r["kind"] == 1:
        return r["out_r"] * r["out_c"] * r["in_ch"] * r["k"] * r["k"]
    return r["in_r"] * r["out_ch"] * r["in_ch"]


def layers(rows):
    """Group rows by (model, layer) and keep only layers with all three passes."""
    grouped = {}
    for r in rows:
        grouped.setdefault((r["model"], r["layer"]), {})[r["pass"]] = r
    return [(k, v) for k, v in grouped.items() if {0, 1, 2} <= v.keys()]


def summarize(dim, grouped):
    out = []
    for (model, layer), p in grouped:
        a, b = p[1], p[2]
        r0 = p[0]
        warm = (a["cycles"] + b["cycles"]) / 2
        spread = abs(a["cycles"] - b["cycles"]) / warm if warm else 0.0
        counters_a = {n: a[f"c{i}"] for i, n in enumerate(SET_A)}
        counters_b = {n: b[f"c{i}"] for i, n in enumerate(SET_B)}
        busy = sum(counters_a[n] for n in SET_A[:7])
        m = macs(a)
        out.append({
            "model": model, "layer": layer, "kind": KIND[a["kind"]],
            "macs": m,
            "cold_cycles": r0["cycles"], "warm_cycles": warm, "pass_spread": spread,
            "ideal_cycles": m / (dim * dim),
            "util": m / (dim * dim * warm) if warm else 0.0,
            "exe_active": counters_a["exe_active"],
            "ex_share": counters_a["exe_active"] / a["cycles"] if a["cycles"] else 0.0,
            "idle_share": max(0.0, 1 - busy / a["cycles"]) if a["cycles"] else 0.0,
            **{f"a_{n}": counters_a[n] for n in SET_A},
            **{f"b_{n}": counters_b[n] for n in SET_B},
        })
    return out


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def write_md(path, config, dim, rows):
    pct = lambda x: f"{100 * x:.1f}%"
    lines = [
        f"# 逐層 profiling：{config}（DIM={dim}）", "",
        "由 `model/profile_report.py` 從 `sw/profile/layer_profile.c` 的輸出產生。",
        "週期數是 Rocket 的 `rdcycle`，在 `gemmini_fence()` 之後讀取；暖機數字是兩次暖機執行的平均。", "",
        "- 利用率 = MACs ÷ (DIM² × 週期)：PE 陣列峰值的幾分之幾。",
        "- 控制器忙碌分解：load／store／execute 三個控制器同時忙碌的組合（互斥，來自 MAIN_* 計數器）；",
        "  「閒置」是三者都不忙的週期（等 CPU 發命令、CPU 端自己的運算等）。", "",
        "| 模型 | 層 | 類型 | MACs | 冷 | 暖 | 理想 | 利用率 | EX 忙 | 閒置 | 讀 B | 寫 B |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['model']} | {r['layer']} | {r['kind']} | {r['macs']:,} | {r['cold_cycles']:,} | "
            f"{r['warm_cycles']:,.0f} | {r['ideal_cycles']:,.0f} | {pct(r['util'])} | "
            f"{pct(r['ex_share'])} | {pct(r['idle_share'])} | {r['b_rdma_bytes']:,} | {r['b_wdma_bytes']:,} |")
    worst = max((r["pass_spread"] for r in rows), default=0.0)
    lines += ["", f"兩次暖機執行的週期數最大差距：{pct(worst)}。"]
    pathlib.Path(path).write_text("\n".join(lines) + "\n")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    config, logs = sys.argv[1], sys.argv[2:]
    dim, rows = parse(logs)
    summary = summarize(dim, layers(rows))
    if not summary:
        sys.exit("no layer has all three passes yet")
    out = pathlib.Path(__file__).resolve().parents[1] / "results"
    out.mkdir(exist_ok=True)
    write_csv(out / f"profile_{config}.csv", summary)
    write_md(out / f"profile_{config}.md", config, dim, summary)
    print(f"{config}: {len(summary)} layers -> {out}/profile_{config}.md")


if __name__ == "__main__":
    main()
