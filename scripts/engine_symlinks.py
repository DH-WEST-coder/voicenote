#!/usr/bin/env python3
"""Restore and verify PyInstaller engine symlinks after Tauri resource copying."""
import os
import shutil
import sys
from pathlib import Path


def source_links(root: Path):
    root = root.resolve()
    for current, dirs, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        names = list(dirs) + files
        # os.walk lists symlinked directories in dirs without following them.
        for name in names:
            path = current_path / name
            if path.is_symlink():
                yield root, path, os.readlink(path)


def link_target(root: Path, source_link: Path, raw_target: str, dest: Path, dest_link: Path) -> str:
    resolved = (source_link.parent / raw_target).resolve(strict=False)
    if not os.path.isabs(raw_target):
        try:
            resolved.relative_to(root)
            return raw_target
        except ValueError:
            return os.path.relpath(resolved, dest_link.parent)
    try:
        relative_inside = resolved.relative_to(root)
    except ValueError:
        return os.path.relpath(resolved, dest_link.parent)
    # Point at the corresponding object in the copied engine tree. This also
    # normalizes absolute source links into relative bundle links.
    target_in_bundle = dest / relative_inside
    return os.path.relpath(target_in_bundle, dest_link.parent)


def replace_with_link(path: Path, target: str) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.symlink_to(target)


def restore(source: Path, dest: Path) -> None:
    root = source.resolve()
    for _, source_link, raw_target in source_links(root):
        relative = source_link.relative_to(root)
        dest_link = dest / relative
        replace_with_link(dest_link, link_target(root, source_link, raw_target, dest, dest_link))


def check(source: Path, dest: Path) -> None:
    root = source.resolve()
    count = 0
    for _, source_link, raw_target in source_links(root):
        relative = source_link.relative_to(root)
        dest_link = dest / relative
        expected = link_target(root, source_link, raw_target, dest, dest_link)
        if not dest_link.is_symlink():
            raise SystemExit(f"링크가 일반 파일/디렉터리로 남음: {dest_link}")
        actual = os.readlink(dest_link)
        if actual != expected:
            raise SystemExit(f"링크 대상 불일치: {dest_link}: {actual!r} != {expected!r}")
        count += 1
    print(f"엔진 symlink 검사 통과: {count}개")


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in {"restore", "check"}:
        raise SystemExit("사용: engine_symlinks.py restore|check SOURCE DEST")
    mode, source, dest = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    if not source.is_dir() or not dest.is_dir():
        raise SystemExit("원본 및 대상 엔진 디렉터리가 필요합니다")
    (restore if mode == "restore" else check)(source, dest)


if __name__ == "__main__":
    main()
