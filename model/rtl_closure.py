#!/usr/bin/env python3
"""Find the files a Verilog module needs, from Chipyard's generated gen-collateral.

firtool writes one file per module, so the files needed for TOP are the ones
that define TOP and every module reachable from it. Reachability is a token
match (any identifier equal to a known module name counts as an instance), which
can only over-include, never miss a module.

Usage: model/rtl_closure.py GEN_COLLATERAL_DIR TOP [--copy-to DIR] [--list FILE]
  --copy-to DIR   copy the needed files into DIR
  --list FILE     write their names, one per line (read order for Vivado)
"""
import argparse
import pathlib
import re
import shutil
import sys


def load(gen):
    """Return (defs, bodies): module name -> defining file, module name -> its own text.

    Some files (e.g. the generated memories) hold many modules, so reachability must
    look at one module's body, not at the whole file it happens to live in."""
    defs, bodies = {}, {}
    for f in sorted(gen.glob("*.sv")) + sorted(gen.glob("*.v")):
        text = f.read_text(errors="replace")
        for m in re.finditer(r"^\s*module\s+(\w+)\b(.*?)^\s*endmodule", text, re.M | re.S):
            if m.group(1) not in defs:
                defs[m.group(1)] = f
                bodies[m.group(1)] = re.sub(r"//.*", "", m.group(2))
    return defs, bodies


def closure(defs, bodies, top):
    if top not in defs:
        sys.exit(f"module {top} is not defined in the given directory")
    seen, order, stack = set(), [], [top]
    while stack:
        m = stack.pop()
        if m in seen:
            continue
        seen.add(m)
        order.append(m)
        stack += [t for t in set(re.findall(r"\b[A-Za-z_]\w*\b", bodies[m]))
                  if t in defs and t != m and t not in seen]
    return order


def instance_counts(defs, bodies, top, order):
    """How many times each reachable module is instantiated under TOP (tree product)."""
    inst = re.compile(r"^\s*(\w+)\s*(?:#\([^;]*?\))?\s+\w+\s*\(", re.M)
    children = {m: [c.group(1) for c in inst.finditer(bodies[m]) if c.group(1) in defs] for m in order}
    memo = {}

    def total(m):  # instances of every module inside one copy of m, including m itself
        if m not in memo:
            acc = {m: 1}
            for c in children[m]:
                for k, v in total(c).items():
                    acc[k] = acc.get(k, 0) + v
            memo[m] = acc
        return memo[m]

    return total(top)


def memories(bodies, modules, counts):
    """Memory arrays in the reachable modules: (module, name, width, depth, instances)."""
    found = []
    for m in modules:
        for a in re.finditer(r"^\s*reg\s*(?:\[(\d+):(\d+)\]\s*)?(\w+)\s*\[(\d+):(\d+)\]",
                             bodies[m], re.M):
            width = abs(int(a.group(1)) - int(a.group(2))) + 1 if a.group(1) else 1
            depth = abs(int(a.group(4)) - int(a.group(5))) + 1
            found.append((m, a.group(3), width, depth, counts.get(m, 1)))
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gen")
    ap.add_argument("top")
    ap.add_argument("--copy-to")
    ap.add_argument("--list")
    args = ap.parse_args()

    gen = pathlib.Path(args.gen)
    defs, bodies = load(gen)
    order = closure(defs, bodies, args.top)
    counts = instance_counts(defs, bodies, args.top, order)
    files = sorted({defs[m] for m in order}, key=lambda p: p.name)

    print(f"top={args.top}: {len(order)} modules in {len(files)} files, "
          f"{sum(f.stat().st_size for f in files) / 1e6:.1f} MB")
    mems = memories(bodies, order, counts)
    bits = sum(w * d * n for _, _, w, d, n in mems)
    print(f"memory arrays under {args.top} (instances counted): {sum(n for *_, n in mems)}, {bits} bits "
          f"= {bits / 8 / 1024:.1f} KiB before BRAM packing")
    for m, name, w, d, n in sorted(mems, key=lambda x: -x[2] * x[3] * x[4])[:12]:
        print(f"  {n:>4} x {m}.{name}: {d} x {w}  ({w * d * n / 8 / 1024:.1f} KiB)")

    if args.copy_to:
        dst = pathlib.Path(args.copy_to)
        dst.mkdir(parents=True, exist_ok=True)
        for f in files:
            shutil.copy2(f, dst / f.name)
    if args.list:
        pathlib.Path(args.list).write_text("".join(f.name + "\n" for f in files))


if __name__ == "__main__":
    main()
