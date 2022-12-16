import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/command.dart';

const kMinifiedLibrary = 'sources.min.js';
const kBrowserifyPackage = 'browserify@^17';

class Bundle extends Command {
  final String output;
  final String target;
  final String? source;
  final String commonsPackage;

  Bundle(this.output, this.target, {this.source, required this.commonsPackage});

  void run() {
    final executionTimer = time();
    bundleSources();
    createVersioningFile();
    generateHomepage();
    stopTimer(executionTimer, prefix: 'Execution time');
  }

  void bundleSources() {
    final tempBuildPath = join(output, 'temp_build');
    deleteDir(tempBuildPath, recursive: true);
    createDir(tempBuildPath, recursive: true);

    _compileSources(tempBuildPath);

    final buildTimer = time();
    final baseBundlesPath = join(output, 'bundles');
    final bundlesPath = join(baseBundlesPath, source);
    deleteDir(bundlesPath, recursive: true);
    createDir(bundlesPath, recursive: true);

    final directoryPath = join(tempBuildPath, source);
    final targetDirPath = join(bundlesPath, source);
    copyTree(directoryPath, targetDirPath, overwrite: true);

    stopTimer(buildTimer, prefix: 'Bundle time');
    deleteDir(tempBuildPath, recursive: true);
  }

  void createVersioningFile() {
    final verionTimer = time();
    stopTimer(verionTimer, prefix: 'Versioning File');
  }

  void generateHomepage() {
    final homepageTimer = time();

    stopTimer(homepageTimer, prefix: 'Homepage Generation');
  }

  /// Installs paperback-extensions-common from npmjs.org
  int installJsPackage(String package, {required String workingDirectory, bool global = false}) {
    return Process.runSync(
      'npm',
      ['install', package, if (global) '-g'],
      workingDirectory: workingDirectory,
    ).exitCode;
  }

  void _compileSources(String tempBuildPath) {
    final compileTimer = time();

    // Download paperback-extensions-common from npmjs.org
    final commonsTempDir = createTempDir();
    final commonSuccessCode = installJsPackage(commonsPackage, workingDirectory: commonsTempDir);
    if (commonSuccessCode != 0) {
      deleteDir(commonsTempDir, recursive: true);
      exit(commonSuccessCode);
    }
    final browserifySuccessCode =
        installJsPackage(kBrowserifyPackage, workingDirectory: commonsTempDir, global: true);
    if (browserifySuccessCode != 0) {
      deleteDir(commonsTempDir, recursive: true);
      exit(browserifySuccessCode);
    }
    final minifiedLib = join(tempBuildPath, kMinifiedLibrary);
    createDir(dirname(minifiedLib), recursive: true);
    _bundleCommons(commonsTempDir, output: minifiedLib);
    deleteDir(commonsTempDir, recursive: true);

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
      final tempSourceFolder = join(tempBuildPath, basename(targetSource));
      final tempJsPath = join(tempSourceFolder, 'temp.source.js');
      final finalJsPath = join(tempSourceFolder, 'source.js');
      createDir(tempSourceFolder, recursive: true);

      final exitCode = runDartJsCompiler(sourceFile, output: tempJsPath);
      if (exitCode != 0) {
        deleteDir(tempSourceFolder, recursive: true);
        continue;
      }
      copy(minifiedLib, finalJsPath, overwrite: true);
      // append generated dart source to minified js dependencies
      File(finalJsPath).writeAsBytesSync(
        File(tempJsPath).readAsBytesSync(),
        mode: FileMode.append,
      );
      delete(tempJsPath);

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

  int _bundleCommons(String tempDir, {required String output}) {
    return Process.runSync(
      'browserify',
      [
        'node_modules/paperback-extensions-common/lib/index.js',
        '-s',
        'Sources',
        '-i',
        './node_modules/paperback-extensions-common/dist/APIWrapper.js',
        '-x',
        'axios',
        '-x',
        'cheerio',
        '-x',
        'fs',
        '-o',
        output,
      ],
      workingDirectory: tempDir,
    ).exitCode;
  }

  /// Runs the dart compiler to compile the given [script] to js.
  /// The compiled js file will be saved to [output].
  ///
  /// Returns the exit code of the process.
  int runDartJsCompiler(
    String script, {
    required String output,
    bool minify = true,
  }) {
    final process = Process.runSync(
      'dart',
      ['compile', 'js', script, '-o', output, if (minify) '-m'],
    );
    if (process.exitCode != 0) {
      printerr(yellow('Warning: Could not compile $script'));
      printerr(process.stderr);
      print(yellow('Continuing...\n'));
    }
    return process.exitCode;
  }
}
