## 0.0.1

- Initial release of the Dart Obfuscator CLI.

## 0.0.1+1

- Add `help` flag for CLI command.
- Fix README.md file errors.
- Fix various logic errors.

## 0.0.1+2

- Update README.md file.

## Unreleased

- Validate all inputs before modifying the file system; never delete a non-empty output directory not created by the tool,
  and refuse output directories equal to, within, or containing a source directory.
- Match declarations and references through the resolved element model, fixing references to shadowed names,
  inherited fields, object patterns, super parameters, redirecting factories and function-typed initializing formals.
- Keep fields overriding explicit accessors, third-party members or excluded declarations, including overrides
  without the `@override` annotation.
- Keep the fields of excluded classes, and match the `--pub` identifiers exactly.
- Update references in all package files, including `bin`, `test` and files excluded from analysis.
- Rewrite the merger using the analyzer: remove directives, first-party import prefixes and name clashes,
  and merge SDK constraints, dependency overrides, hosted URLs, path dependencies and Flutter assets.
- Add the `--seed` argument for deterministic output, and report errors without stack traces.
- Migrate to the analyzer 14 package (requires Dart 3.11), supporting primary constructors and private named
  parameters.
