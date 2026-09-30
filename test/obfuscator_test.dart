@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:obfuscator/src/config.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Location of the fixture packages.
final _fixtures = path.absolute('test', 'fixtures');

late Directory _temp;

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
      for (final name in ['area', 'value', 'stackTrace', 'hashCode', 'name']) {
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
        'name: consumer\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  merged_app:\n    path: $output\n',
      );
      File(path.join(consumer.path, 'main.dart')).writeAsStringSync(
        "import 'package:merged_app/merged.dart';\n\n"
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
