#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BOLT+EPP Data Fusion Script

策略：用 EPP 数据提升 BOLT 计数
- BOLT fdata: 边级计数数据（100% 覆盖但只有热路径）
- EPP fdata: 位置级热度数据（包含更多路径）

融合逻辑：
1. 保留 BOLT 的完整格式（源→目标边的结构）
2. 如果 BOLT 的目标位置在 EPP 中有更高的热度，则提升计数
3. 输出保持 BOLT fdata 格式，确保兼容性
"""

import argparse
import os


def parse_bolt_fdata(filepath):
    """
    解析 BOLT fdata 格式
    格式：src_id src_func src_off dst_id dst_func dst_off mispredicts count
    返回: {edge_key: count, ...}, {edge_key: parts, ...}
    edge_key = (src_id, src_func, src_off, dst_id, dst_func, dst_off)
    """
    edges = {}
    lines = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                parts = line.split()
                if len(parts) < 8:
                    continue
                
                try:
                    src_id = parts[0]
                    src_func = parts[1]
                    src_off = parts[2]
                    dst_id = parts[3]
                    dst_func = parts[4]
                    dst_off = parts[5]
                    # parts[6] is mispredicts
                    cnt = int(parts[7])
                    
                    edge_key = (src_id, src_func, src_off, dst_id, dst_func, dst_off)
                    edges[edge_key] = cnt
                    lines[edge_key] = parts
                except (ValueError, IndexError):
                    continue
    
    except FileNotFoundError:
        print("警告: 文件未找到 {}".format(filepath))
        return {}, {}
    
    return edges, lines


def parse_epp_fdata(filepath):
    """
    解析 EPP fdata 格式
    格式: func_id func_name offset count
    返回: {(func_id, func_name, offset): count, ...}
    """
    positions = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('no_lbr'):
                    continue
                
                parts = line.split()
                if len(parts) < 4:
                    continue
                
                try:
                    func_id = parts[0]
                    func_name = parts[1]
                    offset = parts[2]
                    cnt = int(parts[3])
                    
                    pos_key = (func_id, func_name, offset)
                    positions[pos_key] = cnt
                except (ValueError, IndexError):
                    continue
    
    except FileNotFoundError:
        print("警告: 文件未找到 {}".format(filepath))
        return {}
    
    return positions


def boost_counts(bolt_edges, bolt_lines, epp_positions):
    """
    根据 EPP 数据提升 BOLT 计数
    - 如果目标函数在 EPP 中有高热度，增加 BOLT 到该目标的边权重
    - 保持原始 BOLT 结构，只修改计数
    """
    fused_lines = {}
    boosted_count = 0
    sidecar_rows = []
    
    for edge_key, bolt_count in bolt_edges.items():
        src_id, src_func, src_off, dst_id, dst_func, dst_off = edge_key
        
        # 检查目标是否在 EPP 中
        epp_key = (dst_id, dst_func, dst_off)
        
        parts = bolt_lines[edge_key][:]
        
        if epp_key in epp_positions:
            epp_count = epp_positions[epp_key]
            # 如果 EPP 计数明显大于 BOLT，则提升 BOLT 计数
            if epp_count > bolt_count:
                # 取加权平均：BOLT 70% + EPP 30%
                new_count = int(bolt_count * 0.7 + epp_count * 0.3)
                if new_count > bolt_count:
                    parts[7] = str(new_count)
                    boosted_count += 1
                    boost_ratio = float(new_count) / float(bolt_count) if bolt_count > 0 else 0.0
                    confidence = min(1.0, float(epp_count) / float(max(1, new_count)))
                    sidecar_rows.append({
                        "src_id": src_id,
                        "src_func": src_func,
                        "src_off": src_off,
                        "dst_id": dst_id,
                        "dst_func": dst_func,
                        "dst_off": dst_off,
                        "orig_count": bolt_count,
                        "epp_count": epp_count,
                        "fused_count": new_count,
                        "boost_ratio": boost_ratio,
                        "confidence": confidence,
                        "round_count": 1,
                        "coverage_gain": 1.0,
                        "recency_weight": 1.0,
                        "novelty_score": 0.0,
                    })
                    print("  ✓ 提升边: {} → {} (BOLT:{} + EPP:{} = {})".format(
                        dst_func, dst_off, bolt_count, epp_count, new_count))
        
        fused_lines[edge_key] = parts
    
    return fused_lines, boosted_count, sidecar_rows


def write_path_aware_sidecar(rows, output_path):
    """Write a minimal path-aware sidecar TSV for future BOLT in-tree integration."""
    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("# path-aware sidecar v1\n")
        f.write("# fields: src_id src_func src_off dst_id dst_func dst_off orig_count epp_count fused_count boost_ratio confidence round_count coverage_gain recency_weight novelty_score\n")
        for row in rows:
            f.write(
                "{src_id}\t{src_func}\t{src_off}\t{dst_id}\t{dst_func}\t{dst_off}\t{orig_count}\t{epp_count}\t{fused_count}\t{boost_ratio:.6f}\t{confidence:.6f}\t{round_count}\t{coverage_gain:.6f}\t{recency_weight:.6f}\t{novelty_score:.6f}\n".format(
                    **row
                )
            )

    print("✓ Path-aware sidecar: {} ({} boosted edges)".format(output_path, len(rows)))


def write_bolt_fdata(lines, output_path):
    """
    输出融合后的 BOLT fdata 文件（保持原始格式）
    """
    with open(output_path, 'w') as f:
        for edge_key in sorted(lines.keys()):
            parts = lines[edge_key]
            f.write(' '.join(parts) + '\n')
    
    print("\n✓ 融合后的 fdata 已写入: {}".format(output_path))
    print("  总边数: {}".format(len(lines)))


def main():
    parser = argparse.ArgumentParser(
        description='BOLT+EPP 数据融合 - 用 EPP 数据提升 BOLT 计数'
    )
    parser.add_argument('--bolt-fdata', required=True, help='BOLT 计数数据 (fdata)')
    parser.add_argument('--epp-fdata', required=True, help='EPP 单点数据')
    parser.add_argument('--out-fdata', required=True, help='输出融合后的 fdata')
    parser.add_argument('--out-path-aware', default='', help='可选: 输出 path-aware sidecar TSV')
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("BOLT+EPP 数据融合 (保持 BOLT 格式)")
    print("=" * 60)
    print()
    
    # 1. 解析 BOLT fdata
    print("[1/3] 解析 BOLT fdata: {}".format(args.bolt_fdata))
    bolt_edges, bolt_lines = parse_bolt_fdata(args.bolt_fdata)
    print("      ✓ 加载 {} 条边".format(len(bolt_edges)))
    print()
    
    # 2. 解析 EPP fdata
    print("[2/3] 解析 EPP fdata: {}".format(args.epp_fdata))
    epp_positions = parse_epp_fdata(args.epp_fdata)
    print("      ✓ 加载 {} 个位置".format(len(epp_positions)))
    print()
    
    # 3. 融合数据
    print("[3/3] 融合数据 (基于 EPP 提升)")
    print()
    fused_lines, boosted_count, sidecar_rows = boost_counts(bolt_edges, bolt_lines, epp_positions)
    print()
    print("      融合统计:")
    print("      ├─ BOLT 边数:          {} 条".format(len(bolt_edges)))
    print("      ├─ EPP 位置数:         {} 条".format(len(epp_positions)))
    print("      └─ 已提升的边数:       {} 条".format(boosted_count))
    print()
    
    # 4. 写出融合后的 fdata
    write_bolt_fdata(fused_lines, args.out_fdata)
    if args.out_path_aware:
        write_path_aware_sidecar(sidecar_rows, args.out_path_aware)
    print()
    print("=" * 60)
    print("融合完成！")
    print("=" * 60)


if __name__ == '__main__':
    main()
