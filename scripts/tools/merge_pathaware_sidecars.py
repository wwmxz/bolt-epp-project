#!/usr/bin/env python3
import argparse
import collections
from dataclasses import dataclass
from pathlib import Path


@dataclass
class EdgeAgg:
    src_id: str
    src_func: str
    src_off: str
    dst_id: str
    dst_func: str
    dst_off: str
    max_count: int = 0
    conf_sum: float = 0.0
    rounds_seen: int = 0
    first_seen_round: int = 0
    last_seen_round: int = 0
    recency_weighted_sum: float = 0.0


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def parse_sidecar_rows(path: Path):
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line_no, line in enumerate(f, 1):
            if line_no == 1 or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 11:
                continue
            try:
                fused_count = int(parts[8])
                confidence = float(parts[10])
            except ValueError:
                continue

            yield {
                "src_id": parts[0],
                "src_func": parts[1],
                "src_off": parts[2],
                "dst_id": parts[3],
                "dst_func": parts[4],
                "dst_off": parts[5],
                "fused_count": fused_count,
                "confidence": confidence,
            }


def merge_sidecars(inputs, policy: str):
    merged = collections.OrderedDict()
    total_rounds = len(inputs)

    for round_idx, path in enumerate(inputs, 1):
        recency_w = round_idx / max(1, total_rounds)
        for row in parse_sidecar_rows(path):
            key = (row["dst_func"], row["src_off"], row["dst_off"])
            if key not in merged:
                merged[key] = EdgeAgg(
                    src_id=row["src_id"],
                    src_func=row["src_func"],
                    src_off=row["src_off"],
                    dst_id=row["dst_id"],
                    dst_func=row["dst_func"],
                    dst_off=row["dst_off"],
                    first_seen_round=round_idx,
                    last_seen_round=round_idx,
                )

            agg = merged[key]
            agg.max_count = max(agg.max_count, row["fused_count"])
            agg.conf_sum += row["confidence"]
            agg.rounds_seen += 1
            agg.last_seen_round = round_idx
            agg.recency_weighted_sum += recency_w

    out_rows = []
    for _, agg in sorted(merged.items(), key=lambda kv: kv[0]):
        avg_conf = agg.conf_sum / max(1, agg.rounds_seen)
        coverage_gain = agg.rounds_seen / max(1, total_rounds)
        recency_weight = agg.recency_weighted_sum / max(1, agg.rounds_seen)
        if total_rounds > 1:
            novelty_score = (agg.first_seen_round - 1) / (total_rounds - 1)
        else:
            novelty_score = 0.0

        fused_count = agg.max_count
        confidence = clamp(avg_conf, 0.0, 1.0)
        if policy == "coverage-priority":
            # Prefer edges that improve cross-round coverage while preserving stability.
            fused_count = int(round(fused_count * (1.0 + 0.25 * novelty_score)))
            confidence = clamp(
                confidence * (0.85 + 0.15 * coverage_gain),
                0.0,
                1.0,
            )

        out_rows.append(
            {
                "src_id": agg.src_id,
                "src_func": agg.src_func,
                "src_off": agg.src_off,
                "dst_id": agg.dst_id,
                "dst_func": agg.dst_func,
                "dst_off": agg.dst_off,
                "orig_count": 0,
                "epp_count": 0,
                "fused_count": max(0, fused_count),
                "boost_ratio": 1.0,
                "confidence": confidence,
                "round_count": agg.rounds_seen,
                "coverage_gain": coverage_gain,
                "recency_weight": recency_weight,
                "novelty_score": novelty_score,
            }
        )

    return out_rows


def write_output(rows, output_path: Path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as out:
        out.write(
            "src_id\tsrc_func\tsrc_off\tdst_id\tdst_func\tdst_off\t"
            "orig_count\tepp_count\tfused_count\tboost_ratio\tconfidence\t"
            "round_count\tcoverage_gain\trecency_weight\tnovelty_score\n"
        )
        for row in rows:
            out.write(
                "{src_id}\t{src_func}\t{src_off}\t{dst_id}\t{dst_func}\t{dst_off}\t"
                "{orig_count}\t{epp_count}\t{fused_count}\t{boost_ratio:.6f}\t"
                "{confidence:.6f}\t{round_count}\t{coverage_gain:.6f}\t"
                "{recency_weight:.6f}\t{novelty_score:.6f}\n".format(**row)
            )


def main():
    ap = argparse.ArgumentParser(description="Merge path-aware sidecars from multiple rounds")
    ap.add_argument("--output", required=True, help="Output merged sidecar TSV")
    ap.add_argument("--inputs", nargs="+", required=True, help="Input sidecar TSV files")
    ap.add_argument(
        "--policy",
        default="maxavg",
        choices=["maxavg", "coverage-priority"],
        help="Merge policy",
    )
    args = ap.parse_args()

    input_paths = [Path(p) for p in args.inputs]
    rows = merge_sidecars(input_paths, args.policy)
    write_output(rows, Path(args.output))
    print(f"merged_rows={len(rows)} policy={args.policy} output={args.output}")


if __name__ == "__main__":
    main()