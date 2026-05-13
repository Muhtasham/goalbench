#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from html import unescape
from pathlib import Path
from urllib.request import Request, urlopen

PROGRAMBENCH_RUNS = {
    "gpt-5-5-xhigh": "https://programbench.com/run/gpt-5-5-xhigh/",
    "gpt-5-5-high": "https://programbench.com/run/gpt-5-5-high/",
}
ROW_RE = re.compile(r"<tr class=\"clickable-row\".*?</tr>", re.S)
CELL_RE = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
TAG_RE = re.compile(r"<[^>]+>")
STAT_RE = re.compile(r'<div class="stat-num">([^<]+)</div>\s*<div class="stat-label">(.*?)</div>', re.S)


def fetch(url: str) -> str:
    with urlopen(Request(url, headers={"User-Agent": "programbench-goal/0.1"}), timeout=30) as response:
        return response.read().decode("utf-8", "replace")


def clean_html(value: str) -> str:
    return " ".join(unescape(TAG_RE.sub(" ", value)).split())


def parse_percent(value: str) -> float | None:
    return None if value == "n/a" else float(value.rstrip("%")) / 100


def parse_money(value: str) -> float:
    return float(value.lstrip("$").replace(",", ""))


def parse_int(value: str) -> int:
    return int(value.replace(",", ""))


def parse_stats(html: str) -> dict:
    stats = {clean_html(label).split(" help_outline")[0]: value for value, label in STAT_RE.findall(html)}
    return {
        "resolved_rate": parse_percent(stats["Resolved"]),
        "almost_resolved_rate": parse_percent(stats["Almost Resolved"]),
        "total_cost_usd": parse_money(stats["Total Cost"]),
        "total_calls": parse_int(stats["Total Calls"]),
    }


def parse_run(slug: str, html: str) -> dict:
    rows = []
    for row in ROW_RE.findall(html):
        href = re.search(r'data-href="(/task/[^"]+/)"', row)
        cells = [clean_html(cell) for cell in CELL_RE.findall(row)]
        if len(cells) < 6 or not href:
            continue
        repo = re.search(r'<span class="model-name repo-name-truncate">([^<]+)</span>', row)
        desc = re.search(r'<span class="model-provider repo-desc-truncate">([^<]+)</span>', row)
        instance_id = href.group(1).split("/")[2]
        rows.append(
            {
                "instance_id": instance_id,
                "repository": clean_html(repo.group(1)) if repo else cells[1],
                "description": clean_html(desc.group(1)) if desc else "",
                "language": cells[2],
                "score": parse_percent(cells[3]),
                "cost_usd": parse_money(cells[4]),
                "calls": parse_int(cells[5]),
                "task_url": f"https://programbench.com/task/{instance_id}/",
            }
        )
    if len(rows) != 200:
        raise ValueError(f"{slug}: expected 200 per-instance rows, got {len(rows)}")
    return {**parse_stats(html), "instances": rows}


def refresh(args: argparse.Namespace) -> None:
    data = {
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "runs": {
            slug: {"slug": slug, "source": url, **parse_run(slug, fetch(url))}
            for slug, url in PROGRAMBENCH_RUNS.items()
        },
    }
    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(output)
    for slug, run in data["runs"].items():
        print(f"{slug},{len(run['instances'])},{run['total_cost_usd']},{run['total_calls']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Refresh ProgramBench public run-detail baseline rows")
    parser.add_argument("--output", default="docs/data/programbench-run-baselines.json")
    refresh(parser.parse_args())


if __name__ == "__main__":
    main()
