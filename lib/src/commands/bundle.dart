import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/command.dart';

class Bundle extends Command {
  final String output;
  final String target;
  final String? source;

  Bundle(this.output, this.target, [this.source]);

  void bundleSources() {
    final tempBuildPath = join(output, 'temp_build');
    deleteDir(tempBuildPath, recursive: true);
    createDir(tempBuildPath, recursive: true);

    // TODO: Compile to JS and concatenate paperback-extensions-common and copy includes folder
    compileSources();

    final buildTimer = time();
    final baseBundlesPath = join(output, 'bundles');
    final bundlesPath = join(baseBundlesPath, source);
    deleteDir(bundlesPath, recursive: true);
    createDir(bundlesPath, recursive: true);

    final directoryPath = join(output, 'temp_build', source);
    final file = join(directoryPath, 'source.js');
    if (!exists(file)) {
      printerr(red('Error: Could not find generated file: $file'));
      exit(2);
    }

    copyTree(directoryPath, bundlesPath, overwrite: true);

    stopTimer(buildTimer, prefix: 'Bundle time');
    deleteDir(tempBuildPath, recursive: true);
  }

  void run() {
    final executionTimer = time();
    bundleSources();
    createVersioningFile();
    generateHomepage();
    stopTimer(executionTimer, prefix: 'Execution time');
  }

  void createVersioningFile() {
    final verionTimer = time();
    stopTimer(verionTimer, prefix: 'Versioning File');
  }

  void generateHomepage() {
    final homepageTimer = time();

    stopTimer(homepageTimer, prefix: 'Homepage Generation');
  }

  void compileSources() {
    final compileTimer = time();

    final sources = find('*', workingDirectory: target, types: [Find.directory]).toList();
    for (final targetSource in sources) {
      final sourceFile = '${basename(targetSource)}.dart';
      final sourcePath = join(targetSource, sourceFile);
      if (!exists(sourcePath)) {
        printerr(yellow(
          'Skipping "${basename(targetSource)}", expected source file "$sourceFile" not found',
        ));
        continue;
      }

      // compile source to js
      final tempSourceFolder = join(output, 'temp_build', basename(targetSource));
      final jsPath = join(tempSourceFolder, 'source.js');
      createDir(tempSourceFolder, recursive: true);

      // TODO: Download and compile to JS paperback-extensions-common

      final exitCode = runDartJsCompiler(sourceFile, output: jsPath);
      if (exitCode != 0) {
        deleteDir(tempSourceFolder, recursive: true);
        continue;
      }

      // copy includes folder
      final includesPath = join(targetSource, 'includes');
      if (exists(includesPath)) {
        final includesDestPath = join(tempSourceFolder, 'includes');
        createDir(includesDestPath, recursive: true);
        copyTree(includesPath, includesDestPath, overwrite: true);
      }
    }

    stopTimer(compileTimer, prefix: 'Compiling project');
  }

  /// Runs the dart compiler to compile the given [script] to js.
  /// The compiled js file will be saved to [output].
  ///
  /// Returns the exit code of the process.
  int runDartJsCompiler(
    String script, {
    required String output,
  }) {
    final process = Process.runSync('dart', ['compile', 'js', script, '-o', output]);
    if (process.exitCode != 0) {
      printerr(yellow('Warning: Could not compile $script'));
      printerr(process.stderr);
      print(yellow('Continuing...\n'));
    }
    return process.exitCode;
  }
}
