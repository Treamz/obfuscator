import 'dart:io' as dart_io;

import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:obfuscator/src/generator.dart';
import 'package:obfuscator/src/merger.dart';

void main(
  List<String> arguments,
) async {
  try {
    // Generate the runtime configuration.
    final configuration = Configuration.fromArguments(
      arguments: arguments,
    );

    // Validate the inputs and allocate runtime resources.
    await configuration.init();

    // Instantiate source code object collector.
    final collector = ObjectCollector(
      configuration: configuration,
    );

    // Collect the declarations to be obfuscated and their references.
    await collector.processUnits();

    // Instantiate source code object generator.
    final generator = Generator(
      configuration: configuration,
      collector: collector,
    );

    // Replace the copied file contents with new object identifiers.
    await generator.processCopiedSourceDirectories();

    // Merge provided source code to a single file.
    final merged = await ProjectMerger(
      configuration: configuration,
      collector: collector,
    ).generateMergedProject();
    if (!merged) dart_io.exitCode = 1;
  } on ConfigurationException catch (e) {
    dart_io.stderr.writeln('Error: ${e.message}');
    dart_io.exitCode = 1;
  }
}
