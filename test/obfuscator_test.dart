@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:obfuscator/src/config.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Location of the fixture packages.
final _fixtures = path.absolute('test', 'fixtures');

late Directory _temp;

/// Version of the Dart SDK running the tests.
final _sdkVersion = Version.parse(Platform.version.split(' ').first);

late String _cli;

Future<ProcessResult> _run(String executable, List<String> arguments, {String? workingDirectory}) {
  return Process.run(executable, arguments, workingDirectory: workingDirectory, runInShell: Platform.isWindows);
}

/// Runs the obfuscator CLI with the given [arguments].
Future<ProcessResult> _obfuscate(List<String> arguments) => _run(Platform.resolvedExecutable, [_cli, ...arguments]);

/// Copies the [fixture] directory to a fresh temporary location and resolves its dependencies.
Future<String> _prepareFixture(String fixture, {String? name}) async {
  final destination = path.join(_temp.path, 'src', name ?? fixture);
  _copy(Directory(path.join(_fixtures, fixture)), Directory(destination));
  for (final pubspec in Directory(destination).listSync(recursive: true).where((e) => path.basename(e.path) == 'pubspec.yaml')) {
    final result = await _run('dart', ['pub', 'get', '--offline'], workingDirectory: path.dirname(pubspec.path));
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }
  return destination;
}

void _copy(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = path.basename(entity.path);
    if (name == '.dart_tool' || name == 'pubspec.lock') continue;
    final target = path.join(destination.path, name);
    if (entity is Directory) {
      _copy(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Error and warning codes reported by the analyzer for the [target], as a sorted list.
Future<List<String>> _diagnostics(String workingDirectory, [String target = '.']) async {
  final result = await _run('dart', ['analyze', '--format=machine', target], workingDirectory: workingDirectory);
  return [
    for (final line in '${result.stdout}\n${result.stderr}'.split('\n'))
      if (line.startsWith('ERROR|') || line.startsWith('WARNING|')) line.split('|').take(3).join('|'),
  ]..sort();
}

/// Full error descriptions reported by the analyzer for the [target].
Future<String> _errors(String workingDirectory, [String target = '.']) async {
  final result = await _run('dart', ['analyze', '--format=machine', target], workingDirectory: workingDirectory);
  return '${result.stdout}\n${result.stderr}'.split('\n').where((line) => line.startsWith('ERROR|')).join('\n');
}

Future<String> _runDart(String workingDirectory, String file) async {
  final result = await _run('dart', ['run', file], workingDirectory: workingDirectory);
  expect(result.exitCode, 0, reason: 'dart run $file in $workingDirectory:\n${result.stdout}${result.stderr}');
  return result.stdout as String;
}

/// Writes the [files] (relative paths mapped to contents) to the [root] directory, and resolves the dependencies
/// of its packages, listed with [packages] (relative paths).
Future<void> _writePackages(String root, Map<String, String> files, List<String> packages) async {
  for (final entry in files.entries) {
    File(path.join(root, entry.key))
      ..createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  for (final package in packages) {
    final result = await _run('dart', ['pub', 'get', '--offline'], workingDirectory: path.join(root, package));
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }
}

/// Contents of all Dart files in the [directory], concatenated.
String _sources(String directory) {
  return [
    for (final file in Directory(directory).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !file.path.contains('.dart_tool')) file.readAsStringSync(),
  ].join('\n');
}

Matcher _containsWord(String word) => matches(RegExp('\\b${RegExp.escape(word)}\\b'));

/// Verifies the obfuscated copy and the merged output of a package against the original one.
Future<void> _verifyOutput({
  required String source,
  required String copy,
  required String output,
}) async {
  expect(await _diagnostics(copy), await _diagnostics(source), reason: await _errors(copy));
  expect(await _errors(output, 'lib/merged.dart'), isEmpty);
  final expected = await _runDart(source, 'lib/main.dart');
  expect(await _runDart(copy, 'lib/main.dart'), expected);
  expect(await _runDart(output, 'lib/merged.dart'), expected);
}

void main() {
  setUpAll(() async {
    _temp = Directory.systemTemp.createTempSync('obfuscator_test_');
    _cli = path.join(_temp.path, 'obfuscator.dill');
    final result = await _run('dart', ['compile', 'kernel', 'bin/obfuscator.dart', '-o', _cli]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  tearDownAll(() => _temp.deleteSync(recursive: true));

  group('core fixture', () {
    late String source, output, copy, copied;
    late ProcessResult result;

    setUpAll(() async {
      source = await _prepareFixture('core');
      output = path.join(_temp.path, 'out_core');
      result = await _obfuscate(['--src=$source', '--out=$output', '--pub=Keep,keptField,', '--seed=1']);
      copy = path.join(output, 'copy', 'core');
      copied = _sources(path.join(copy, 'lib'));
    });

    test('runs successfully', () {
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });

    test('keeps the program valid and its behaviour unchanged', () async {
      await _verifyOutput(source: source, copy: copy, output: output);
    });

    test('updates references outside of the lib directory', () async {
      expect(await _errors(copy, 'test'), isEmpty);
      expect(_sources(path.join(copy, 'test')), isNot(_containsWord('Circle')));
    });

    test('renames classes and fields', () {
      for (final name in ['Circle', 'Square', 'Counter', 'Point', 'Tagged', 'tagValue', 'otherField', 'Unused', 'unusedField', 'total']) {
        expect(copied, isNot(_containsWord(name)), reason: name);
      }
      // Fields overriding each other without the annotation share the new name.
      expect(copied, isNot(_containsWord('label')));
      expect(copied, isNot(_containsWord('hits')));
    });

    test('renames private classes with the same name in each library', () {
      expect(copied, isNot(_containsWord('_Body')));
    });

    test('keeps fields overriding or overridden by explicit accessors and third-party members', () {
      for (final name in ['area', 'value', 'stackTrace', 'hashCode', 'name', '_low']) {
        expect(copied, _containsWord(name), reason: name);
      }
    });

    test('keeps the excluded declarations along with their fields', () {
      for (final name in ['Api', 'message', 'Keep', 'keepMe', 'keptField', 'User']) {
        expect(copied, _containsWord(name), reason: name);
      }
    });

    test('generates deterministic names for a given seed', () async {
      final secondOutput = path.join(_temp.path, 'out_core_2');
      final second = await _obfuscate(['--src=$source', '--out=$secondOutput', '--pub=Keep,keptField,', '--seed=1']);
      expect(second.exitCode, 0);
      expect(_sources(path.join(secondOutput, 'copy', 'core', 'lib')), copied);
    });
  });

  group('merge fixture', () {
    late String source, output, copy, merged;
    late ProcessResult result;

    setUpAll(() async {
      // The path dependencies are resolved relative to the original location.
      _copy(Directory(path.join(_fixtures, 'deps')), Directory(path.join(_temp.path, 'src', 'deps')));
      source = await _prepareFixture('merge_app');
      output = path.join(_temp.path, 'out_merge');
      result = await _obfuscate(['--src=$source', '--out=$output', '--seed=2']);
      copy = path.join(output, 'copy', 'merge_app');
      merged = File(path.join(output, 'lib', 'merged.dart')).readAsStringSync();
    });

    test('runs successfully', () {
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });

    test('keeps the program valid and its behaviour unchanged', () async {
      await _verifyOutput(source: source, copy: copy, output: output);
    });

    test('updates generated files excluded from analysis, and other package directories', () async {
      for (final file in ['lib/gen.g.dart', 'lib/route.gr.dart']) {
        expect(File(path.join(copy, file)).readAsStringSync(), isNot(_containsWord('Model')), reason: file);
      }
      expect(await _errors(copy, 'bin'), isEmpty);
      expect(await _errors(copy, 'test'), isEmpty);
      expect(File(path.join(copy, 'lib/gen.g.dart')).readAsStringSync(), isNot(_containsWord('title')));
    });

    test('keeps the code following an import with a trailing comment', () {
      expect(merged, contains('aReport'));
      expect(merged, isNot(contains('// for max')));
    });

    test('removes all of the directives and first-party prefixes', () {
      expect(merged, isNot(contains('library ')));
      expect(merged, isNot(contains('src/helpers.dart')));
      expect(merged, isNot(contains('part ')));
      expect(merged, isNot(matches(RegExp(r'\bh\.'))));
    });

    test('generates a valid pubspec.yaml file', () {
      final pubspec = File(path.join(output, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('sdk: ">=3.10.0 <4.0.0"'));
      // A single merged package keeps its name, for the references to its own assets.
      expect(pubspec, contains('name: merge_app'));
      expect(pubspec, contains('version: 2.3.4'));
      // Development dependencies may depend on the merged package itself, and are not needed without tests.
      expect(pubspec, isNot(contains('dev_dependencies')));
      expect(pubspec, isNot(contains('flutter:\n    sdk: flutter')));
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains(path.join(_temp.path, 'src', 'deps', 'localdep')));
      expect(pubspec, contains('path: assets/dir/'));
      expect(File(path.join(output, 'assets', 'data.txt')).existsSync(), isTrue);
      expect(File(path.join(output, 'assets', 'dir', 'nested.txt')).existsSync(), isTrue);
    });

    test('imports the third-party libraries re-exported by merged libraries', () {
      expect(merged, contains("import 'dart:collection' show Queue, SplayTreeMap, HashSet;"));
      expect(merged, contains("import 'dart:collection' as ui show Queue, SplayTreeMap, HashSet;"));
    });

    test('renames top-level declarations clashing with import prefixes', () {
      expect(merged, contains('math_1'));
    });

    test('renames import prefixes shared by merged files for different libraries', () {
      expect(merged, contains('as dep_1;'));
      expect(merged, contains('as lazy_dep_1;'));
    });

    test('keeps the third-party exports of public libraries', () async {
      expect(merged, contains("export 'dart:collection' show Queue, SplayTreeMap, HashSet;"));
      // The first-party declaration clashing with an exported name is renamed.
      expect(merged, contains('HashSet_1()'));
      final consumer = Directory(path.join(_temp.path, 'consumer', 'lib'))..createSync(recursive: true);
      File(path.join(consumer.parent.path, 'pubspec.yaml')).writeAsStringSync(
        'name: consumer\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  merge_app:\n    path: $output\n',
      );
      File(path.join(consumer.path, 'main.dart')).writeAsStringSync(
        "import 'package:merge_app/merged.dart';\n\n"
        "void main() => print('\${(HashSet<int>()..add(1)).length + Queue<int>().length} \${LinkedHashSet<int>().length} \${HashMap()}');\n",
      );
      final pubGet = await _run('dart', ['pub', 'get', '--offline'], workingDirectory: consumer.parent.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}${pubGet.stderr}');
      expect(await _errors(consumer.parent.path), isEmpty);
      // `HashMap` is the own declaration of a public library, which shadows the re-exported one.
      expect(await _runDart(consumer.parent.path, 'lib/main.dart'), '1 0 own\n');
    });

    test('updates references of nested packages', () async {
      final example = path.join(copy, 'example');
      expect(await _errors(example), isEmpty);
      expect(await _runDart(example, 'lib/main.dart'), await _runDart(path.join(source, 'example'), 'lib/main.dart'));
      expect(File(path.join(example, 'lib', 'main.dart')).readAsStringSync(), isNot(_containsWord('Model')));
    });
  });

  group('merge edge cases fixture', () {
    test('keeps the program valid and its behaviour unchanged', () async {
      _copy(Directory(path.join(_fixtures, 'deps')), Directory(path.join(_temp.path, 'src', 'deps')));
      final source = await _prepareFixture('merge_edge');
      final output = path.join(_temp.path, 'out_merge_edge');
      final result = await _obfuscate(['--src=$source', '--out=$output', '--seed=4']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      await _verifyOutput(source: source, copy: path.join(output, 'copy', 'merge_edge'), output: output);
      // Invalid Dart files (e.g., templates) are neither obfuscated nor merged.
      final template = path.join('lib', 'templates', 'widget.dart');
      expect(
        File(path.join(output, 'copy', 'merge_edge', template)).readAsStringSync(),
        File(path.join(source, template)).readAsStringSync(),
      );
      expect(File(path.join(output, 'lib', 'merged.dart')).readAsStringSync(), isNot(contains('{{name}}')));
      expect(File(path.join(output, 'pubspec.yaml')).readAsStringSync(), contains('devdep'));
    });
  });

  group('multiple packages', () {
    test('are obfuscated consistently, including packages with the same directory name', () async {
      final root = await _prepareFixture('multi');
      final one = path.join(root, 'one', 'shared');
      final two = path.join(root, 'two', 'shared');
      final output = path.join(_temp.path, 'out_multi');
      final result = await _obfuscate(['--src=$one,$two', '--out=$output', '--seed=3']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final copyOne = path.join(output, 'copy', 'shared');
      final copyTwo = path.join(output, 'copy', 'shared_two');
      expect(File(path.join(copyOne, 'pubspec.yaml')).readAsStringSync(), contains('name: shared_one'));
      expect(File(path.join(copyTwo, 'pubspec.yaml')).readAsStringSync(), contains(copyOne));
      expect(_sources(path.join(copyOne, 'lib')), isNot(_containsWord('Entity')));
      expect(_sources(path.join(copyOne, 'lib')), isNot(_containsWord('id')));
      await _verifyOutput(source: two, copy: copyTwo, output: output);
      expect(File(path.join(output, 'pubspec.yaml')).readAsStringSync(), isNot(contains('shared_one')));
      // Both packages export the same declarations, which isn't a conflict.
      expect('${result.stdout}', isNot(contains('exported by multiple libraries')));
      expect(File(path.join(output, 'lib', 'merged.dart')).readAsStringSync(), contains("export 'dart:collection' show Queue;"));
    });
  });

  group('command line interface', () {
    late String source;

    setUpAll(() async {
      source = await _prepareFixture('multi', name: 'cli');
      source = path.join(source, 'one', 'shared');
    });

    Future<void> expectFailure(List<String> arguments, String message) async {
      final result = await _obfuscate(arguments);
      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', contains(message));
      expect('${result.stdout}${result.stderr}', isNot(contains('Unhandled exception')));
      expect(File(path.join(source, 'lib', 'shared_one.dart')).existsSync(), isTrue);
    }

    test('refuses an output directory equal to the source directory', () async {
      await expectFailure(['--src=$source', '--out=$source'], 'must not be the same as');
    });

    test('refuses an output directory within the source directory', () async {
      await expectFailure(['--src=$source', '--out=${path.join(source, 'out')}'], 'must not be the same as');
      expect(Directory(path.join(source, 'out')).existsSync(), isFalse);
    });

    test('refuses an output directory containing the source directory', () async {
      await expectFailure(['--src=$source', '--out=${path.dirname(source)}'], 'must not be the same as');
    });

    test('keeps the output directory if the source directory is missing', () async {
      final output = Directory(path.join(_temp.path, 'out_missing'))..createSync();
      final marker = File(path.join(output.path, Configuration.outputMarkerFileName))..writeAsStringSync('');
      await expectFailure(['--src=${path.join(_temp.path, 'missing')}', '--out=${output.path}'], 'not found');
      expect(marker.existsSync(), isTrue);
    });

    test('refuses to delete a non-empty directory not created by the tool', () async {
      final output = Directory(path.join(_temp.path, 'out_foreign'))..createSync();
      final file = File(path.join(output.path, 'important.txt'))..writeAsStringSync('keep');
      await expectFailure(['--src=$source', '--out=${output.path}'], 'not created by this tool');
      expect(file.existsSync(), isTrue);
    });

    test('reuses an output directory created by the tool', () async {
      final output = path.join(_temp.path, 'out_reuse');
      for (var run = 0; run < 2; run++) {
        final result = await _obfuscate(['--src=$source', '--out=$output']);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      }
    });

    test('copies symbolic links without following them, and skips generated directories', () async {
      if (Platform.isWindows) return;
      final package = await _prepareFixture('multi', name: 'links');
      final root = path.join(package, 'one', 'shared');
      Directory(path.join(root, '.git')).createSync();
      File(path.join(root, 'build', 'output.txt')).createSync(recursive: true);
      Link(path.join(root, 'loop')).createSync('.');
      File(path.join(root, 'example', 'pubspec.yaml')).createSync(recursive: true);
      File(path.join(root, 'example', 'build', 'output.dart')).createSync(recursive: true);
      Link(path.join(root, 'outside')).createSync('..');
      final output = path.join(_temp.path, 'out_links');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final copy = path.join(output, 'copy', 'shared');
      expect(Directory(path.join(copy, '.git')).existsSync(), isFalse);
      expect(Directory(path.join(copy, 'build')).existsSync(), isFalse);
      expect(Directory(path.join(copy, 'example', 'build')).existsSync(), isFalse);
      expect(Link(path.join(copy, 'loop')).targetSync(), '.');
      expect(Link(path.join(copy, 'outside')).targetSync(), Directory(path.dirname(root)).resolveSymbolicLinksSync());
    });

    test('generates an SDK constraint compatible with Dart 3 for legacy lower bounds', () async {
      final package = await _prepareFixture('multi', name: 'legacy');
      final root = path.join(package, 'one', 'shared');
      final pubspec = File(path.join(root, 'pubspec.yaml'));
      pubspec.writeAsStringSync(pubspec.readAsStringSync().replaceFirst('sdk: ^3.10.0', "sdk: '>=2.19.0 <4.0.0'"));
      final output = path.join(_temp.path, 'out_legacy');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(File(path.join(output, 'pubspec.yaml')).readAsStringSync(), contains('sdk: ">=2.19.0 <4.0.0"'));
      expect('${result.stdout}', isNot(contains('could not be resolved')));
    });

    test('never writes assets outside of the output directory', () async {
      final package = await _prepareFixture('multi', name: 'assets');
      final root = path.join(package, 'one', 'shared');
      File(path.join(package, 'one', 'shared_asset.txt')).writeAsStringSync('shared');
      final pubspec = File(path.join(root, 'pubspec.yaml'));
      pubspec.writeAsStringSync('${pubspec.readAsStringSync()}flutter:\n  assets:\n    - ../shared_asset.txt\n');
      final output = Directory(path.join(_temp.path, 'assets_out', 'out'));
      final result = await _obfuscate(['--src=$root', '--out=${output.path}']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(File(path.join(output.parent.path, 'shared_asset.txt')).existsSync(), isFalse);
      expect(File(path.join(output.path, 'pubspec.yaml')).readAsStringSync(), isNot(contains('shared_asset')));
      expect(result.stdout, contains('asset "../shared_asset.txt" of the shared_one package is placed outside of the package'));
    });

    test('supports workspace roots, keeping the resolution of their members', () async {
      final root = Directory(path.join(_temp.path, 'workspace'));
      File(path.join(root.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: ws_root\npublish_to: none\nenvironment:\n  sdk: ^3.10.0\nworkspace:\n  - packages/member\n');
      File(path.join(root.path, 'lib', 'root.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Root {\n  int value = 1;\n}\n');
      final member = path.join(root.path, 'packages', 'member');
      File(path.join(member, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'name: ws_member\npublish_to: none\nresolution: workspace\nenvironment:\n  sdk: ^3.10.0\n'
          'dependencies:\n  ws_root:\n    path: ../..\n',
        );
      File(path.join(member, 'lib', 'member.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync("import 'package:ws_root/root.dart';\n\nint member() => Root().value;\n");
      final output = path.join(_temp.path, 'out_workspace');
      final result = await _obfuscate(['--src=${root.path}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final copiedMember = path.join(output, 'copy', 'workspace', 'packages', 'member');
      expect(File(path.join(copiedMember, 'pubspec.yaml')).readAsStringSync(), contains('resolution: workspace'));
      expect(await _errors(copiedMember), isEmpty);
      expect(File(path.join(copiedMember, 'lib', 'member.dart')).readAsStringSync(), isNot(_containsWord('Root')));
    });

    test('maps path dependencies between nested packages to the copies', () async {
      final root = Directory(path.join(_temp.path, 'nested'));
      void write(String file, String contents) => File(path.join(root.path, file))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
      write('pubspec.yaml', 'name: nested_root\npublish_to: none\nenvironment:\n  sdk: ^3.10.0\n');
      write('lib/root.dart', 'class Root {\n  int value = 1;\n}\n');
      write(
        'tools/b/pubspec.yaml',
        'name: nested_b\npublish_to: none\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  nested_root:\n    path: ../..\n',
      );
      write('tools/b/lib/b.dart', "import 'package:nested_root/root.dart';\n\nint b() => Root().value;\n");
      write(
        'tools/c/pubspec.yaml',
        'name: nested_c\npublish_to: none\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n'
            '  nested_root:\n    path: ../..\n  nested_b:\n    path: ../b\n',
      );
      write(
        'tools/c/lib/c.dart',
        "import 'package:nested_b/b.dart';\nimport 'package:nested_root/root.dart';\n\nint c() => b() + Root().value;\n",
      );
      final output = path.join(_temp.path, 'out_nested');
      final result = await _obfuscate(['--src=${root.path}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect('${result.stdout}', isNot(contains('may not be updated')));
      final copy = path.join(output, 'copy', 'nested');
      expect(File(path.join(copy, 'tools', 'c', 'pubspec.yaml')).readAsStringSync(), contains(path.join(copy, 'tools', 'b')));
      expect(await _errors(path.join(copy, 'tools', 'c')), isEmpty);
      expect(File(path.join(copy, 'tools', 'c', 'lib', 'c.dart')).readAsStringSync(), isNot(_containsWord('Root')));
    });

    test('skips nested packages with invalid pubspec files, such as templates', () async {
      final package = await _prepareFixture('multi', name: 'templates');
      final root = path.join(package, 'one', 'shared');
      File(path.join(root, 'bricks', '__brick__', '{{name}}', 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: {{name}}\n  invalid: [\n');
      final output = path.join(_temp.path, 'out_templates');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect('${result.stdout}', contains('is not a valid pubspec.yaml file'));
    });

    test('resolves the local pubspec overrides from the copy', () async {
      final package = await _prepareFixture('multi', name: 'overrides');
      final root = path.join(package, 'two', 'shared');
      final pubspec = File(path.join(root, 'pubspec.yaml'));
      pubspec.writeAsStringSync(pubspec.readAsStringSync().replaceFirst('    path: ../../one/shared\n', '    path: ../missing\n'));
      File(path.join(root, 'pubspec_overrides.yaml')).writeAsStringSync(
        'dependency_overrides:\n  shared_one:\n    path: ../../one/shared\n',
      );
      final output = path.join(_temp.path, 'out_overrides');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _errors(output, 'lib/merged.dart'), isEmpty);
    });

    test('copies symbolic links to library sources as files, never writing through them', () async {
      if (Platform.isWindows) return;
      final package = await _prepareFixture('multi', name: 'library_links');
      final root = path.join(package, 'one', 'shared');
      final shared = File(path.join(package, 'shared_code', 'greeter.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Greeter {\n  String greet() => \'hi\';\n}\n');
      Link(path.join(root, 'lib', 'greeter.dart')).createSync(shared.path);
      File(path.join(root, 'lib', 'use_greeter.dart')).writeAsStringSync(
        "import 'greeter.dart';\n\nString useGreeter() => Greeter().greet();\n",
      );
      final output = path.join(_temp.path, 'out_library_links');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(shared.readAsStringSync(), contains('class Greeter'));
      final copied = File(path.join(output, 'copy', 'shared', 'lib', 'greeter.dart'));
      expect(FileSystemEntity.isLinkSync(copied.path), isFalse);
      expect(copied.readAsStringSync(), isNot(contains('Greeter')));
      expect(await _errors(output, 'lib/merged.dart'), isEmpty);
    });

    test('never copies Dart sources declared as assets', () async {
      final package = await _prepareFixture('multi', name: 'dart_assets');
      final root = path.join(package, 'one', 'shared');
      final pubspec = File(path.join(root, 'pubspec.yaml'));
      pubspec.writeAsStringSync('${pubspec.readAsStringSync()}flutter:\n  assets:\n    - lib/\n');
      File(path.join(root, 'lib', 'data.json')).writeAsStringSync('{}');
      final output = path.join(_temp.path, 'out_dart_assets');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(File(path.join(output, 'lib', 'shared_one.dart')).existsSync(), isFalse);
      expect(File(path.join(output, 'lib', 'data.json')).existsSync(), isTrue);
    });

    test('reports source files which are not valid UTF-8', () async {
      final package = await _prepareFixture('multi', name: 'encoding');
      final root = path.join(package, 'one', 'shared');
      File(path.join(root, 'lib', 'latin1.dart')).writeAsBytesSync([...'// Caf'.codeUnits, 0xE9, 10, ...'int latin = 1;\n'.codeUnits]);
      final output = path.join(_temp.path, 'out_encoding');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('is not a valid UTF-8 file'));
    });

    test('qualifies inherited members captured by dart:core names imported only with prefixes', () async {
      final root = Directory(path.join(_temp.path, 'core_prefixed'));
      File(path.join(root.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: core_prefixed\nenvironment:\n  sdk: ^3.10.0\n');
      File(path.join(root.path, 'lib', 'main.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
import 'dart:core' as $core;

class Logger {
  final $core.List<$core.String> lines = [];

  void print($core.Object? value) => lines.add('logged: $value');
}

class Service extends Logger {
  void run() {
    print('started');
  }
}

void main() {
  final service = Service()..run();
  $core.print(service.lines);
}
''');
      await _run('dart', ['pub', 'get', '--offline'], workingDirectory: root.path);
      final output = path.join(_temp.path, 'out_core_prefixed');
      final result = await _obfuscate(['--src=${root.path}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(output, 'lib/merged.dart'), '[logged: started]\n');
    });

    test('keeps relative imports pointing outside of the package valid in the copy', () async {
      final root = Directory(path.join(_temp.path, 'relative_outside', 'pkg'));
      File(path.join(root.parent.path, 'shared', 'util.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('String shout(String value) => value.toUpperCase();\n');
      File(path.join(root.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: relative_outside\nenvironment:\n  sdk: ^3.10.0\n');
      File(path.join(root.path, 'lib', 'main.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Greeter {}\n\nvoid main() => print(Greeter());\n');
      File(path.join(root.path, 'bin', 'tool.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync("import '../../shared/util.dart';\n\nvoid main() => print(shout('hi'));\n");
      await _run('dart', ['pub', 'get', '--offline'], workingDirectory: root.path);
      final output = path.join(_temp.path, 'out_relative_outside');
      final result = await _obfuscate(['--src=${root.path}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(path.join(output, 'copy', 'pkg'), 'bin/tool.dart'), 'HI\n');
    });

    test('resolves workspace members depending on each other by version', () async {
      final root = path.join(_temp.path, 'workspace_versions');
      await _writePackages(
        root,
        {
          'pubspec.yaml': 'name: ws\npublish_to: none\nenvironment:\n  sdk: ^3.10.0\nworkspace:\n  - packages/core\n  - packages/app\n',
          'packages/core/pubspec.yaml':
              'name: ws_core\nversion: 1.0.0\npublish_to: none\nresolution: workspace\nenvironment:\n  sdk: ^3.10.0\n',
          'packages/core/lib/core.dart': 'class Money {\n  const Money(this.cents);\n\n  final int cents;\n}\n',
          'packages/app/pubspec.yaml':
              'name: ws_app\npublish_to: none\nresolution: workspace\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ws_core: ^1.0.0\n',
          'packages/app/lib/main.dart': "import 'package:ws_core/core.dart';\n\nvoid main() => print(const Money(1234).cents);\n",
        },
        ['.'],
      );
      for (final sources in [
        [path.join(root, 'packages', 'core'), path.join(root, 'packages', 'app')],
        [path.join(root, 'packages', 'app')],
      ]) {
        final output = path.join(_temp.path, 'out_workspace_versions_${sources.length}');
        final result = await _obfuscate(['--src=${sources.join(',')}', '--out=$output']);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(await _runDart(path.join(output, 'copy', 'app'), 'lib/main.dart'), '1234\n');
        expect(await _runDart(output, 'lib/merged.dart'), '1234\n');
      }
    });

    test('uses the language versions of libraries newer than the package constraint', () async {
      final root = path.join(_temp.path, 'newer_version');
      await _writePackages(
        root,
        {
          'pubspec.yaml': "name: newer_version\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n",
          'lib/main.dart': '// @dart=3.10\nenum Mode { a, b }\n\nvoid main() {\n  Mode mode = .b;\n  print(mode);\n}\n',
        },
        ['.'],
      );
      final output = path.join(_temp.path, 'out_newer_version');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(output, 'lib/merged.dart'), 'Mode.b\n');
    });

    test('adapts pre-3.0 libraries extending platform classes with class modifiers', () async {
      final root = path.join(_temp.path, 'legacy_modifiers');
      await _writePackages(
        root,
        {
          'legacy/pubspec.yaml': "name: legacy\nenvironment:\n  sdk: '>=2.19.0 <4.0.0'\n",
          'legacy/lib/legacy.dart': r'''
import 'dart:collection';

class Countdown extends Iterator<int> {
  Countdown(this._value);

  int _value;

  @override
  int get current => _value;

  @override
  bool moveNext() => --_value >= 0;
}

class Entry extends LinkedListEntry<Entry> {
  Entry(this.label);

  final String label;
}

String describeLegacy() {
  final countdown = Countdown(3);
  final values = <int>[];
  while (countdown.moveNext()) {
    values.add(countdown.current);
  }
  final list = LinkedList<Entry>()..addAll([Entry('a'), Entry('b')]);
  return '$values ${list.map((entry) => entry.label).join()}';
}
''',
          'app/pubspec.yaml': 'name: legacy_app\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  legacy:\n    path: ../legacy\n',
          'app/lib/main.dart': "import 'package:legacy/legacy.dart';\n\nvoid main() => print(describeLegacy());\n",
        },
        ['legacy', 'app'],
      );
      final output = path.join(_temp.path, 'out_legacy_modifiers');
      final result = await _obfuscate(['--src=${path.join(root, 'legacy')},${path.join(root, 'app')}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(output, 'lib/merged.dart'), '[2, 1, 0] ab\n');
    });

    test('keeps enhanced enum members of merged packages older than Dart 2.17 valid', () async {
      final root = path.join(_temp.path, 'old_enums');
      await _writePackages(
        root,
        {
          'pubspec.yaml': "name: old_enums\nenvironment:\n  sdk: '>=2.12.0 <4.0.0'\n",
          'lib/a.dart': "enum Mode { fast, slow }\n\nString modeA() => '\${Mode.fast}';\n",
          'lib/b.dart': "enum Mode { on, off }\n\nString modeB() => '\${Mode.off}';\n",
          'lib/main.dart': "import 'a.dart';\nimport 'b.dart';\n\nvoid main() => print('\${modeA()} \${modeB()}');\n",
        },
        ['.'],
      );
      final output = path.join(_temp.path, 'out_old_enums');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(output, 'lib/merged.dart'), 'Mode.fast Mode.off\n');
    });

    test('maps relative URIs into other obfuscated packages to their copies', () async {
      final root = path.join(_temp.path, 'relative_other');
      await _writePackages(
        root,
        {
          'core/pubspec.yaml': 'name: rel_core\nenvironment:\n  sdk: ^3.10.0\n',
          'core/lib/core.dart': 'class Account {\n  Account(this.owner);\n\n  final String owner;\n}\n',
          'core/test/fixtures.dart': "import 'package:rel_core/core.dart';\n\nAccount sampleAccount() => Account('ann');\n",
          'app/pubspec.yaml': 'name: rel_app\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  rel_core:\n    path: ../core\n',
          'app/lib/main.dart': 'void main() {}\n',
          'app/test/app_test.dart': "import '../../core/test/fixtures.dart';\n\nvoid main() => print(sampleAccount().owner);\n",
        },
        ['core', 'app'],
      );
      final output = path.join(_temp.path, 'out_relative_other');
      final result = await _obfuscate(['--src=${path.join(root, 'core')},${path.join(root, 'app')}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(await _runDart(path.join(output, 'copy', 'app'), 'test/app_test.dart'), 'ann\n');
    });

    test('keeps private named parameters valid', () async {
      final root = path.join(_temp.path, 'private_named');
      await _writePackages(
        root,
        {
          'pubspec.yaml': 'name: private_named\nenvironment:\n  sdk: ^3.12.0\n',
          'lib/a.dart': 'class Other {\n  Other(this._value);\n\n  final int _value;\n\n  int get value => _value + 100;\n}\n',
          'lib/b.dart': r'''
class Box {
  Box({required this._value, this.label = 'box'});

  final int _value;
  final String label;

  int get doubled => _value * 2;
}

class Crate extends Box {
  Crate({required super.value}) : super(label: 'crate');
}

abstract class Wrapper {
  factory Wrapper({required int value}) = _Wrapped;

  int get unwrapped;
}

class _Wrapped implements Wrapper {
  _Wrapped({required this._value});

  final int _value;

  @override
  int get unwrapped => _value;
}

String describe() => '${Box(value: 2).doubled} ${Crate(value: 3).doubled}';
''',
          'lib/main.dart': r'''
import 'a.dart';
import 'b.dart';

void main() {
  final box = Box(value: 4, label: 'large');
  print('${Other(1).value} ${box.label} ${box.doubled} ${Crate(value: 5).label} ${Wrapper(value: 6).unwrapped} ${describe()}');
}
''',
        },
        ['.'],
      );
      // The fields initialized by private named parameters keep their names, which determine the parameter names.
      final output = path.join(_temp.path, 'out_private_named');
      final result = await _obfuscate(['--src=$root', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final copy = path.join(output, 'copy', 'private_named');
      await _verifyOutput(source: root, copy: copy, output: output);
      expect(File(path.join(copy, 'lib', 'b.dart')).readAsStringSync(), _containsWord('_value'));
      expect(File(path.join(copy, 'lib', 'b.dart')).readAsStringSync(), isNot(_containsWord('label')));
      // Once merged, the clashing private fields are renamed along with the public names of the parameters.
      final keptOutput = path.join(_temp.path, 'out_private_named_kept');
      final keptResult = await _obfuscate(['--src=$root', '--out=$keptOutput', '--pub=_value']);
      expect(keptResult.exitCode, 0, reason: '${keptResult.stdout}${keptResult.stderr}');
      expect(keptResult.stdout, contains('the named parameter "value" is renamed to "value_1"'));
      expect(await _errors(keptOutput, 'lib/merged.dart'), isEmpty);
      expect(await _runDart(keptOutput, 'lib/merged.dart'), await _runDart(root, 'lib/main.dart'));
      expect(File(path.join(keptOutput, 'lib', 'merged.dart')).readAsStringSync(), contains('(value_1: 4,'));
    });

    test(
      'supports primary constructors',
      () async {
        final root = path.join(_temp.path, 'primary');
        await _writePackages(
          root,
          {
            'pubspec.yaml': 'name: primary\nenvironment:\n  sdk: ^3.13.0\n',
            'lib/shapes.dart': r'''
class Point(final int x, final int y) {
  this : assert(x >= 0);

  int get sum => x + y;
}

class Size({required final int width, final int height = 1});

class Labeled.named(final String text) {
  String shout() => text.toUpperCase();
}

extension type Meters(int value) {
  Meters twice() => Meters(value * 2);
}

enum Tone(final String hex) {
  red('#f00'),
  blue('#00f');

  String get code => hex;
}

class Legacy {
  new create(this.amount);

  factory build() => Legacy.create(7);

  final int amount;
}

abstract class Base {
  int get _secret;

  int reveal() => 1;
}

class Counter(final int _count) {
  int get count => _count;
}

class Item(final String name);

class Scaled(final int factor) {
  final int doubled = factor * 2;
}

int Function() peekSecret(Base base) => () => base._secret;
''',
            'lib/impl.dart': r'''
import 'shapes.dart';

class Impl(final int value) extends Base;

class Tally(final int _count) {
  int get count => _count + 1000;
}

class Item(final int id);

String describeImpl() => '${Impl(3).value} ${Impl(4).reveal()} ${Tally(2).count} ${Item(9).id}';
''',
            'lib/main.dart': r'''
import 'impl.dart' hide Item;
import 'shapes.dart';

void main() {
  final size = Size(width: 3);
  print([
    Point(1, 2).sum,
    '${size.width}x${size.height}',
    Size(width: 4, height: 5).height,
    Labeled.named('hey').shout(),
    Meters(21).twice().value,
    Tone.blue.code,
    Legacy.build().amount,
    Counter(5).count,
    Item('item').name,
    Scaled(4).doubled,
    describeImpl(),
  ].join(' '));
}
''',
          },
          ['.'],
        );
        final output = path.join(_temp.path, 'out_primary');
        final result = await _obfuscate(['--src=$root', '--out=$output']);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        final copy = path.join(output, 'copy', 'primary');
        await _verifyOutput(source: root, copy: copy, output: output);
        final copied = _sources(path.join(copy, 'lib'));
        for (final name in ['Point', 'x', 'width', 'height', 'Labeled', 'text', 'hex', 'Legacy', 'amount', 'factor', 'doubled']) {
          expect(copied, isNot(_containsWord(name)), reason: name);
        }
        // The merger renames the clashing classes and private fields declared by primary constructors.
        final keptOutput = path.join(_temp.path, 'out_primary_kept');
        final keptResult = await _obfuscate(['--src=$root', '--out=$keptOutput', '--pub=Item,_count,Base']);
        expect(keptResult.exitCode, 0, reason: '${keptResult.stdout}${keptResult.stderr}');
        expect(await _errors(keptOutput, 'lib/merged.dart'), isEmpty);
        expect(await _runDart(keptOutput, 'lib/merged.dart'), await _runDart(root, 'lib/main.dart'));
        final merged = File(path.join(keptOutput, 'lib', 'merged.dart')).readAsStringSync();
        expect(merged, allOf(contains('class Item_1(final String name);'), contains('_count_1')));
      },
      skip: _sdkVersion < Version(3, 13, 0) ? 'Primary constructors require Dart 3.13' : false,
    );

    test('reports conflicting dependency declarations', () async {
      final root = Directory(path.join(_temp.path, 'conflict'));
      for (final name in ['dep_one', 'dep_two']) {
        final directory = Directory(path.join(root.path, name, 'lib'))..createSync(recursive: true);
        File(path.join(directory.parent.path, 'pubspec.yaml')).writeAsStringSync('name: dep\nenvironment:\n  sdk: ^3.10.0\n');
        File(path.join(directory.path, 'dep.dart')).writeAsStringSync('int value = 1;\n');
      }
      for (final (name, dependency) in [('app_one', 'dep_one'), ('app_two', 'dep_two')]) {
        final directory = Directory(path.join(root.path, name, 'lib'))..createSync(recursive: true);
        File(path.join(directory.parent.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $name\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  dep:\n    path: ../$dependency\n',
        );
        File(path.join(directory.path, '$name.dart')).writeAsStringSync('class ${name == 'app_one' ? 'One' : 'Two'} {}\n');
      }
      final output = path.join(_temp.path, 'out_conflict');
      final result = await _obfuscate(['--src=${path.join(root.path, 'app_one')},${path.join(root.path, 'app_two')}', '--out=$output']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('conflicting declarations of the "dep" dependency'));
    });

    test('reports missing arguments without a stack trace', () async {
      await expectFailure(['--src=$source'], 'outputDirectory is mandatory');
    });

    test('reports invalid seeds', () async {
      await expectFailure(['--src=$source', '--out=${path.join(_temp.path, 'out_seed')}', '--seed=abc'], 'must be an integer');
    });
  });
}
