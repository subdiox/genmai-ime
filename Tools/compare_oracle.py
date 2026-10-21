#!/usr/bin/env python3
"""Compares converter_main (C++ oracle) output with genmai-engine output.

usage: Tools/compare_oracle.py EXPECTED ACTUAL [--commands FILE] [--show N]

Both files are converter_main outputs (or "=== <name> @<time>" runs of them,
see compare_oracle.sh): 4 banner lines, then one block per
input command. A block is either the line "ExecCommand() return false" or the
printed segments followed by an empty line (the segment key line after a
"---------- Segment" line may itself be empty). Before comparing:
- the banner is dropped (paths differ between runs; checked separately),
- `log:` lines and their indented continuation lines are removed: the oracle
  is a debug (fastbuild) build of converter_main, whose candidates carry debug
  logs (MOZC_DEBUG) that are not part of the parity target.

Prints the mismatching blocks (first N) and a summary line
"<name>: M/T commands match", and exits with 1 if any block differs.
"""

import argparse
import difflib
import sys

LOG_LINE = "       log:"
LOG_CONT = "           "  # 7 + 4 spaces


def strip_logs(lines):
    out = []
    in_log = False
    for line in lines:
        if line == LOG_LINE:
            in_log = True
            continue
        if in_log and line.startswith(LOG_CONT):
            continue
        in_log = False
        out.append(line)
    return out


def read_lines(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def runs(lines):
    """Splits a multi-run file ("=== <name> @<time>" + one converter_main run each)."""
    if not lines or not lines[0].startswith("=== "):
        return [("", lines)]
    result = []
    for line in lines:
        if line.startswith("=== "):
            # "=== <name> @<unix time the oracle ran>"
            result.append((line[4:].rsplit(" @", 1)[0], []))
        else:
            result[-1][1].append(line)
    return result


def blocks(lines):
    lines = strip_logs(lines[4:])
    result = []
    current = []
    expect_key = False
    for line in lines:
        if expect_key:
            # The segment key line after "---------- Segment i/n [...]" (may be
            # empty, e.g. for zero query suggestion).
            current.append(line)
            expect_key = False
            continue
        if line.startswith("---------- Segment "):
            current.append(line)
            expect_key = True
            continue
        if not current and line == "ExecCommand() return false":
            result.append([line])
            continue
        if line == "":
            result.append(current)
            current = []
            continue
        current.append(line)
    if current:
        result.append(current)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("expected")
    parser.add_argument("actual")
    parser.add_argument("--commands", help="command file, to label mismatches")
    parser.add_argument("--name", default="parity")
    parser.add_argument("--show", type=int, default=5)
    args = parser.parse_args()

    expected = []
    actual = []
    labels = []
    commands = read_lines(args.commands) if args.commands else []
    expected_runs = runs(read_lines(args.expected))
    actual_runs = dict(runs(read_lines(args.actual)))
    for name, lines in expected_runs:
        e = blocks(lines)
        a = blocks(actual_runs.get(name, ["", "", "", ""]))
        n = max(len(e), len(a))
        e += [["<missing>"]] * (n - len(e))
        a += [["<missing>"]] * (n - len(a))
        expected += e
        actual += a
        single = len(expected_runs) == 1
        labels += [(commands[i] if i < len(commands) else f"#{i}") if single else f"{name} #{i}"
                   for i in range(n)]

    total = max(len(expected), len(actual))
    mismatches = 0
    for i in range(total):
        e = expected[i] if i < len(expected) else ["<missing>"]
        a = actual[i] if i < len(actual) else ["<missing>"]
        if e == a:
            continue
        mismatches += 1
        if mismatches <= args.show:
            label = labels[i]
            print(f"*** MISMATCH {args.name} command {i}: {label}")
            for d in difflib.unified_diff(e, a, "oracle", "swift", n=2, lineterm=""):
                print(d)
    print(f"{args.name}: {total - mismatches}/{total} commands match")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
