# Dart Obfuscator

A command-line tool that obfuscates Dart (including Flutter) source code by renaming
declarations and their references using the Dart analyzer.

It is intended for preparing code to be shared as **private packages** or distributed
in source form while reducing readability by renaming classes and fields.

The tool works on copied project sources (it does not overwrite the original) and produces an obfuscated copy,
a single merged `merged.dart` file for the codebase, and a generated `pubspec.yaml` that reflects
dependencies found in the sources.

---

## Table of contents

- [Features](#features)
- [Quick start](#quick-start)
- [Usage](#usage)

  - [Required arguments](#required-arguments)
  - [Optional arguments](#optional-arguments)
  - [Example(s)](#examples)

- [How it works (high level)](#how-it-works-high-level)
- [Generated outputs](#generated-outputs)
- [Exclusion rules](#exclusion-rules)
- [Best practices / recommendations](#best-practices--recommendations)
- [Limitations & caveats](#limitations--caveats)
- [Security & legal considerations](#security--legal-considerations)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- Parse and resolve Dart source code using the Dart analyzer.
- Rename classes (including class type aliases) and fields (instance and static, including fields of mixins and enums),
  along with all of their references, matched through the resolved element model.
- Keep the program behaviour unchanged: fields overriding explicit getters/setters, third-party members,
  or excluded declarations keep their original names, and so do the members overriding them.
- Generate random obfuscated identifiers, or deterministic ones with the `--seed` argument.
- Work on copies of supplied source folders; originals remain untouched.
- Produce:

  - Obfuscated source tree (mirrors original structure inside output folder).
  - A single `merged.dart` combining code units where applicable.
  - A generated `pubspec.yaml` inferred from source imports/metadata.

- Support exclusion of items from obfuscation via annotation or object identifiers passed on the CLI (`--pub`).
- Intended workflow: obfuscate a codebase and share the obfuscated copy as a “private package”.

---

## Quick start

1. CLI Usage

1.1 Install the package

You can install the package from the command line:

```bash
dart pub global activate obfuscator
```

1.2 Run the obfuscator:

Once the package is installed, simply define the source (`--src`) and output (`--out`) directories,
and the tool will proceed with the obfuscation process.

Multiple projects can be setup for obfuscation by separating file paths with a comma.

```bash
obfuscator --src="/path/to/project1,/path/to/project2" --out="/path/to/output"
```

1.3 Optionally, provide annotation or object identifiers to exclude certain symbols from obfuscation:

Comma-separated list of identifiers entered with the `pub` argument are excluded from obfuscation.

```bash
dart run bin/obfuscator.dart --src ./my_app --out ./obf_out --pub NoObfuscation,AppLocalizations
```

2. Run From Source

The project can also be ran using it's source code:

2.1 Git clone

Repo is fetched to the device using git.

```bash
git clone https://github.com/ljmatan/obfuscator
```

2.2 Run the obfuscator:

Providing the comma-separated source directory locations as `src` named argument,
while also including the output directory location with the `out` argument.

```bash
dart run bin/obfuscator.dart --src "/path/to/project1,/path/to/project2" --out "/path/to/output"
```

2.3 Optionally, provide annotation or object identifiers to exclude certain symbols from obfuscation:

Comma-separated list of identifiers entered with the `pub` argument are excluded from obfuscation.

```bash
dart run bin/obfuscator.dart --src ./my_app --out ./obf_out --pub NoObfuscation,AppLocalizations
```

---

## Usage

Run the main entrypoint `bin/obfuscator.dart`. The program accepts command-line arguments.

### Required arguments

- `--src` — comma-separated list of source package paths. Each path must be a directory containing a `pubspec.yaml` file. Example:

  ```
  --src /home/user/projects/app1,/home/user/projects/libpkg
  ```

- `--out` — output directory where the processed (obfuscated) projects and generated artifacts will be written. The directory will be created if it does not exist (see the requirements below). Example:

  ```
  --out /home/user/obf-output
  ```

### Optional arguments

- `--pub` — comma-separated list of annotation or object identifiers (fully-qualified or simple)
  that mark declarations **not** to be obfuscated.

  The `NoObfuscation` and `publicApi` identifiers are always included.

  - Example:

    ```
    --pub NoObfuscation,MyCompany.DoNotObfuscate
    ```

- `--seed` — integer seed used for generating the obfuscated identifiers.
  Runs with the same seed and the same sources produce the same output.

Run `dart run bin/obfuscator.dart --help` for the full list and precise flag naming.

The output directory must be empty, missing, or created by a previous run of the tool
(marked with a `.obfuscator_output` file), as its contents are deleted on each run.
It must not be the same as, placed within, or contain any of the source directories.

### Examples

Obfuscate two projects and write output into `/tmp/obf`:

```bash
dart run bin/obfuscator.dart --src /projects/app1,/projects/shared_package --out /tmp/obf
```

Obfuscate a project while excluding declarations annotated with `NoObfuscation` and `Keep`:

```bash
dart run bin/obfuscator.dart --src ./app --out ./out --pub NoObfuscation,Keep
```

Example obfuscated code for various projects can be found in the `output` directory:
https://github.com/ljmatan/obfuscator/tree/main/output

---

## How it works (high level)

1. **Validate**: All of the inputs are validated before any file system changes are made.
2. **Copy**: The source packages are copied to the output directory (excluding `.git`, `.dart_tool` and `build`),
   relative path dependencies are made absolute, and `pub get` is run for each copy.
3. **Analysis**: Every Dart file of the copied packages is resolved with the Dart analyzer,
   including the files excluded with `analysis_options.yaml` (e.g., generated `*.g.dart` files).
4. **Discovery**: Classes and fields declared in the `lib` directories are collected, skipping the excluded ones.
   Fields overriding one another are grouped, and a group is renamed only if all of its members are renamable fields.
5. **Reference resolution**: All references resolving to the collected declarations are recorded in all of the package
   files (`lib`, `bin`, `test`, ...), including initializing formals, super parameters, named arguments, assignments,
   object patterns, combinators and documentation comments.
6. **Replace**: The copied files are rewritten with the generated names, and the mappings are recorded.
7. **Generate merged.dart**: The `lib` files are merged into a single library. Directives are removed,
   first-party import prefixes are dropped, clashing names are renamed, third-party exports of public
   libraries are kept, and extension invocations affected by the merge are made explicit.
8. **Generate pubspec.yaml**: The dependencies, SDK constraints and Flutter assets of the source packages are merged.

---

## Generated outputs

- `<out>/copy/<name>/...` — obfuscated copy of each provided source project.
- `<out>/lib/merged.dart` — single-file merge of the processed codebase.
- `<out>/pubspec.yaml` — generated `pubspec.yaml`, merged from the source packages. The merged package keeps
  the name of the source package if a single one is provided, and is named `merged_app` otherwise.
- `<out>/assets/...` — assets and fonts declared by the source packages.
- `<out>/mappings.json` — JSON map of original → obfuscated symbol names.

---

## Exclusion rules

- **Default exclusion**: the tool looks for the `NoObfuscation` and `publicApi` annotations (or other identifiers
  passed via `--pub`) and will not obfuscate any matching declarations.

- **What is excluded**:

  - An excluded class, mixin or enum keeps its name, along with the names of all of its fields.
  - An excluded field keeps its name, along with the fields overriding it or overridden by it.
  - Classes annotated with `freezed`, `Freezed`, `unfreezed` or `RoutePage` are always excluded.

- **How identifiers are matched**:

  - Exact match by annotation name (e.g., `NoObfuscation` for `@NoObfuscation()`).
  - Exact match by prefixed annotation name (e.g., `obfuscator.NoObfuscation` for `@obfuscator.NoObfuscation()`).
  - Exact match by class or field name (e.g., `--pub AppLocalizations`).

- **Common use cases**:

  - Keep public stable API names for interop with reflection / platform channels.
  - Exclude classes used by platform integration or code generation that requires stable names.

---

## Best practices / recommendations

- **Test the obfuscated build**: run `dart analyze` and `flutter test` / `dart test` on the obfuscated output before sharing to ensure no runtime breakages.
- **Annotate stable APIs** that must not be renamed (e.g., platform channel method names, reflection entries).
- **Limit the scope**: for very large projects, consider obfuscating only selected libraries to reduce risk.
- **Inspect mapping files** and retain them securely (they can be used to reverse-mapping in trusted contexts).

---

## Limitations & caveats

- **Not a security barrier**: source obfuscation increases effort to understand the code but is not a substitute for licensing, code access controls, or true binary-level obfuscation.
- **Complex reflection & mirrors**: if code uses `dart:mirrors`, `reflectable`, or string-based reflection, renaming may break runtime behavior unless you annotate/whitelist those symbols.
- **Generated code**: code generators (e.g., `build_runner`) may expect specific identifiers. Avoid renaming generated output unless you control the generator or also regenerate outputs appropriately.
- **Third-party packages**: External packages referenced by name must remain consistent in `pubspec.yaml`; the tool tries to infer package dependencies by import, but manual verification is recommended.
- **Edge cases in resolution**: some dynamic dispatch or runtime symbol lookups may not be detectable via static analysis; test thoroughly.
  Fields accessed on `dynamic` receivers keep their original names, but `Symbol` literals, `runtimeType.toString()`
  comparisons (class names are obfuscated), and constructor tear-offs assigned to function types with named parameters
  are not handled.
- **Merged output**: the merged file is a single library. Clashing top-level names, private members and import
  prefixes are renamed, and extension member invocations which could resolve differently are made explicit.
  Library-level annotations, conditional imports of first-party libraries, and extension operators, cascaded
  extension invocations or extension getters in object patterns (reported with a warning) may need manual
  adjustments. Libraries of older language versions (e.g., `// @dart=2.19`) are adapted to the language version
  of the merged file for class modifiers and wildcard variables (reported with a warning), while libraries without
  null safety can't be merged.
- **Invalid sources**: Dart files with syntax errors (e.g., templates) are neither obfuscated nor merged, and
  source files must be valid UTF-8.
  The `flutter: generate: true` (localizations) setting is not supported.
- **Legal**: ensure you have the right to obfuscate and distribute any source code; follow licenses and agreements.

---

## Security & legal considerations

- Keep obfuscation mappings confidential if they are used to de-obfuscate code within private contexts.
- Obfuscation is not encryption. If you need to protect intellectual property, also employ legal safeguards: licensing, access control, code repositories with restricted access.
- Verify license compatibility of third-party code before obfuscating and redistributing.

---

## Troubleshooting

- Symbols still refer to old names:

  - Ensure you run the tool on a **resolved AST** environment (the tool runs analyzer resolution internally for correctness).
  - Inspect `mappings.json` to confirm the mapping.
  - Fields overriding explicit getters or setters, third-party members, or excluded declarations are never renamed.

- Build or runtime errors after obfuscation:

  - Check for reflection usage or string-based lookups that reference symbol names.
  - Confirm generated `pubspec.yaml` dependencies are correct. If not, merge dependency entries from the original `pubspec.yaml` manually.

- If the tool fails to recognize a declaration, ensure the file is syntactically valid Dart and that all dependent packages are resolvable.
  The tool reports analysis errors of the copied sources as warnings, and stops if `pub get` fails for any of the copies.

---

## Development

Run the test suite, which obfuscates the fixture packages from `test/fixtures` and verifies that the obfuscated
and merged programs are valid and produce the same output as the original ones:

```bash
dart test
```

---

## Contributions

If you encounter a failure or incorrect obfuscation result,
please file a report on the GitHub issue tracker with:

- The error or stack trace (if any)
- A short code sample reproducing the issue
- The command you used (with arguments)

Your report helps improve the reliability of future releases.

## License

The probject is published with MIT license.

See the `LICENSE` file for details.
