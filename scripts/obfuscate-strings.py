#!/usr/bin/env python3
"""Rewrites URL/host/path string literals in the native resolver .cpp files
into XOR-encoded byte arrays decoded at runtime via zs_deob().

Only ever run against a throwaway CI checkout (see
.github/workflows/build-ipa-hardened.yml) — never commits its output back to
the repo. Leaves anything that isn't a plain double-quoted C++ string literal
(format strings with escapes we don't understand, raw strings, etc.) alone.
"""
import re
import sys
import random
from pathlib import Path

NATIVE_DIR = Path(__file__).resolve().parent.parent / "ZStream/Sources/Native/cpp"

# Only literals that look like URLs/hosts/paths are worth hiding — leave
# short/generic literals (JSON keys, single chars, format punctuation) alone
# to keep the diff small and avoid touching anything load-bearing like
# printf-style format specifiers.
TARGET_RE = re.compile(r'"((?:https?://|/)[A-Za-z0-9_./\-?=&:%]{3,})"')

STRING_LITERAL_RE = re.compile(r'"(?:[^"\\]|\\.)*"')

# Matches an entire // line comment (to end of line) so we can skip over it
# without treating quoted text inside it as a real literal.
LINE_COMMENT_RE = re.compile(r'//[^\n]*')

CODE_OR_COMMENT_RE = re.compile(
    f'(?P<comment>{LINE_COMMENT_RE.pattern})|(?P<literal>{STRING_LITERAL_RE.pattern})'
)

# zs_deob() returns std::string at runtime — it cannot initialize a
# constexpr/const char array or pointer (not a constant expression, and a
# `const char*` would dangle pointing at a temporary), nor sit inside an
# aggregate-initializer entry for a struct with const char* fields. Skip
# those declaration/initializer contexts entirely and only touch literals
# used inline inside function-body expressions.
UNSAFE_LINE_RE = re.compile(
    r'^\s*(constexpr|const)\s+char\b'  # const char* / constexpr char[] decls
    r'|^\s*\{"'                        # aggregate-init entries, e.g. {"yoru", ...}
)


def encode(s: str, key: int) -> str:
    b = s.encode("utf-8")
    xored = bytes(c ^ key for c in b)
    hex_bytes = ",".join(f"0x{c:02x}" for c in xored)
    return f'zs_deob((const unsigned char[]){{{hex_bytes}}}, {len(b)}, 0x{key:02x})'


def process_line(line: str) -> tuple[str, int]:
    if UNSAFE_LINE_RE.match(line):
        return line, 0

    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        if m.group("comment") is not None:
            return m.group(0)
        literal = m.group("literal")
        target = TARGET_RE.fullmatch(literal)
        if not target:
            return literal
        key = random.randint(1, 255)
        count += 1
        return encode(target.group(1), key)

    return CODE_OR_COMMENT_RE.sub(repl, line), count


def process_file(path: Path) -> int:
    lines = path.read_text().splitlines(keepends=True)
    count = 0
    out_lines = []
    for line in lines:
        new_line, n = process_line(line)
        out_lines.append(new_line)
        count += n
    if count:
        path.write_text("".join(out_lines))
    return count


def main() -> None:
    if not NATIVE_DIR.is_dir():
        print(f"error: {NATIVE_DIR} not found", file=sys.stderr)
        sys.exit(1)

    total = 0
    for path in sorted(NATIVE_DIR.glob("*.cpp")):
        if path.name == "net_common.cpp":
            # Houses zs_deob itself and low-level URL parsing helpers —
            # leave untouched to avoid self-reference issues.
            continue
        n = process_file(path)
        if n:
            print(f"{path.name}: obfuscated {n} literal(s)")
        total += n

    print(f"total: {total} string literal(s) obfuscated")


if __name__ == "__main__":
    main()
