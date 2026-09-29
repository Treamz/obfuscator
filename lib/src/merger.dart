import 'dart:io' as dart_io;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart' as analyzer_context;
import 'package:analyzer/dart/analysis/results.dart' as analyzer_results;
import 'package:analyzer/dart/ast/ast.dart' as analyzer_ast;
import 'package:analyzer/dart/ast/token.dart' as analyzer_token;
import 'package:analyzer/dart/ast/visitor.dart' as analyzer_visitor;
import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart' as pub_semver;
import 'package:pubspec_parse/pubspec_parse.dart' as pubspec_parse;
import 'package:yaml_edit/yaml_edit.dart' as yaml_edit;

/// Resolved `lib` file of an obfuscated package, prepared for merging.
///
class _MergedSource {
  _MergedSource({
    required this.package,
    required this.filePath,
    required this.result,
  });

  final SourcePackage package;

  final String filePath;

  final analyzer_results.ResolvedUnitResult result;

  /// Text replacements applied to the file contents before merging.
  ///
  final edits = <({int offset, int end, String text})>[];

  void addEdit(int offset, int end, String text) {
    if (!edits.any((edit) => edit.offset == offset && edit.end == end && edit.text == text)) {
      edits.add((offset: offset, end: end, text: text));
    }
  }
}

/// Reference to a top-level declaration, which may require renaming or a prefix in the merged file.
///
class _TopLevelReference {
  _TopLevelReference({
    required this.source,
    required this.offset,
    required this.end,
    required this.element,
  });

  final _MergedSource source;

  final int offset;

  final int end;

  final analyzer_element.Element element;
}

/// Class used for merging all of the available source code directories into a single file.
///
class ProjectMerger {
  /// Class used for merging all of the available source code directories into a single file,
  /// according to the provided [configuration].
  ///
  ProjectMerger({
    required Configuration configuration,
    required ObjectCollector collector,
  }) : _configuration = configuration,
       _collector = collector;

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// Property holding the value of the main object collector.
  ///
  final ObjectCollector _collector;

  /// Whether the [library] is one of the obfuscated libraries, merged into the output file.
  ///
  bool _isMergedLibrary(analyzer_element.LibraryElement? library) {
    if (library == null) return false;
    final uri = library.uri;
    if (uri.scheme == 'package') {
      return uri.pathSegments.isNotEmpty && _configuration.sourcePackages.contains(uri.pathSegments.first);
    }
    if (uri.scheme == 'file') {
      final filePath = uri.toFilePath();
      return _configuration.packages.any((package) => path.isWithin(path.join(package.copyDirectory.path, 'lib'), filePath));
    }
    return false;
  }

  /// Returns the top-level declaration an [element] reference resolves to, if any.
  ///
  static analyzer_element.Element? _topLevelElement(analyzer_element.Element? element) {
    if (element == null) return null;
    var base = element.baseElement;
    if (base is analyzer_element.ConstructorElement) return null;
    if (base is analyzer_element.PropertyAccessorElement) base = base.variable;
    if (base is analyzer_element.PrefixElement || base is analyzer_element.LibraryElement) return null;
    if (base.enclosingElement is! analyzer_element.LibraryElement) return null;
    final name = base.name;
    if (name == null || name.isEmpty || base.library == null) return null;
    return base;
  }

  /// Unique identifier of a top-level [element].
  ///
  static String _topLevelKey(analyzer_element.Element element) => '${element.library!.uri}#${element.name}';

  /// Resolves the `lib` files of the obfuscated packages.
  ///
  Future<List<_MergedSource>> _resolveSources(analyzer_context.AnalysisContextCollection collection) async {
    final sources = <_MergedSource>[];
    for (final package in _configuration.packages) {
      final libPath = path.join(package.copyDirectory.path, 'lib');
      for (final filePath in ObjectCollector.listDartFiles(package)) {
        if (!path.isWithin(libPath, filePath)) continue;
        final context = ObjectCollector.contextFor(collection, filePath);
        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is! analyzer_results.ResolvedUnitResult) {
          throw ConfigurationException('Unable to analyze "$filePath" for merging: ${result.runtimeType}.');
        }
        sources.add(_MergedSource(package: package, filePath: filePath, result: result));
      }
    }
    return sources;
  }

  /// Collects the directive removals, and the references to top-level declarations.
  ///
  List<_TopLevelReference> _prepareSources(
    List<_MergedSource> sources,
    List<String> imports,
  ) {
    final references = <_TopLevelReference>[];
    for (final source in sources) {
      for (final directive in source.result.unit.directives) {
        if (directive is analyzer_ast.ImportDirective) {
          final importedLibrary = directive.libraryImport?.importedLibrary;
          if (!_isMergedLibrary(importedLibrary)) {
            final import = directive.toSource();
            if (!imports.contains(import)) imports.add(import);
            if (importedLibrary == null) {
              print('Warning: unresolved import "${directive.uri.stringValue}" in ${source.filePath}.');
            }
          }
        }
        source.addEdit(directive.offset, _endOfTrailingComment(source.result.content, directive.end), '');
      }
      source.result.unit.accept(
        _MergeReferenceVisitor(
          merger: this,
          source: source,
          references: references,
        ),
      );
    }
    return references;
  }

  /// Returns the end of a comment following the [offset] on the same line, or the [offset] itself.
  ///
  static int _endOfTrailingComment(String contents, int offset) {
    final lineEnd = contents.indexOf('\n', offset);
    final rest = contents.substring(offset, lineEnd == -1 ? contents.length : lineEnd);
    return RegExp(r'^[ \t]*//').hasMatch(rest) ? offset + rest.trimRight().length : offset;
  }

  /// Finds the top-level names which would clash once the libraries are merged, and renames them.
  ///
  /// First-party top-level declarations are renamed if the same name is declared by multiple
  /// libraries, or if the name refers to a different, third-party declaration in any of the libraries.
  /// Third-party references with ambiguous names are prefixed with a dedicated import.
  ///
  void _resolveNameClashes(
    List<_MergedSource> sources,
    List<_TopLevelReference> references,
    List<String> imports,
  ) {
    // First-party top-level declarations, in the order of declaration.
    final declarations = <String, analyzer_element.Element>{};
    for (final source in sources) {
      for (final declaration in source.result.unit.declarations) {
        for (final (element, _) in _declaredTopLevelElements(declaration)) {
          declarations.putIfAbsent(_topLevelKey(element), () => element);
        }
      }
    }
    final externalReferencesByName = <String, Map<String, List<_TopLevelReference>>>{};
    for (final reference in references) {
      if (_isMergedLibrary(reference.element.library)) continue;
      externalReferencesByName
          .putIfAbsent(reference.element.name!, () => {})
          .putIfAbsent(_topLevelKey(reference.element), () => [])
          .add(reference);
    }

    final usedNames = {..._collector.usedIdentifiers};
    final renames = <String, String>{};
    final declaredNames = <String>{};
    for (final entry in declarations.entries) {
      final name = entry.value.name!;
      if (declaredNames.add(name) && !externalReferencesByName.containsKey(name)) continue;
      var index = 1;
      var newName = '${name}_$index';
      while (usedNames.contains(newName)) {
        newName = '${name}_${++index}';
      }
      usedNames.add(newName);
      renames[entry.key] = newName;
      print('Renamed the top-level declaration "$name" of ${entry.value.library!.uri} to "$newName" to avoid a name clash.');
    }

    for (final source in sources) {
      for (final declaration in source.result.unit.declarations) {
        for (final (element, token) in _declaredTopLevelElements(declaration)) {
          final newName = renames[_topLevelKey(element)];
          if (newName != null) source.addEdit(token.offset, token.end, newName);
        }
      }
    }
    for (final reference in references) {
      final newName = renames[_topLevelKey(reference.element)];
      if (newName != null) reference.source.addEdit(reference.offset, reference.end, newName);
    }

    // Third-party names resolving to different declarations are accessed with dedicated import prefixes.
    var prefixIndex = 0;
    for (final entry in externalReferencesByName.entries) {
      if (entry.value.length < 2) continue;
      for (final elementReferences in entry.value.values) {
        final reference = elementReferences.first;
        final importUri = _findImportUri(reference.source, reference.element);
        if (importUri == null) {
          print('Warning: unable to disambiguate the "${entry.key}" name in the merged file.');
          continue;
        }
        String prefix;
        do {
          prefix = '_merged_import_${prefixIndex++}';
        } while (usedNames.contains(prefix));
        usedNames.add(prefix);
        imports.add("import '$importUri' as $prefix;");
        for (final elementReference in elementReferences) {
          elementReference.source.addEdit(elementReference.offset, elementReference.offset, '$prefix.');
        }
      }
    }
  }

  /// Returns the URI of an import through which the [element] is referenced by the [source].
  ///
  String? _findImportUri(_MergedSource source, analyzer_element.Element element) {
    final libraryFragment = source.result.libraryElement.firstFragment;
    for (final import in libraryFragment.libraryImports) {
      if (import.prefix != null) continue;
      final importedElement = import.namespace.get2(element.name!);
      if (_topLevelElement(importedElement) == element.baseElement) {
        return import.importedLibrary?.uri.toString();
      }
    }
    return null;
  }

  /// Top-level elements declared by the [declaration], along with their name tokens.
  ///
  static Iterable<(analyzer_element.Element, analyzer_token.Token)> _declaredTopLevelElements(
    analyzer_ast.CompilationUnitMember declaration,
  ) sync* {
    if (declaration is analyzer_ast.TopLevelVariableDeclaration) {
      for (final variable in declaration.variables.variables) {
        final element = _topLevelElement(variable.declaredFragment?.element);
        if (element != null) yield (element, variable.name);
      }
      return;
    }
    final element = _topLevelElement(declaration.declaredFragment?.element);
    if (element == null) return;
    final token = switch (declaration) {
      analyzer_ast.NamedCompilationUnitMember(:final name) => name,
      analyzer_ast.ExtensionDeclaration(:final name) => name,
      _ => null,
    };
    if (token != null) yield (element, token);
  }

  /// Applies the recorded edits to the [source] contents.
  ///
  static String _applyEdits(_MergedSource source) {
    var contents = source.result.content;
    final edits = [...source.edits]..sort((a, b) => b.offset != a.offset ? b.offset.compareTo(a.offset) : b.end.compareTo(a.end));
    var previousOffset = contents.length;
    for (final edit in edits) {
      if (edit.end > previousOffset) {
        throw StateError('Overlapping merge edits in ${source.filePath} at offset ${edit.offset}.');
      }
      contents = contents.replaceRange(edit.offset, edit.end, edit.text);
      previousOffset = edit.offset;
    }
    return contents.trim();
  }

  /// Converts a [dependency] declared by the [package] to a `pubspec.yaml` value.
  ///
  Object? _dependencyToYamlNode(
    SourcePackage package,
    pubspec_parse.Dependency dependency,
  ) {
    return switch (dependency) {
      pubspec_parse.HostedDependency(:final hosted, :final version) =>
        hosted?.url == null
            ? version.toString()
            : {
                'hosted': {
                  if (hosted!.declaredName != null) 'name': hosted.declaredName,
                  'url': hosted.url.toString(),
                },
                'version': version.toString(),
              },
      pubspec_parse.PathDependency(path: final dependencyPath) => {
        'path': _configuration.resolveDependencyPath(
          package: package,
          dependencyPath: dependencyPath,
          preferCopies: false,
        ),
      },
      pubspec_parse.GitDependency(:final url, :final ref, path: final gitPath) => {
        'git': {
          'url': url.toString(),
          if (ref != null) 'ref': ref,
          if (gitPath != null) 'path': gitPath,
        },
      },
      pubspec_parse.SdkDependency(:final sdk, :final version) => {
        'sdk': sdk,
        if (version != pub_semver.VersionConstraint.any) 'version': version.toString(),
      },
    };
  }

  /// Returns the highest lower bound of the [constraints], formatted as a caret constraint.
  ///
  static String? _mergeVersionConstraints(Iterable<pub_semver.VersionConstraint?> constraints) {
    pub_semver.Version? minimum;
    for (final constraint in constraints) {
      if (constraint is pub_semver.VersionRange) {
        final min = constraint.min;
        if (min != null && (minimum == null || min > minimum)) minimum = min;
      }
    }
    return minimum == null ? null : '^$minimum';
  }

  /// Copies an asset (file or directory) declared by the [package] to the output directory.
  ///
  void _copyAsset(SourcePackage package, String assetPath) {
    final sourcePath = path.join(package.sourceDirectory.path, assetPath);
    final destinationPath = path.join(_configuration.outputDirectory.path, assetPath);
    final type = dart_io.FileSystemEntity.typeSync(sourcePath);
    if (type == dart_io.FileSystemEntityType.file) {
      dart_io.File(destinationPath).parent.createSync(recursive: true);
      dart_io.File(sourcePath).copySync(destinationPath);
    } else if (type == dart_io.FileSystemEntityType.directory) {
      for (final entity in dart_io.Directory(sourcePath).listSync(recursive: true)) {
        if (entity is! dart_io.File) continue;
        final target = path.join(destinationPath, path.relative(entity.path, from: sourcePath));
        dart_io.File(target).parent.createSync(recursive: true);
        entity.copySync(target);
      }
    } else {
      print('Warning: asset "$assetPath" of the ${package.name} package was not found.');
    }
  }

  /// Merges the `flutter` sections of the source packages, copying the declared assets and fonts.
  ///
  Map<String, Object?>? _mergeFlutterConfiguration() {
    final merged = <String, Object?>{};
    final assets = <Object?>[];
    final fonts = <Object?>[];
    for (final package in _configuration.packages) {
      final configuration = package.pubspec.flutter;
      if (configuration == null) continue;
      if (configuration['uses-material-design'] == true) merged['uses-material-design'] = true;
      if (configuration['generate'] == true) {
        merged['generate'] = true;
        print('Warning: "flutter: generate: true" (e.g., localizations) is not supported by the merged project.');
      }
      final packageAssets = configuration['assets'];
      if (packageAssets is List) {
        for (final asset in packageAssets) {
          final assetPath = asset is Map ? asset['path'] : asset;
          if (assetPath is String) _copyAsset(package, assetPath);
          if (!assets.any((existing) => existing.toString() == asset.toString())) assets.add(asset);
        }
      }
      final packageFonts = configuration['fonts'];
      if (packageFonts is List) {
        for (final family in packageFonts) {
          fonts.add(family);
          final familyFonts = family is Map ? family['fonts'] : null;
          if (familyFonts is! List) continue;
          for (final font in familyFonts) {
            final asset = font is Map ? font['asset'] : null;
            if (asset is String) _copyAsset(package, asset);
          }
        }
      }
    }
    if (assets.isNotEmpty) merged['assets'] = assets;
    if (fonts.isNotEmpty) merged['fonts'] = fonts;
    return merged.isEmpty ? null : merged;
  }

  /// Generates a new `pubspec.yaml` file from the source package specifications.
  ///
  void _generateMergedPubspecFile() {
    final packages = _configuration.packages;
    final sourcePackageNames = _configuration.sourcePackages.toSet();
    Map<String, Object?> mergeDependencies(Map<String, pubspec_parse.Dependency> Function(pubspec_parse.Pubspec) section) {
      final result = <String, Object?>{};
      for (final package in packages) {
        for (final entry in section(package.pubspec).entries) {
          if (sourcePackageNames.contains(entry.key)) continue;
          result[entry.key] = _dependencyToYamlNode(package, entry.value);
        }
      }
      return result;
    }

    final environment = <String, Object?>{
      'sdk': _mergeVersionConstraints(packages.map((package) => package.pubspec.environment['sdk'])) ?? '^3.0.0',
    };
    final flutterConstraint = _mergeVersionConstraints(packages.map((package) => package.pubspec.environment['flutter']));
    if (flutterConstraint != null) environment['flutter'] = flutterConstraint;
    final dependencies = mergeDependencies((pubspec) => pubspec.dependencies);
    final devDependencies = mergeDependencies((pubspec) => pubspec.devDependencies);
    final dependencyOverrides = mergeDependencies((pubspec) => pubspec.dependencyOverrides);
    final flutter = _mergeFlutterConfiguration();

    final editor = yaml_edit.YamlEditor('');
    editor.update([], {
      'name': 'merged_app',
      'description': 'A new merged application.',
      'version': '1.0.0+1',
      'publish_to': 'none',
      'environment': environment,
      if (dependencies.isNotEmpty) 'dependencies': dependencies,
      if (devDependencies.isNotEmpty) 'dev_dependencies': devDependencies,
      if (dependencyOverrides.isNotEmpty) 'dependency_overrides': dependencyOverrides,
      'flutter': ?flutter,
    });
    _configuration.mergedPubspecFile.writeAsStringSync('${editor.toString().trim()}\n');
  }

  /// Outputs all of the [Configuration.packages] `lib` contents to a single file.
  ///
  /// Returns `false` if the merged output could not be generated as valid Dart code.
  ///
  Future<bool> generateMergedProject() async {
    final collection = analyzer_context.AnalysisContextCollection(
      includedPaths: [for (final package in _configuration.packages) package.copyDirectory.path],
    );
    final sources = await _resolveSources(collection);
    final imports = <String>[];
    final references = _prepareSources(sources, imports);
    _resolveNameClashes(sources, references, imports);
    await collection.dispose();

    final fileBuffer = StringBuffer();
    for (final import in imports) {
      fileBuffer.writeln(import);
    }
    fileBuffer.writeln();
    for (final source in sources) {
      final contents = _applyEdits(source);
      if (contents.isEmpty) continue;
      fileBuffer
        ..writeln(contents)
        ..writeln();
    }

    // Format available output data.
    var success = true;
    var formattedCode = fileBuffer.toString();
    try {
      formattedCode = _configuration.formatter.format(formattedCode);
    } catch (e) {
      success = false;
      print('Error: the merged code could not be formatted, as it is not valid Dart code:\n$e');
    }
    await _configuration.outputMergedFile.writeAsString(formattedCode);

    // Record the merged `pubspec.yaml` file and run package setup.
    _generateMergedPubspecFile();
    try {
      await Configuration.runPubGet(
        directory: _configuration.outputDirectory,
        flutter: _configuration.packages.any((package) => package.usesFlutter),
      );
    } on ConfigurationException catch (e) {
      print('Warning: dependencies of the merged project could not be resolved:\n$e');
    }
    return success;
  }
}

/// Collects the references to top-level declarations, and removes the first-party import prefixes.
///
class _MergeReferenceVisitor extends analyzer_visitor.RecursiveAstVisitor<void> {
  _MergeReferenceVisitor({
    required this.merger,
    required this.source,
    required this.references,
  });

  final ProjectMerger merger;

  final _MergedSource source;

  final List<_TopLevelReference> references;

  @override
  void visitImportDirective(analyzer_ast.ImportDirective node) {}

  @override
  void visitExportDirective(analyzer_ast.ExportDirective node) {}

  @override
  void visitPartDirective(analyzer_ast.PartDirective node) {}

  @override
  void visitPartOfDirective(analyzer_ast.PartOfDirective node) {}

  @override
  void visitLibraryDirective(analyzer_ast.LibraryDirective node) {}

  /// Records a reference to the [element] named by the [token], if it's a top-level declaration.
  ///
  void _record(analyzer_element.Element? element, analyzer_token.Token token, {required bool isPrefixed}) {
    final topLevelElement = ProjectMerger._topLevelElement(element);
    if (topLevelElement == null || token.lexeme != topLevelElement.name) return;
    // References through third-party import prefixes are not ambiguous.
    if (isPrefixed && !merger._isMergedLibrary(topLevelElement.library)) return;
    references.add(
      _TopLevelReference(
        source: source,
        offset: token.offset,
        end: token.end,
        element: topLevelElement,
      ),
    );
  }

  /// Removes the [prefix] of a reference to a merged library, e.g., `helpers.` in `helpers.value`.
  ///
  /// Returns whether the prefix was removed.
  ///
  bool _removePrefix(analyzer_token.Token prefix, analyzer_token.Token period, analyzer_element.Element? element) {
    final library = element?.library;
    if (!merger._isMergedLibrary(library)) return false;
    source.addEdit(prefix.offset, period.end, '');
    return true;
  }

  @override
  void visitSimpleIdentifier(analyzer_ast.SimpleIdentifier node) {
    final element = node.element;
    if (element is analyzer_element.PrefixElement) {
      final parent = node.parent;
      if (parent is analyzer_ast.PrefixedIdentifier && parent.prefix == node) {
        _removePrefix(node.token, parent.period, parent.identifier.element ?? ObjectCollector.assignedElement(parent.identifier));
      } else if (parent is analyzer_ast.MethodInvocation && parent.target == node) {
        if (parent.methodName.name == 'loadLibrary' && element.imports.every((import) => merger._isMergedLibrary(import.importedLibrary))) {
          // Deferred loading of a merged library, which is always loaded.
          source.addEdit(parent.offset, parent.end, 'Future<void>.value()');
        } else {
          _removePrefix(node.token, parent.operator!, parent.methodName.element);
        }
      }
      return;
    }
    var resolved = element ?? ObjectCollector.assignedElement(node);
    if (resolved is analyzer_element.ConstructorElement) {
      resolved = node.name == resolved.enclosingElement.name ? resolved.enclosingElement : null;
    }
    final parent = node.parent;
    final isPrefixed = switch (parent) {
      analyzer_ast.PrefixedIdentifier(:final identifier, :final prefix) =>
        identifier == node && prefix.element is analyzer_element.PrefixElement,
      analyzer_ast.MethodInvocation(:final methodName, :final target) =>
        methodName == node && target is analyzer_ast.SimpleIdentifier && target.element is analyzer_element.PrefixElement,
      _ => false,
    };
    // Members accessed through a target (e.g., `object.member`) can't be top-level declarations.
    if (parent is analyzer_ast.PrefixedIdentifier && parent.identifier == node && !isPrefixed) return;
    if (parent is analyzer_ast.PropertyAccess && parent.propertyName == node) return;
    if (parent is analyzer_ast.MethodInvocation && parent.methodName == node && parent.target != null && !isPrefixed) return;
    _record(resolved, node.token, isPrefixed: isPrefixed);
  }

  @override
  void visitNamedType(analyzer_ast.NamedType node) {
    final importPrefix = node.importPrefix;
    var isPrefixed = importPrefix != null;
    if (importPrefix != null && _removePrefix(importPrefix.name, importPrefix.period, node.element)) {
      isPrefixed = false;
    }
    _record(node.element, node.name, isPrefixed: isPrefixed);
    super.visitNamedType(node);
  }
}
