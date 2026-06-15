# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Critical constraints

This is a **pure-Dart package** — no Flutter dependency is permitted, either
in the production code or in tooling. Do not use `flutter` commands (e.g.
`flutter test`, `flutter analyze`, `flutter pub`). Always use the `dart`
equivalents, preferably via the `Makefile` targets (e.g. `make test`,
`make analyze`).

## General

Work is planned using specifications in the `docs/plans` directory. When working
on plans make sure you review `docs/plans/README.md` file for guidance. When
asked to plan something do not commence implementation until explicitly told to
do so.

The `docs/roadmap` directory is used to track future work items and their
priority. This is worth reviewing when working on the codebase as current work
may intersect with the roadmap.

We'll create plans for our work and place them in the `docs/plans/` directory.
When the planned work has been completed we'll move them to
`docs/plans/completed`.

Quality assurance is critical to this project and you need to maintain a minimum
of 90% test coverage at all times. You must also run all tests successfully
before considering a task to be complete.

Consider edge-cases and failure scenarios when preparing tests - it is critical
not just to focus on easy, "golden-path" tests.

All public classes, methods and properties must have appropriate doc comments.
You may include examples in dec comments if you believe it will help another
developer.

Any complex segments of code should be commented so as to describe the process
and rationale for the approach.

All code files must have a license at the top. The template file is
@header_template.txt. You must add the comment syntax appropriate to the
programming language. Also replace `{{.Year}}` to match the current year.

## Repository Layout

```
lib/
  betto_charset_detector.dart   ← public barrel (exports detectCharset)
  src/
    charset_detector.dart       ← implementation
test/
  charset_detector_test.dart    ← unit tests (100% line coverage)
tool/
  probe_test.dart               ← manual canDecode investigation script
docs/
  plans/                        ← implementation plans
  roadmap/                      ← versioned roadmap
  spec/                         ← technical specification (Pandoc Markdown)
```

## Commands

The `Makefile` should contain all key development lifecycle commands. In
general, `make` should be preferred to directly running commands such as `dart`
and `flutter`.

```bash
# Run tests
make test

# Analyze/lint
make analyze

# Format code
make format

# Coverage
make coverage

# Build docs site (requires pandoc)
make site

# Run checks before committing code
make pre_commit
```

## Implementation Status

| Feature                  | Status   | Notes                                  |
| :----------------------- | :------- | :------------------------------------- |
| `detectCharset` function | Complete | BOM → UTF-8 → candidate probe pipeline |
| Test suite               | Complete | 44 tests, 100% line coverage           |
| Technical specification  | Complete | See `docs/spec/README.md`              |

## Architecture

The package is a single pure-Dart library with no Flutter or native
dependencies. The public API is one top-level function exported from the
barrel file. See `docs/spec/README.md` for the full technical specification,
including the three-stage detection algorithm, sampling policy, and the
guaranteed IANA label set.

## Documentation

Full specification is in [docs/spec/](docs/spec/) (Pandoc Markdown). The built
HTML lives in [site/](site/) and is generated via `make docs`. Key spec files:

- [docs/spec/README.md](docs/spec/README.md) — detection algorithm, sampling policy, supported encodings, IANA label contract
