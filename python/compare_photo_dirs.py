#!/usr/bin/env python3
"""Compare two photo/movie directory trees and write a Markdown report.

Usage:
    python compare_photo_dirs.py [DIR_A] [DIR_B] [-o report.md] [--hash]

Files are matched by relative path (case-insensitive, since OneDrive is
Windows-based). Matching files are compared by size, and optionally by SHA-256
content hash with --hash.
"""

import argparse
import hashlib
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

DEFAULT_A = "/host-home/OneDrive/Pictures"
DEFAULT_B = "/workspaces/photos"

IGNORED_DIRS = {"#recycle", "@eadir", ".@__thumb", "$recycle.bin"}
IGNORED_FILES = {"thumbs.db", "desktop.ini", ".ds_store", ".picasa.ini"}


def scan(root: Path) -> dict[str, tuple[Path, int]]:
    """Return {casefolded relative path: (absolute path, size)} for every file under root.

    Each file is stat'ed exactly once here; network mounts make repeated stats slow.
    """
    files: dict[str, tuple[Path, int]] = {}
    stack = [root]
    while stack:
        current = stack.pop()
        with os.scandir(current) as it:
            for entry in it:
                name = entry.name.casefold()
                if entry.is_dir(follow_symlinks=False):
                    if name not in IGNORED_DIRS:
                        stack.append(Path(entry.path))
                elif entry.is_file() and name not in IGNORED_FILES:
                    full = Path(entry.path)
                    files[full.relative_to(root).as_posix().casefold()] = (
                        full, entry.stat().st_size)
        if len(files) // 2000 != (len(files) - 1) // 2000 or not stack:
            print(f"  {len(files):,} files found...", file=sys.stderr)
    return files


def ext_of(path: Path) -> str:
    return path.suffix.lower() or "(none)"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def human(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{n} B"


def md_escape(text: str) -> str:
    return text.replace("|", "\\|")


def build_report(a_root: Path, b_root: Path, a: dict, b: dict, use_hash: bool,
                 list_limit: int) -> tuple[str, bool]:
    keys_a, keys_b = set(a), set(b)
    both = sorted(keys_a & keys_b)
    only_a = sorted(keys_a - keys_b)
    only_b = sorted(keys_b - keys_a)

    size_mismatch, hash_mismatch, errors = [], [], []
    for k in both:
        try:
            if a[k][1] != b[k][1]:
                size_mismatch.append(k)
            elif use_hash and sha256(a[k][0]) != sha256(b[k][0]):
                hash_mismatch.append(k)
        except OSError as e:
            errors.append((k, str(e)))

    identical = not (only_a or only_b or size_mismatch or hash_mismatch or errors)

    ext_a = Counter(ext_of(p) for p, _ in a.values())
    ext_b = Counter(ext_of(p) for p, _ in b.values())
    bytes_a = sum(size for _, size in a.values())
    bytes_b = sum(size for _, size in b.values())

    out: list[str] = []
    w = out.append
    w("# Photo Directory Comparison Report\n")
    w(f"Generated: {datetime.now():%Y-%m-%d %H:%M:%S}\n")
    w(f"- **A:** `{a_root}`")
    w(f"- **B:** `{b_root}`")
    w(f"- **Content check:** {'SHA-256 hash' if use_hash else 'file size only'}\n")
    w(f"## Result: {'✅ Directories match' if identical else '❌ Directories differ'}\n")

    w("## Summary\n")
    w("| Metric | A | B |")
    w("|---|---:|---:|")
    w(f"| Total files | {len(a):,} | {len(b):,} |")
    w(f"| Total size | {human(bytes_a)} | {human(bytes_b)} |")
    w(f"| Files in both | {len(both):,} | {len(both):,} |")
    w(f"| Only in this directory | {len(only_a):,} | {len(only_b):,} |")
    w(f"| Size mismatches | {len(size_mismatch):,} | |")
    if use_hash:
        w(f"| Same size, different content | {len(hash_mismatch):,} | |")
    w("")

    w("## File Types (by extension)\n")
    w("| Extension | A | B | Difference (A − B) |")
    w("|---|---:|---:|---:|")
    for ext in sorted(set(ext_a) | set(ext_b), key=lambda e: (-(ext_a[e] + ext_b[e]), e)):
        diff = ext_a[ext] - ext_b[ext]
        flag = "" if diff == 0 else " ⚠️"
        w(f"| `{ext}` | {ext_a[ext]:,} | {ext_b[ext]:,} | {diff:+,}{flag} |")
    w(f"| **Total** | **{len(a):,}** | **{len(b):,}** | **{len(a) - len(b):+,}** |")
    w("")

    def section(title: str, rows: list[str]) -> None:
        if not rows:
            return
        w(f"## {title} ({len(rows):,})\n")
        for r in rows[:list_limit]:
            w(f"- {r}")
        if len(rows) > list_limit:
            w(f"- … and {len(rows) - list_limit:,} more")
        w("")

    section("Only in A", [f"`{md_escape(a[k][0].relative_to(a_root).as_posix())}`" for k in only_a])
    section("Only in B", [f"`{md_escape(b[k][0].relative_to(b_root).as_posix())}`" for k in only_b])
    section("Size mismatches", [
        f"`{md_escape(a[k][0].relative_to(a_root).as_posix())}` "
        f"(A: {a[k][1]:,} B, B: {b[k][1]:,} B)"
        for k in size_mismatch
    ])
    section("Content mismatches (same size)",
            [f"`{md_escape(a[k][0].relative_to(a_root).as_posix())}`" for k in hash_mismatch])
    section("Errors", [f"`{md_escape(k)}`: {e}" for k, e in errors])

    return "\n".join(out) + "\n", identical


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir_a", nargs="?", default=DEFAULT_A)
    ap.add_argument("dir_b", nargs="?", default=DEFAULT_B)
    ap.add_argument("-o", "--output", default="comparison_report.md",
                    help="Markdown report path (default: %(default)s)")
    ap.add_argument("--hash", action="store_true",
                    help="Compare SHA-256 of files that exist in both (slow)")
    ap.add_argument("--list-limit", type=int, default=500,
                    help="Max entries per difference list (default: %(default)s)")
    args = ap.parse_args()

    a_root, b_root = Path(args.dir_a), Path(args.dir_b)
    for root in (a_root, b_root):
        if not root.is_dir():
            print(f"Error: directory not found: {root}", file=sys.stderr)
            return 2

    print(f"Scanning {a_root} ...", file=sys.stderr)
    a = scan(a_root)
    print(f"Scanning {b_root} ...", file=sys.stderr)
    b = scan(b_root)

    report, identical = build_report(a_root, b_root, a, b, args.hash, args.list_limit)
    Path(args.output).write_text(report, encoding="utf-8")
    print(f"Report written to {args.output}", file=sys.stderr)
    return 0 if identical else 1


if __name__ == "__main__":
    sys.exit(main())
