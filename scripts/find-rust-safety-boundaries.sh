#!/usr/bin/env bash
#
# find-rust-safety-boundaries.sh
#
# Find safe functions that contain unsafe {} blocks — Rust's implicit
# safety boundary. This is what D marks explicitly with @trusted.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, function, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - Block comments /* { } */ may skew brace counts
#   - String literals containing braces or "unsafe" cause false positives
#   - Macro invocations may hide or fabricate unsafe blocks
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-rust-safety-boundaries.sh [dir]
#   ./find-rust-safety-boundaries.sh ~/git/rust/library

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe fns wrapping unsafe blocks ..." >&2

printf "file\tline\tfunction\tsignature\n"

find "$DIR" -name '*.rs' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        for (n = 1; n <= NR; n++) {
            raw = lines[n]

            # Does this line declare a (safe) fn?
            if (raw !~ /^[[:space:]]*(pub(\([a-z]+\))?[[:space:]]+)?(const[[:space:]]+)?(async[[:space:]]+)?(extern[[:space:]]+"[^"]*"[[:space:]]+)?fn[[:space:]]+[a-z_]/) continue
            if (raw ~ /unsafe[[:space:]]+fn/) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract function name
            fn_name = raw
            sub(/.*fn[[:space:]]+/, "", fn_name)
            sub(/[^a-zA-Z_0-9].*/, "", fn_name)

            # Walk the body tracking brace depth
            depth = 0; started = 0; has_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)  # strip line comments

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }
                if (line ~ /unsafe[[:space:]]*\{/) has_unsafe = 1
                if (started && depth <= 0) break
            }

            if (has_unsafe) {
                printf "%s\t%d\t%s\t%s\n", RELFILE, fn_line, fn_name, fn_sig
            }

            # Skip past the body regardless of whether it had unsafe
            n = j
        }
    }
    ' RELFILE="${file#"$DIR"/}" "$file"
done

