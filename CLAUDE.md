# CLAUDE.md

## What This Is

A technical paper comparing memory safety trust boundary discoverability
across D, Rust, Swift, and C#, with supporting analysis scripts.

## File Structure

- `paper.md` -- The main paper
- `scripts/` -- Bash scripts for trust boundary analysis
  - `find-rust-trust-boundaries.sh` -- Finds safe Rust fns wrapping unsafe blocks
  - `find-swift-trust-boundaries.sh` -- Finds safe Swift funcs wrapping unsafe expressions
  - `find-csharp-trust-boundaries.sh` -- Finds safe C# methods wrapping unsafe blocks
  - `find-csharp-unsafe-methods.sh` -- Finds all unsafe C# methods (explicit + implicit)

## Conventions

- Scripts target specific repos: Rust (rust-lang/rust), Swift (swiftlang/swift),
  D (dlang/phobos), C# (dotnet/runtime). They expect a directory argument.
- The paper references scripts by relative path; do not inline full scripts.
- Output samples in the paper should be kept short (~10 lines) for readability.
- Language in the paper should be measured and professional -- suitable for
  public sharing with language design communities.

## Terminology

- **Trust boundary** = the transition point from unsafe to safe code (D's `@trusted`)
- **Discoverability** = ability to find trust boundaries with grep/ripgrep alone
- **Lossless** = every safety attestation is explicitly recorded in source
  and visible to git blame
- **Inference** = the degree of contextual reasoning needed to determine a
  method's safety role

## Editorial Guidelines

- Avoid "fail" / "gold star" or pass/fail language; use "discoverable" /
  "requires inference" / "not directly discoverable"
- Acknowledge design tradeoffs in other languages rather than dismissing them
- Keep the Silverlight security transparency parallel as a key supporting argument
- The scorecard table should stay synchronized with any script result changes
