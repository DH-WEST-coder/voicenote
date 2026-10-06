#!/usr/bin/env python3
"""Fail if any bundled Mach-O advertises a minimum OS above the requested one."""
import re
import subprocess
import sys
from pathlib import Path


def version(value: str):
    return tuple(int(part) for part in value.split("."))


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("사용: check_app_minos.py APP MAXIMUM")
    app, maximum = Path(sys.argv[1]), version(sys.argv[2])
    failures = []
    count = 0
    for path in app.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        kind = subprocess.run(["/usr/bin/file", "-b", str(path)], text=True,
                              capture_output=True, check=True).stdout
        if "Mach-O" not in kind:
            continue
        count += 1
        loads = subprocess.run(["/usr/bin/otool", "-l", str(path)], text=True,
                               capture_output=True, check=True).stdout
        minos = re.findall(r"^\s*minos\s+([0-9]+(?:\.[0-9]+)*)\s*$", loads, re.M)
        if not minos:
            failures.append(f"{path}: LC_BUILD_VERSION minos 없음")
            continue
        for found in minos:
            if version(found) > maximum:
                failures.append(f"{path}: minos {found} > {sys.argv[2]}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"앱 Mach-O minos 검사 통과: {count}개, 최대 {sys.argv[2]}")


if __name__ == "__main__":
    main()
