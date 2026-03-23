#!/usr/bin/env python3
# -*- coding: gbk 2312 -*-
import argparse
import collections
import os
import re
import subprocess
import sys


def parse_epp_raw_profile(profile_path):
    # 格式:
    # fid num_paths
    # path_id_hex count
    result = []
    with open(profile_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = [ln.strip() for ln in f if ln.strip()]

    i = 0
    while i < len(lines):
        head = lines[i].split()
        if len(head) != 2:
            raise ValueError(f"Bad header line: {lines[i]}")
        fid = int(head[0], 10)
        npaths = int(head[1], 10)
        i += 1

        paths = {}
        for _ in range(npaths):
            if i >= len(lines):
                raise ValueError("Unexpected EOF while reading paths")
            p = lines[i].split()
            if len(p) < 2:
                raise ValueError(f"Bad path line: {lines[i]}")
            # Canonicalize path id to match decoder output (e.g. 000...00d -> d)
            pid = format(int(p[0], 16), "x")
            cnt = int(p[1], 10)
            paths[pid] = cnt
            i += 1

        if npaths > 0:
            result.append({"fid": fid, "paths": paths})

    return result


def parse_epp_decoded_paths(decoded_path):
    # 解析 llvm-epp -p 输出:
    # - name: func
    #   num_exec_paths: N
    #   - path: 1a
    #       - file.c,123
    out = []
    cur_func = None
    cur_path = None

    re_func = re.compile(r"^\s*-\s+name:\s*(.+?)\s*$")
    re_path = re.compile(r"^\s*-\s+path:\s*([0-9a-fA-F]+)\s*$")
    re_line = re.compile(r"^\s*-\s+(.+),([0-9]+)\s*$")

    with open(decoded_path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            line = raw.rstrip("\n")

            m = re_func.match(line)
            if m:
                name = m.group(1).strip()
                cur_func = {"name": name, "paths": {}}
                out.append(cur_func)
                cur_path = None
                continue

            m = re_path.match(line)
            if m and cur_func is not None:
                pid = m.group(1).lower()
                cur_func["paths"][pid] = []
                cur_path = pid
                continue

            m = re_line.match(line)
            if m and cur_func is not None and cur_path is not None:
                file_name = os.path.basename(m.group(1).strip())
                src_line = int(m.group(2), 10)
                cur_func["paths"][cur_path].append((file_name, src_line))

    return out


def _run_objdump_with_fallback(binary_path, objdump_bin):
    """Run an objdump-compatible tool and return stdout.

    Preference order:
    1) user supplied tool (typically llvm-objdump) with LLVM 5+ compatible flags
    2) user supplied tool with source-mixed disassembly
    3) GNU objdump fallback
    """

    candidates = [
        [objdump_bin, "-d", "-line-numbers", "--no-show-raw-insn", binary_path],
        [objdump_bin, "-d", "-S", "--no-show-raw-insn", binary_path],
        ["objdump", "-dSl", binary_path],
    ]

    errors = []
    for cmd in candidates:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if p.returncode == 0 and p.stdout:
            return p.stdout
        errors.append("{} => {}".format(" ".join(cmd), p.stderr.strip() or "empty output"))

    raise RuntimeError("objdump failed:\n" + "\n".join(errors))


def parse_objdump_line_map(binary_path, objdump_bin="llvm-objdump"):
    # 构建 (func, file_base, line) -> [addr...]
    out = _run_objdump_with_fallback(binary_path, objdump_bin)

    re_func = re.compile(r"^\s*([0-9a-fA-F]+)\s+<(.+)>:\s*$")
    re_func_alt = re.compile(r"^\s*([.$A-Za-z_][\w.$@]*)\s*:\s*$")
    re_fileline = re.compile(r"^\s*(.+):([0-9]+)\s*$")
    re_insn = re.compile(r"^\s*([0-9a-fA-F]+):")

    cur_func = None
    cur_file = None
    cur_line = None

    mp = collections.defaultdict(list)

    for ln in out.splitlines():
        mf = re_func.match(ln)
        if mf:
            cur_func = mf.group(2)
            cur_file = None
            cur_line = None
            continue

        mf2 = re_func_alt.match(ln)
        if mf2 and not ln.lstrip().startswith("Disassembly of section"):
            cur_func = mf2.group(1)
            cur_file = None
            cur_line = None
            continue

        ml = re_fileline.match(ln)
        if ml:
            cur_file = os.path.basename(ml.group(1).strip())
            cur_line = int(ml.group(2), 10)
            continue

        mi = re_insn.match(ln)
        if mi and cur_func is not None and cur_file is not None and cur_line is not None:
            addr = int(mi.group(1), 16)
            key = (cur_func, cur_file, cur_line)
            mp[key].append(addr)

    return mp


def build_samples(raw_entries, decoded_entries, line_map):
    # 利用“顺序一致性”把 raw(fid/path/count) 对齐到 decoded(func/path/lines)
    # 这是 llvm-epp 当前输出结构下最稳妥的无侵入做法
    if len(raw_entries) != len(decoded_entries):
        print(
            f"warning: raw executed funcs={len(raw_entries)} != decoded funcs={len(decoded_entries)}; using min length",
            file=sys.stderr,
        )

    n = min(len(raw_entries), len(decoded_entries))
    addr_count = collections.Counter()

    for idx in range(n):
        rawf = raw_entries[idx]
        decf = decoded_entries[idx]
        fname = decf["name"]

        for pid, cnt in rawf["paths"].items():
            if cnt <= 0:
                continue
            if pid not in decf["paths"]:
                continue

            # 去重，避免同一路径内同一源码行重复加权
            uniq_lines = list(dict.fromkeys(decf["paths"][pid]))
            for file_base, src_line in uniq_lines:
                key = (fname, file_base, src_line)
                addrs = line_map.get(key)
                if not addrs:
                    continue
                # 选择第一个地址作为该行采样点
                addr_count[addrs[0]] += cnt

    return addr_count


def write_preaggregated_basic(samples, out_path):
    # perf2bolt --pa 可读格式:
    # E cycles
    # S <hex_addr> <count>
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("E cycles\n")
        for addr in sorted(samples.keys()):
            f.write(f"S {addr:x} {samples[addr]}\n")


def run_perf2bolt(perf2bolt_bin, binary_path, preagg_path, out_fdata):
    cmd = [
        perf2bolt_bin,
        binary_path,
        "--pa",
        "-ba",
        "-p",
        preagg_path,
        "-o",
        out_fdata,
        "-ignore-build-id",
    ]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"perf2bolt failed:\n{p.stdout}\n{p.stderr}")


def main():
    ap = argparse.ArgumentParser(description="Convert EPP paths to BOLT profile (pre-aggregated basic samples)")
    ap.add_argument("--profile", required=True, help="EPP raw profile file, e.g. xxx.profile")
    ap.add_argument("--decoded", required=True, help="EPP decoded paths text from llvm-epp -p")
    ap.add_argument("--binary", required=True, help="Target ELF binary for address mapping")
    ap.add_argument("--out-preagg", required=True, help="Output pre-aggregated profile txt")
    ap.add_argument("--out-fdata", default="", help="Optional output fdata via perf2bolt")
    ap.add_argument("--objdump", default="llvm-objdump", help="objdump binary")
    ap.add_argument("--perf2bolt", default="perf2bolt", help="perf2bolt binary")
    args = ap.parse_args()

    raw_entries = parse_epp_raw_profile(args.profile)
    decoded_entries = parse_epp_decoded_paths(args.decoded)
    line_map = parse_objdump_line_map(args.binary, args.objdump)

    samples = build_samples(raw_entries, decoded_entries, line_map)
    if not samples:
        raise RuntimeError("No samples generated. Check debug info, decoded paths, and objdump line mapping.")

    write_preaggregated_basic(samples, args.out_preagg)
    print(f"Generated pre-aggregated profile: {args.out_preagg} ({len(samples)} samples)")

    if args.out_fdata:
        run_perf2bolt(args.perf2bolt, args.binary, args.out_preagg, args.out_fdata)
        print(f"Generated fdata: {args.out_fdata}")


if __name__ == "__main__":
    main()