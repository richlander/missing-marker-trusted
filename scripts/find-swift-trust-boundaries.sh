#!/usr/bin/env bash
#
# find-swift-trust-boundaries.sh
#
# Find safe functions that use `unsafe` expressions — Swift's implicit
# trust boundary. This is what D marks explicitly with @trusted.
#
# In Swift 6.2, `unsafe` is an expression prefix (not a block):
#   let p = unsafe someUnsafeCall()
# A trust boundary is a func NOT marked @unsafe that contains these.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, function, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - String literals containing "unsafe" cause false positives
#   - Multi-line string literals with braces skew brace counting
#   - Macros may hide or fabricate unsafe expressions
#   - @unsafe on a preceding line is detected with a lookback heuristic
#     (up to 8 lines); unusual formatting may cause misclassification
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-swift-trust-boundaries.sh [dir]
#   ./find-swift-trust-boundaries.sh ~/git/swiftlang-swift/stdlib

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe funcs wrapping unsafe expressions ..." >&2

printf "file\tline\tfunction\tsignature\n"

find "$DIR" -name '*.swift' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        for (n = 1; n <= NR; n++) {
            raw = lines[n]

            # Match func or init declarations
            is_func = 0
            if (raw ~ /[[:space:]]*(public|internal|private|fileprivate|open|package)?[[:space:]]*(static[[:space:]]+)?(mutating[[:space:]]+)?func[[:space:]]+/) is_func = 1
            if (raw ~ /[[:space:]]*(public|internal|private|fileprivate|open|package)?[[:space:]]*(static[[:space:]]+)?(required[[:space:]]+)?(convenience[[:space:]]+)?init[[:space:]]*[\(<]/) is_func = 1
            if (!is_func) continue

            # Check if this func is itself @unsafe by looking back up to 8 lines
            is_unsafe_decl = 0
            for (b = n - 1; b >= 1 && b >= n - 8; b--) {
                prev = lines[b]
                # Stop at blank lines or closing braces (different decl)
                if (prev ~ /^[[:space:]]*$/) break
                if (prev ~ /\}/) break
                if (prev ~ /^[[:space:]]*@unsafe[[:space:]]*$/) {
                    is_unsafe_decl = 1
                    break
                }
            }
            if (is_unsafe_decl) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract function name
            fn_name = ""
            if (raw ~ /func[[:space:]]/) {
                fn_name = raw
                sub(/.*func[[:space:]]+/, "", fn_name)
                sub(/[^a-zA-Z_0-9].*/, "", fn_name)
            } else {
                fn_name = "init"
            }

            # Walk the body tracking brace depth, looking for unsafe expressions
            depth = 0; started = 0; has_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)  # strip line comments

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }

                # Swift unsafe expressions: `unsafe expr` (not @unsafe, not "unsafe" in a string)
                # Match `unsafe` preceded by space/=/( and followed by space/letter
                if (j > n && line ~ /[[:space:](=]unsafe[[:space:]]/) has_unsafe = 1

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
