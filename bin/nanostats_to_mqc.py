#!/usr/bin/env python3
"""
Turn NanoPlot NanoStats files into MultiQC custom content (*_mqc.json):
  - General Statistics: before/after filtering columns, one row per sample id
  - "Before filtering" and "After filtering" sections, each with a read
    statistics table and a reads-by-quality bar plot

The MultiQC nanostat module can't do this: run twice, both runs share the same
column keys and plot ids, so with id-based sample names the "after" values
overwrite the "before" ones.

Usage:   nanostats_to_mqc.py <stats_dir> <out_dir> [--filter-info TEXT]
Expects: <id>_<barcode>_<raw|filt>_NanoStats.txt   (see modules/local/nanoplot.nf)
"""

import argparse
import json
import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^(?P<id>.+)_[^_]+_(?P<stage>raw|filt)_NanoStats\.txt$")
QCUT_RE = re.compile(r"^>Q(?P<q>\d+):\s*(?P<n>[\d,.]+)")

# file-name stage -> (key, section name)
STAGES = {"raw": ("before", "Before filtering"), "filt": ("after", "After filtering")}

# NanoStats label -> (key, title, divisor, MultiQC column config)
METRICS = {
    "Number of reads":     ("reads",      "Reads",            1,   {"format": "{:,.0f}", "scale": "Blues"}),
    "Total bases":         ("bases_mb",   "Total bases (Mb)", 1e6, {"format": "{:,.1f}", "scale": "Greens"}),
    "Mean read length":    ("mean_len",   "Mean length",      1,   {"format": "{:,.0f}", "suffix": " bp", "scale": "Purples"}),
    "Median read length":  ("median_len", "Median length",    1,   {"format": "{:,.0f}", "suffix": " bp", "scale": "Purples"}),
    "Read length N50":     ("n50",        "Read N50",         1,   {"format": "{:,.0f}", "suffix": " bp", "scale": "Purples"}),
    "Mean read quality":   ("mean_q",     "Mean Q",           1,   {"format": "{:,.1f}", "scale": "RdYlGn"}),
    "Median read quality": ("median_q",   "Median Q",         1,   {"format": "{:,.1f}", "scale": "RdYlGn"}),
}
COLUMNS = {key: (label, title, cfg) for label, (key, title, _div, cfg) in METRICS.items()}

# Metrics shown as before/after pairs in General Statistics
GENERAL_STATS = ["reads", "median_len", "median_q"]


def parse_nanostats(path):
    """NanoStats file -> ({metric key: value}, {Q cutoff: reads above it})."""
    metrics, above_q = {}, {}
    for line in path.read_text().splitlines():
        m = QCUT_RE.match(line)
        if m:
            above_q[int(m["q"])] = float(m["n"].replace(",", ""))
            continue
        label, _, value = line.partition(":")
        if label.strip() in METRICS:
            key, _title, divisor, _cfg = METRICS[label.strip()]
            metrics[key] = float(value.replace(",", "")) / divisor
    return metrics, above_q


def quality_bins(total, above_q):
    """Cumulative '>Qn' read counts -> reads per bin: <Q10, Q10-15, ..., >Q30."""
    cuts = sorted(above_q)
    bins = {f"<Q{cuts[0]}": total - above_q[cuts[0]]}
    for lo, hi in zip(cuts, cuts[1:]):
        bins[f"Q{lo}-{hi}"] = above_q[lo] - above_q[hi]
    bins[f">Q{cuts[-1]}"] = above_q[cuts[-1]]
    return bins


def write_json(out_dir, name, content):
    with open(Path(out_dir) / f"{name}_mqc.json", "w") as fh:
        json.dump(content, fh, indent=1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stats_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--filter-info", default="", help="filter settings, shown in the 'After filtering' description")
    args = ap.parse_args()

    # stage key -> sample id -> metrics / quality bins
    metrics = {key: {} for key, _name in STAGES.values()}
    qbins = {key: {} for key, _name in STAGES.values()}
    for path in sorted(Path(args.stats_dir).glob("*_NanoStats.txt")):
        m = NAME_RE.match(path.name)
        if not m:
            sys.exit(f"Unexpected NanoStats file name: {path.name}")
        stage = STAGES[m["stage"]][0]
        values, above_q = parse_nanostats(path)
        metrics[stage][m["id"]] = values
        if above_q and "reads" in values:
            qbins[stage][m["id"]] = quality_bins(values["reads"], above_q)

    Path(args.out_dir).mkdir(parents=True, exist_ok=True)

    # General Statistics: before/after pairs (+ % reads kept) in one row per sample
    headers, data = {}, {}
    for key in GENERAL_STATS:
        label, title, cfg = COLUMNS[key]
        for stage, name in STAGES.values():
            headers[f"{key}_{stage}"] = {"title": f"{title} ({stage})", "description": f"{label}, {name.lower()}", **cfg}
            for sid, values in metrics[stage].items():
                if key in values:
                    data.setdefault(sid, {})[f"{key}_{stage}"] = values[key]
        if key == "reads":
            headers["pct_kept"] = {"title": "% Reads kept", "description": "Percentage of reads kept by NanoFilt",
                                   "suffix": "%", "min": 0, "max": 100, "scale": "RdYlGn"}
    for row in data.values():
        if row.get("reads_before") and "reads_after" in row:
            row["pct_kept"] = 100 * row["reads_after"] / row["reads_before"]
    write_json(args.out_dir, "general_stats", {
        "id": "read_qc_general_stats", "section_name": "Read QC",
        "plot_type": "generalstats", "pconfig": [{k: v} for k, v in headers.items()], "data": data,
    })

    # One report section per stage: statistics table + reads-by-quality bar plot
    descriptions = {
        "before": "NanoPlot statistics of the raw reads (unaligned BAM), before NanoFilt.",
        "after": f"NanoPlot statistics of the reads kept by NanoFilt ({args.filter_info}).".replace(" ()", ""),
    }
    for stage, name in STAGES.values():
        parent = {"parent_id": f"{stage}_filtering", "parent_name": name, "parent_description": descriptions[stage]}
        write_json(args.out_dir, f"{stage}_read_stats", {
            **parent, "id": f"{stage}_read_stats", "section_name": "Read statistics", "plot_type": "table",
            "pconfig": {"id": f"{stage}_read_stats_table", "title": f"{name}: read statistics", "namespace": name},
            "headers": {key: {"title": title, "description": label, **cfg} for key, (label, title, cfg) in COLUMNS.items()},
            "data": metrics[stage],
        })
        if qbins[stage]:
            write_json(args.out_dir, f"{stage}_read_quality", {
                **parent, "id": f"{stage}_read_quality", "section_name": "Reads by mean quality", "plot_type": "bargraph",
                "pconfig": {"id": f"{stage}_read_quality_plot", "title": f"{name}: reads by mean quality", "ylab": "Reads"},
                "data": qbins[stage],
            })


if __name__ == "__main__":
    main()
