import 'dart:io' as dart_io;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart' as analyzer_context;
import 'package:args/args.dart' as args;
import 'package:dart_style/dart_style.dart' as dart_style;
import 'package:path/path.dart' as path;
import 'package:obfuscator/src/annotation.dart';
import 'package:pubspec_parse/pubspec_parse.dart' as pubspec_parse;
import 'package:yaml_edit/yaml_edit.dart' as yaml_edit;

/// Error raised for invalid input or environment, reported to the user without a stack trace.
///
class ConfigurationException implements Exception {
  /// Creates an exception described by the user-facing [message].
  ///
  const ConfigurationException(this.message);

  /// User-facing description of the problem.
  ///
  final String message;

  @override
  String toString() => message;
}

/// A Dart package provided for obfuscation with the `--src` argument.
///
class SourcePackage {
  /// Creates a reference to the package placed in [sourceDirectory] and described by [pubspec].
  ///
  SourcePackage({
    required this.sourceDirectory,
    required this.pubspec,
  });

  /// Location of the original package sources, which are never modified.
  ///
  final dart_io.Directory sourceDirectory;

  /// Parsed contents of the original `pubspec.yaml` file.
  ///
  final pubspec_parse.Pubspec pubspec;

  /// Location of the copied (obfuscated) package sources.
  ///
  late dart_io.Directory copyDirectory;

  /// Locations of the packages nested within the [copyDirectory] (e.g., `example`).
  ///
  /// Their declarations are not obfuscated, but their references to the obfuscated declarations are updated.
  ///
  final nestedPackageDirectories = <String>[];

  /// Package identifier, as defined with the `pubspec.yaml` file.
  ///
  String get name => pubspec.name;

  /// Whether the package requires the Flutter SDK for dependency resolution.
  ///
  bool get usesFlutter => usesFlutterSdk(pubspec);

  /// Whether the package described by the [pubspec] requires the Flutter SDK for dependency resolution.
  ///
  static bool usesFlutterSdk(pubspec_parse.Pubspec pubspec) => [
    ...pubspec.dependencies.values,
    ...pubspec.devDependencies.values,
    ...pubspec.dependencyOverrides.values,
  ].any((dependency) => dependency is pubspec_parse.SdkDependency && dependency.sdk == 'flutter');
}

/// Object defining the basic input options for the obfuscation service.
///
class Configuration {
  /// Creates an instance of the obfuscation run configuration using the command line [arguments].
  ///
  Configuration.fromArguments({
    required List<String> arguments,
  }) : _arguments = arguments;

  /// Command line interface arguments.
  ///
  final List<String> _arguments;

  /// Name of the file marking a directory as created by this tool.
  ///
  /// Only directories containing this file (or empty ones) are ever deleted by the tool.
  ///
  static const outputMarkerFileName = '.obfuscator_output';

  /// Entries of a package directory (a directory containing a `pubspec.yaml` file) which are not copied.
  ///
  static const _skippedPackageEntries = {'build'};

  /// Entries which are not copied to the output, regardless of their location.
  ///
  static const _skippedEntries = {'.git', '.dart_tool'};

  /// Validate and retrieve the CLI arguments.
  ///
  ({String sourceDirectoriesArg, String outputDirectoryArg, String? publicApiIdentifiersArg, int? seed}) _processArguments(
    List<String> arguments,
  ) {
    // Define argument identifiers.
    const sourceDirectoriesId = 'sourceDirectories';
    const outputDirectoryId = 'outputDirectory';
    const publicApiIdentifierId = 'publicApiIdentifiers';
    const seedId = 'seed';

    // Instantiate and setup argument parser.
    final argumentParser = args.ArgParser(
      allowTrailingOptions: true,
    );

    for (final argument in <({String id, String alias, String help, bool mandatory})>{
      (
        id: sourceDirectoriesId,
        alias: 'src',
        help: 'Comma-separated package directories (each containing a pubspec.yaml file) to be obfuscated.',
        mandatory: true,
      ),
      (
        id: outputDirectoryId,
        alias: 'out',
        help:
            'The output directory of the obfuscation command. '
            'It must be empty, missing, or created by a previous run of this tool.',
        mandatory: true,
      ),
      (
        id: publicApiIdentifierId,
        alias: 'pub',
        help:
            'Comma-separated annotation or declaration identifiers for the values marked as not to be obfuscated. '
            'The "NoObfuscation" and "publicApi" identifiers are always included.',
        mandatory: false,
      ),
      (
        id: seedId,
        alias: 'seed',
        help: 'Optional integer seed for generating deterministic obfuscated identifiers.',
        mandatory: false,
      ),
    }) {
      argumentParser.addOption(
        argument.id,
        aliases: [argument.alias],
        help: argument.help,
        mandatory: argument.mandatory,
      );
    }
    argumentParser.addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    );

    void printUsage() {
      print('Dart Obfuscator CLI');
      print('');
      print('Usage: obfuscator --src=<directories> --out=<directory> [--pub=<identifiers>] [--seed=<integer>]');
      print('');
      print(argumentParser.usage);
    }

    // If no arguments are specified or the `--help` flag is provided, print help and exit.
    if (arguments.isEmpty || arguments.contains('--help') || arguments.contains('-h')) {
      printUsage();
      dart_io.exit(0);
    }

    try {
      final cliArguments = argumentParser.parse(arguments);
      final seedArg = cliArguments.option(seedId);
      final seed = seedArg == null ? null : int.tryParse(seedArg);
      if (seedArg != null && seed == null) {
        throw ConfigurationException('The --seed value must be an integer, got "$seedArg".');
      }
      return (
        sourceDirectoriesArg: cliArguments.option(sourceDirectoriesId)!,
        outputDirectoryArg: cliArguments.option(outputDirectoryId)!,
        publicApiIdentifiersArg: cliArguments.option(publicApiIdentifierId),
        seed: seed,
      );
    } on args.ArgParserException catch (e) {
      printUsage();
      throw ConfigurationException(e.message);
    } on ArgumentError catch (e) {
      printUsage();
      throw ConfigurationException('${e.message}');
    }
  }

  /// Splits a comma-separated argument value, ignoring whitespace and empty entries.
  ///
  static List<String> _splitList(String value) {
    return [
      for (final entry in value.split(','))
        if (entry.trim().isNotEmpty) entry.trim(),
    ];
  }

  /// Returns the absolute, normalized [location] with any symbolic links resolved.
  ///
  /// Links are resolved for the longest existing part of the path, so that non-existing
  /// locations can be compared with the existing ones.
  ///
  static String _resolvePath(String location) {
    final canonical = path.canonicalize(location);
    var current = canonical;
    final missingSegments = <String>[];
    while (true) {
      if (dart_io.FileSystemEntity.typeSync(current) != dart_io.FileSystemEntityType.notFound) {
        final resolved = dart_io.Directory(current).resolveSymbolicLinksSync();
        return path.joinAll([resolved, ...missingSegments.reversed]);
      }
      final parent = path.dirname(current);
      if (parent == current) return canonical;
      missingSegments.add(path.basename(current));
      current = parent;
    }
  }

  /// Packages provided for obfuscation.
  ///
  final packages = <SourcePackage>[];

  /// Directories in which source files to be obfuscated are placed.
  ///
  List<dart_io.Directory> get sourceDirectories => [for (final package in packages) package.sourceDirectory];

  /// The identifiers of the packages to be obfuscated, derived from the `pubspec.yaml` files.
  ///
  List<String> get sourcePackages => [for (final package in packages) package.name];

  /// Validate the source directories and parse their `pubspec.yaml` files.
  ///
  void _initialiseSourcePackages({
    required String sourceDirectoriesArg,
  }) {
    final sourceDirectoriesPaths = _splitList(sourceDirectoriesArg);
    if (sourceDirectoriesPaths.isEmpty) {
      throw const ConfigurationException('No source directories were provided with the --src argument.');
    }
    for (final sourceDirectoryPath in sourceDirectoriesPaths) {
      final directory = dart_io.Directory(_resolvePath(sourceDirectoryPath));
      if (!directory.existsSync()) {
        throw ConfigurationException('Source directory "$sourceDirectoryPath" not found.');
      }
      final pubspecFile = dart_io.File(path.join(directory.path, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) {
        throw ConfigurationException('Source directory "$sourceDirectoryPath" does not contain a pubspec.yaml file.');
      }
      final pubspec_parse.Pubspec pubspec;
      try {
        pubspec = pubspec_parse.Pubspec.parse(
          pubspecFile.readAsStringSync(),
          sourceUrl: pubspecFile.uri,
        );
      } catch (e) {
        throw ConfigurationException('Unable to parse ${pubspecFile.path}:\n$e');
      }
      if (packages.any((package) => package.sourceDirectory.path == directory.path)) {
        throw ConfigurationException('Source directory "$sourceDirectoryPath" is provided more than once.');
      }
      if (packages.any((package) => package.name == pubspec.name)) {
        throw ConfigurationException('Multiple source directories define the same package name "${pubspec.name}".');
      }
      packages.add(
        SourcePackage(
          sourceDirectory: directory,
          pubspec: pubspec,
        ),
      );
    }
    for (final package in packages) {
      for (final other in packages) {
        if (package != other && path.isWithin(other.sourceDirectory.path, package.sourceDirectory.path)) {
          throw ConfigurationException(
            'Source directory "${package.sourceDirectory.path}" is placed within "${other.sourceDirectory.path}".',
          );
        }
      }
    }
  }

  /// The output directory of the obfuscation command (e.g., `"./build/"`).
  ///
  late dart_io.Directory outputDirectory;

  /// Validate, create and reset any current output directory state.
  ///
  void _initialiseOutputDirectory({
    required String outputDirectoryArg,
  }) {
    outputDirectory = dart_io.Directory(_resolvePath(outputDirectoryArg));
    for (final package in packages) {
      final sourcePath = package.sourceDirectory.path;
      if (path.equals(sourcePath, outputDirectory.path) ||
          path.isWithin(sourcePath, outputDirectory.path) ||
          path.isWithin(outputDirectory.path, sourcePath)) {
        throw ConfigurationException(
          'The output directory "${outputDirectory.path}" must not be the same as, placed within, '
          'or contain the source directory "$sourcePath".',
        );
      }
    }
    final outputType = dart_io.FileSystemEntity.typeSync(outputDirectory.path, followLinks: false);
    if (outputType == dart_io.FileSystemEntityType.directory) {
      final isEmpty = outputDirectory.listSync().isEmpty;
      final isPreviousOutput = dart_io.File(path.join(outputDirectory.path, outputMarkerFileName)).existsSync();
      if (!isEmpty && !isPreviousOutput) {
        throw ConfigurationException(
          'The output directory "${outputDirectory.path}" is not empty and was not created by this tool. '
          'Remove it manually or provide a different location.',
        );
      }
      outputDirectory.deleteSync(recursive: true);
    } else if (outputType != dart_io.FileSystemEntityType.notFound) {
      throw ConfigurationException('The output location "${outputDirectory.path}" is not a directory.');
    }
    outputDirectory.createSync(recursive: true);
    dart_io.File(path.join(outputDirectory.path, outputMarkerFileName)).writeAsStringSync(
      'Created by the Dart Obfuscator. The contents of this directory are deleted on each run.\n',
    );
  }

  /// Directory where the source code files are copied to.
  ///
  late dart_io.Directory sourceDirectoriesCopy;

  /// Recursively copies the [source] directory contents to the [destination] directory.
  ///
  /// Symbolic links are copied as links rather than followed. Relative links pointing outside of the
  /// [sourceRoot] are converted to absolute ones, so that they keep pointing to the same location.
  ///
  void _copyDirectory({
    required dart_io.Directory source,
    required dart_io.Directory destination,
    required String sourceRoot,
  }) {
    destination.createSync(recursive: true);
    final isPackageDirectory = dart_io.File(path.join(source.path, 'pubspec.yaml')).existsSync();
    for (final entity in source.listSync(followLinks: false)) {
      final name = path.basename(entity.path);
      if (_skippedEntries.contains(name) || isPackageDirectory && _skippedPackageEntries.contains(name)) continue;
      final newPath = path.join(destination.path, name);
      if (entity is dart_io.Link) {
        var target = entity.targetSync();
        if (path.isRelative(target)) {
          final absoluteTarget = path.normalize(path.join(path.dirname(entity.path), target));
          if (!path.equals(sourceRoot, absoluteTarget) && !path.isWithin(sourceRoot, absoluteTarget)) {
            target = absoluteTarget;
          }
        }
        dart_io.Link(newPath).createSync(target);
      } else if (entity is dart_io.File) {
        entity.copySync(newPath);
      } else if (entity is dart_io.Directory) {
        _copyDirectory(
          source: entity,
          destination: dart_io.Directory(newPath),
          sourceRoot: sourceRoot,
        );
      }
    }
  }

  /// Adjusts a copied `pubspec.yaml` file so that it resolves from the [copyDirectory] location.
  ///
  /// The `resolution: workspace` entry is removed (unless [keepWorkspaceResolution] is `true`, for the members
  /// of a workspace which is copied as well), and relative path dependencies, declared relative to
  /// the [originalDirectory], are converted to absolute ones, or to the copy locations for the packages
  /// which are obfuscated as well.
  ///
  void _updateCopiedPubspec({
    required String copyDirectory,
    required String originalDirectory,
    required bool keepWorkspaceResolution,
  }) {
    final pubspecFile = dart_io.File(path.join(copyDirectory, 'pubspec.yaml'));
    final editor = yaml_edit.YamlEditor(pubspecFile.readAsStringSync());
    final contents = editor.parseAt([]).value;
    if (contents is! Map) return;
    if (contents['resolution'] == 'workspace' && !keepWorkspaceResolution) {
      editor.remove(['resolution']);
    }
    for (final section in const ['dependencies', 'dev_dependencies', 'dependency_overrides']) {
      final dependencies = contents[section];
      if (dependencies is! Map) continue;
      for (final entry in dependencies.entries) {
        final dependency = entry.value;
        if (dependency is! Map || dependency['path'] is! String) continue;
        editor.update(
          [section, entry.key, 'path'],
          resolveDependencyPath(
            baseDirectory: originalDirectory,
            dependencyPath: dependency['path'] as String,
            preferCopies: true,
          ),
        );
      }
    }
    pubspecFile.writeAsStringSync(editor.toString());
  }

  /// Returns the absolute location of a path dependency declared as [dependencyPath] by the package
  /// placed in the [baseDirectory].
  ///
  /// If the dependency is one of the obfuscated packages and [preferCopies] is `true`,
  /// the location of its copy is returned instead.
  ///
  String resolveDependencyPath({
    required String baseDirectory,
    required String dependencyPath,
    required bool preferCopies,
  }) {
    final absolutePath = _resolvePath(path.join(baseDirectory, dependencyPath));
    if (preferCopies) {
      // Locations within the obfuscated packages (e.g., their nested packages) are mapped to the copies.
      for (final package in packages) {
        final sourcePath = package.sourceDirectory.path;
        if (path.equals(sourcePath, absolutePath) || path.isWithin(sourcePath, absolutePath)) {
          return path.join(package.copyDirectory.path, path.relative(absolutePath, from: sourcePath));
        }
      }
    }
    return absolutePath;
  }

  /// Runs `pub get` in the [directory], using the Flutter tool if [flutter] is `true`.
  ///
  /// Throws a [ConfigurationException] if the dependencies can't be resolved.
  ///
  static Future<void> runPubGet({
    required dart_io.Directory directory,
    required bool flutter,
  }) async {
    final executable = flutter ? 'flutter' : 'dart';
    final errors = <String>[];
    for (final extraArguments in const [
      <String>[],
      <String>['--offline'],
    ]) {
      final dart_io.ProcessResult result;
      try {
        result = await dart_io.Process.run(
          executable,
          // Nested packages (e.g., `example`) are resolved separately, as their failures are not fatal.
          ['pub', 'get', '--no-example', ...extraArguments],
          workingDirectory: directory.path,
          runInShell: dart_io.Platform.isWindows,
        );
      } on dart_io.ProcessException catch (e) {
        throw ConfigurationException('Unable to run "$executable pub get" in ${directory.path}: ${e.message}');
      }
      if (result.exitCode == 0) return;
      errors.add('${result.stdout}\n${result.stderr}'.trim());
    }
    throw ConfigurationException(
      '"$executable pub get" failed in ${directory.path}:\n${errors.first}\n\n'
      'Retrying with "--offline" failed as well:\n${errors.last}',
    );
  }

  /// Define locations and copy source code directories to the newly-created `copy` folder.
  ///
  Future<void> _initialiseSourceDirectoriesCopy() async {
    sourceDirectoriesCopy = dart_io.Directory(
      path.join(outputDirectory.path, 'copy'),
    )..createSync(recursive: true);
    final usedNames = <String>{};
    for (final package in packages) {
      var copyName = path.basename(package.sourceDirectory.path);
      if (!usedNames.add(copyName)) {
        copyName = package.name;
        for (var index = 2; !usedNames.add(copyName); index++) {
          copyName = '${package.name}_$index';
        }
      }
      package.copyDirectory = dart_io.Directory(path.join(sourceDirectoriesCopy.path, copyName));
    }
    for (final package in packages) {
      _copyDirectory(
        source: package.sourceDirectory,
        destination: package.copyDirectory,
        sourceRoot: package.sourceDirectory.path,
      );
      _updateCopiedPubspec(
        copyDirectory: package.copyDirectory.path,
        originalDirectory: package.sourceDirectory.path,
        keepWorkspaceResolution: false,
      );
      _findNestedPackages(package, package.copyDirectory);
      for (final nestedDirectory in package.nestedPackageDirectories) {
        _updateCopiedPubspec(
          copyDirectory: nestedDirectory,
          originalDirectory: path.join(
            package.sourceDirectory.path,
            path.relative(nestedDirectory, from: package.copyDirectory.path),
          ),
          keepWorkspaceResolution: _isWithinCopiedWorkspace(package, nestedDirectory),
        );
      }
    }
    for (final package in packages) {
      await runPubGet(
        directory: package.copyDirectory,
        flutter: package.usesFlutter,
      );
    }
    for (final package in packages) {
      for (final nestedDirectory in package.nestedPackageDirectories) {
        try {
          final nestedPubspec = pubspec_parse.Pubspec.parse(
            dart_io.File(path.join(nestedDirectory, 'pubspec.yaml')).readAsStringSync(),
          );
          await runPubGet(
            directory: dart_io.Directory(nestedDirectory),
            flutter: SourcePackage.usesFlutterSdk(nestedPubspec),
          );
        } catch (e) {
          print(
            'Warning: references of the nested package $nestedDirectory may not be updated, as its dependencies could not be resolved:\n$e',
          );
        }
      }
    }
  }

  /// Whether a package nested in the [nestedDirectory] of the copied [package] is placed within
  /// a copied workspace root (a package with the `workspace` entry), which it may be a member of.
  ///
  static bool _isWithinCopiedWorkspace(SourcePackage package, String nestedDirectory) {
    for (
      var directory = path.dirname(nestedDirectory);
      path.equals(directory, package.copyDirectory.path) || path.isWithin(package.copyDirectory.path, directory);
      directory = path.dirname(directory)
    ) {
      final pubspecFile = dart_io.File(path.join(directory, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) continue;
      final contents = yaml_edit.YamlEditor(pubspecFile.readAsStringSync()).parseAt([]).value;
      if (contents is Map && contents.containsKey('workspace')) return true;
    }
    return false;
  }

  /// Records the packages nested within the [directory] of the copied [package].
  ///
  void _findNestedPackages(SourcePackage package, dart_io.Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! dart_io.Directory || path.basename(entity.path).startsWith('.')) continue;
      if (dart_io.File(path.join(entity.path, 'pubspec.yaml')).existsSync()) {
        package.nestedPackageDirectories.add(entity.path);
      }
      _findNestedPackages(package, entity);
    }
  }

  /// File definition for object mappings.
  ///
  late dart_io.File outputMappingsFile;

  /// File definition of the merged code file.
  ///
  late dart_io.File outputMergedFile;

  /// File definition for the merged `pubspec.yaml` file, derived from [packages].
  ///
  late dart_io.File mergedPubspecFile;

  /// Allocate output file resources.
  ///
  void _initialiseOutputFiles() {
    outputMappingsFile = dart_io.File(path.join(outputDirectory.path, 'mappings.json'))..createSync(recursive: true);
    outputMergedFile = dart_io.File(path.join(outputDirectory.path, 'lib', 'merged.dart'))..createSync(recursive: true);
    mergedPubspecFile = dart_io.File(path.join(outputDirectory.path, 'pubspec.yaml'));
  }

  /// Optional annotation or object identifiers for the values marked as not to be obfuscated.
  ///
  /// Defaults to the [NoObfuscation] annotation identifier provided by the library.
  ///
  final publicApiIdentifiers = <String>[
    (NoObfuscation).toString(),
    'publicApi',
  ];

  /// Set and validate the public API identifier collection.
  ///
  void _initialisePublicApiIdentifiers({
    required String? publicApiIdentifiersArg,
  }) {
    if (publicApiIdentifiersArg != null) {
      publicApiIdentifiers.addAll(_splitList(publicApiIdentifiersArg));
    }
  }

  /// Optional seed used for generating deterministic identifiers.
  ///
  int? seed;

  /// A collection of analysis contexts.
  ///
  late analyzer_context.AnalysisContextCollection analysisContextCollection;

  /// Assign the analysis context collection values.
  ///
  void _initialiseAnalysisContextCollections() {
    analysisContextCollection = analyzer_context.AnalysisContextCollection(
      includedPaths: [for (final package in packages) package.copyDirectory.path],
    );
  }

  /// Dart code formatter.
  ///
  final formatter = dart_style.DartFormatter(
    lineEnding: '\n',
    trailingCommas: dart_style.TrailingCommas.preserve,
    languageVersion: dart_style.DartFormatter.latestLanguageVersion,
  );

  /// Instantiate required class resources.
  ///
  /// All of the inputs are validated before any file system changes are made.
  ///
  Future<void> init() async {
    final args = _processArguments(_arguments);
    seed = args.seed;
    _initialisePublicApiIdentifiers(
      publicApiIdentifiersArg: args.publicApiIdentifiersArg,
    );
    _initialiseSourcePackages(
      sourceDirectoriesArg: args.sourceDirectoriesArg,
    );
    _initialiseOutputDirectory(
      outputDirectoryArg: args.outputDirectoryArg,
    );
    await _initialiseSourceDirectoriesCopy();
    _initialiseOutputFiles();
    _initialiseAnalysisContextCollections();
  }
}
