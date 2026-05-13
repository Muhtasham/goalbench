#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def load_instance_ids(programbench_repo: Path) -> list[str]:
    tasks_dir = programbench_repo / "src" / "programbench" / "data" / "tasks"
    return sorted(path.name for path in tasks_dir.iterdir() if path.is_dir() and (path / "task.yaml").is_file())


def main() -> None:
    parser = argparse.ArgumentParser(description="Write ProgramBench instance IDs to a target set file")
    parser.add_argument("programbench_repo")
    parser.add_argument("--output", default="target_sets/all_tasks.txt")
    parser.add_argument("--include-fixtures", action="store_true")
    args = parser.parse_args()

    ids = [
        instance_id
        for instance_id in load_instance_ids(Path(args.programbench_repo).expanduser().resolve())
        if args.include_fixtures or not instance_id.startswith("testorg__")
    ]

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "# Generated from ProgramBench task metadata.\n"
        "# Excludes test fixtures by default; rerun scripts/write-target-set.py "
        "with --include-fixtures to include them.\n" + "\n".join(ids) + "\n"
    )
    print(f"{output} instances={len(ids)}")


if __name__ == "__main__":
    main()
