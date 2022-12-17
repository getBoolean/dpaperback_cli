import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';
import 'package:puppeteer/puppeteer.dart' as ppt;
import 'package:puppeteer/puppeteer.dart';

const kMinifiedLibrary = 'lib.min.js';
const kBrowserifyPackage = 'browserify@^17';
const kCliPrefix = '\$SourceId\$';

class Bundle extends Command<int> with CommandTime {
  late String output;
  late String target;
  late String? source;
  late String commonsPackage;

  Bundle() {
    argParser
      ..addSeparator('Flags:')
      ..addOption('output',
          abbr: 'o', help: 'The output directory.', defaultsTo: './', valueHelp: 'folder')
      ..addOption('target',
          abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib', valueHelp: 'folder')
      ..addOption('source', abbr: 's', help: 'Bundle a single source.', valueHelp: 'source name')
      ..addOption(
        'paperback-extensions-common',
        abbr: 'c',
        help: 'The Paperback Extensions Common Package and Version',
        valueHelp: ':package@:version',
        defaultsTo: kDefaultPaperbackExtensionsCommon,
      );
  }

  @override
  String get description =>
      'Builds all the sources in the repository and generates a versioning file';

  @override
  String get name => 'bundle';

  @override
  List<String> get aliases => ['build'];

  @override
  Future<int> run() async {
    final results = argResults;
    if (results == null) return 1;

    output = parseOutputPath(results);
    target = parseTargetPath(results);
    source = results['source'] as String?;
    commonsPackage = results['paperback-extensions-common'] as String;

    return BundleCli(output, target, source: source, commonsPackage: commonsPackage).run();
  }

  String parseTargetPath(ArgResults command) {
    final targetArgument = command['target'] as String;
    final targetPath = canonicalize(targetArgument);
    if (!exists(targetPath)) {
      print(red('The target directory "$targetArgument" could not be found'));
      exit(2);
    }

    return targetPath;
  }

  String parseOutputPath(ArgResults command) {
    final outputArgument = command['output'] as String;
    final outputPath = canonicalize(outputArgument);

    if (!exists(outputPath)) {
      createDir(outputPath, recursive: true);
    }
    return outputPath;
  }
}

class BundleCli with CommandTime {
  final String output;
  final String target;
  final String? source;
  final String commonsPackage;

  BundleCli(this.output, this.target, {required this.source, required this.commonsPackage});

  int run() {
    final executionTimer = time();
    bundleSources();
    createVersioningFile();
    generateHomepage();
    stopTimer(executionTimer, prefix: 'Execution time');
    return 0;
  }

  void createVersioningFile() {
    final verionTimer = time();

    final versioningFileMap = {
      'buildTime': DateTime.now().toUtc().toIso8601String(),
      'sources': [],
    };

    final browser = waitForEx(ppt.puppeteer.launch());
    final bundlesPath = join(output, 'bundles');
    // for each folder in bundles
    final dirs = find('*', workingDirectory: bundlesPath, types: [Find.directory], recursive: false)
        .toList();
    for (final dir in dirs) {
      final source = basename(dir);
      final timer = time();
      try {
        final sourceInfo = generateSourceInfo(browser, source, bundlesPath);
        final sourceId = sourceInfo['id'];
        Directory(dir).renameSync(join(dirname(dir), sourceId));
        (versioningFileMap['sources']! as List).add(sourceInfo);
        stopTimer(timer, prefix: '- Generating $sourceId Info');
      } on FileNotFoundException {
        printerr(yellow('Skipping "$source", source.js not found'));
        continue;
      } on DCliException catch (e) {
        printerr(red('Skipping "$source", ${e.message}${e.cause != null ? ' - ${e.cause}' : ''}'));
        continue;
      } on FileSystemException catch (e) {
        printerr(red('Skipping "$source", could not read source.js into memory: ${e.message}'));
        continue;
      } on Exception catch (e) {
        printerr(red('Skipping "$source", ${e.toString()}'));
        continue;
      }
    }
    waitForEx(browser.close());
    final versioningFileContents = jsonEncode(versioningFileMap);
    File(join(bundlesPath, 'versioning.json')).writeAsStringSync(versioningFileContents);
    stopTimer(verionTimer, prefix: 'Versioning File');
  }

  Map<String, dynamic> generateSourceInfo(Browser browser, String source, String directoryPath) {
    final sourceJs = join(directoryPath, source, 'source.js');
    // TODO: Rename source folder to id from source.js
    final sourceContents = exists(sourceJs) ? File(sourceJs).readAsStringSync() : null;
    if (sourceContents == null) {
      throw FileNotFoundException(sourceJs);
    }
    final page = waitForEx(browser.newPage());

    waitForEx(page.evaluate(sourceContents));
    final String sourceId = waitForEx(page.evaluate(kCliPrefix));
    final Map<String, dynamic> sourceInfo = waitForEx(page.evaluate('${sourceId}Info'));
    sourceInfo['id'] = sourceId;
    print(green('SOURCE ID: $sourceId', bold: true));
    print(green('SOURCE INFO: $sourceInfo', bold: true));

    return sourceInfo;
  }

  void bundleSources() {
    final tempBuildPath = join(output, 'temp_build');
    // delete all files in temp_build except kMinifiedLibrary
    if (!exists(tempBuildPath)) {
      createDir(tempBuildPath, recursive: true);
    }
    find('*', workingDirectory: tempBuildPath, recursive: false).forEach((file) {
      if (isFile(file) && file != kMinifiedLibrary) {
        delete(file);
      } else if (isDirectory(file)) {
        deleteDir(file, recursive: true);
      }
    });

    _compileSources(tempBuildPath);

    final buildTimer = time();
    final baseBundlesPath = join(output, 'bundles');
    final bundlesPath = join(baseBundlesPath, source);
    if (exists(bundlesPath)) {
      deleteDir(bundlesPath, recursive: true);
    }
    createDir(bundlesPath, recursive: true);

    final directoryPath = join(tempBuildPath, source);
    final targetDirPath = join(bundlesPath, source);
    copyTree(directoryPath, targetDirPath, overwrite: true);

    stopTimer(buildTimer, prefix: 'Bundle time');
    deleteDir(tempBuildPath, recursive: true);
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
    final minifiedLib = join(tempBuildPath, kMinifiedLibrary);
    if (!exists(minifiedLib)) {
      _bundleJsDependencies(minifiedLib);
    }

    final sources = source != null
        ? [join(target, source)]
        : find('*', workingDirectory: target, types: [Find.directory], recursive: false).toList();
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
      if (!exists(tempSourceFolder)) {
        createDir(tempSourceFolder, recursive: true);
      }

      final exitCode = runDartJsCompiler(sourcePath, output: tempJsPath);
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
        if (!exists(includesDestPath)) {
          createDir(includesDestPath, recursive: true);
        }

        copyTree(includesPath, includesDestPath, overwrite: true);
      }
    }

    stopTimer(compileTimer, prefix: 'Compiling project');
  }

  void _bundleJsDependencies(String outputFile) {
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
    if (!exists(dirname(outputFile))) {
      createDir(dirname(outputFile), recursive: true);
    }
    _bundleCommons(commonsTempDir, output: outputFile);
    deleteDir(commonsTempDir, recursive: true);
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
      ['compile', 'js', script, '-o', output, if (minify) '-m', '--no-source-maps'],
    );
    if (process.exitCode != 0) {
      printerr(yellow('Warning: Could not compile $script'));
      printerr(process.stdout);
      printerr(process.stderr);
      print(yellow('Continuing...\n'));
      return process.exitCode;
    }
    if (exists('$output.deps')) {
      delete('$output.deps');
    }

    return process.exitCode;
  }
}
