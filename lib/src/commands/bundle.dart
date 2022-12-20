import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/dcli/resource/generated/resource_registry.g.dart';
import 'package:dpaperback_cli/src/utils/time_mixin.dart';
import 'package:dpaperback_cli/src/utils/unpack_async.dart';
import 'package:puppeteer/puppeteer.dart' as ppt;
import 'package:puppeteer/puppeteer.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

const kMinifiedLibrary = 'lib.min.js';
const kBrowserifyPackage = 'browserify@^17';
const kPugPackage = '@anduh/pug-cli@^1.0.0-alpha8';
const kCliPrefix = '\$SourceId\$';

final browserProvider = FutureProvider.autoDispose((_) => ppt.puppeteer.launch());

class Bundle extends Command<int> {
  final ProviderContainer container;

  Bundle([ProviderContainer? container]) : container = container ?? ProviderContainer() {
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
      )
      ..addOption(
        'pubspec',
        abbr: 'P',
        help: 'The path to the pubspec.yaml',
        valueHelp: 'file-path',
        defaultsTo: './pubspec.yaml',
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

    final output = await parseOutputPath(results);
    final target = parseTargetPath(results);
    final pubspecPath = parsePubspecPath(results);
    final source = results['source'] as String?;
    final commonsPackage = results['paperback-extensions-common'] as String;

    return BundleCli(
      output: output,
      target: target,
      source: source,
      commonsPackage: commonsPackage,
      container: container,
      pubspecPath: pubspecPath,
    ).run();
  }

  String parsePubspecPath(ArgResults command) {
    final pubspecArgument = command['pubspec'] as String;
    final pubspecPath = canonicalize(pubspecArgument);
    if (!exists(pubspecPath)) {
      print(red('The pubspec file "$pubspecArgument" could not be found'));
      exit(2);
    }

    return pubspecPath;
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

  Future<String> parseOutputPath(ArgResults command) async {
    final outputArgument = command['output'] as String;
    final outputPath = canonicalize(outputArgument);

    if (!await Directory(outputPath).exists()) {
      await Directory(outputPath).create(recursive: true);
    }
    return outputPath;
  }
}

class BundleCli with CommandTime {
  final String output;
  final String target;
  final String? source;
  final String commonsPackage;
  final ProviderContainer container;
  final String pubspecPath;
  late Future<Browser> futureBrowser;

  BundleCli({
    required this.output,
    required this.target,
    this.source,
    required this.commonsPackage,
    required this.container,
    required this.pubspecPath,
  });

  Future<int> run() async {
    final executionTimer = Stopwatch()..start();
    futureBrowser = container.read(browserProvider.future);
    print('');
    final successCode = await bundleSources();
    if (successCode != 0) {
      return successCode;
    }
    await createVersioningFile();
    final homepageSuccessCode = await generateHomepage();
    if (homepageSuccessCode != 0) {
      return homepageSuccessCode;
    }

    executionTimer.stop();
    print((blue('Total Execution time: ${executionTimer.elapsedMilliseconds}ms', bold: true)));
    return 0;
  }

  Future<void> createVersioningFile() async {
    final versionTimer = Stopwatch()..start();

    final versioningFileMap = {
      'buildTime': DateTime.now().toUtc().toIso8601String(),
      'sources': [],
    };

    time(prefix: 'Launching puppeteer');
    final browser = await futureBrowser;
    stop();
    final bundlesPath = join(output, 'bundles');
    // TODO: Make async FileSystemEntity.isDirectorySync
    final directories = await Directory(bundlesPath)
        .list()
        .where((entity) => FileSystemEntity.isDirectorySync(entity.path))
        .map((entity) => entity.path)
        .toList();
    for (final dir in directories) {
      final source = basename(dir);
      try {
        time(prefix: '- Generating $source Info');
        final sourceInfo = await generateSourceInfo(browser, source, bundlesPath);
        final sourceId = sourceInfo['id'];
        Directory(dir).renameSync(join(dirname(dir), sourceId));
        (versioningFileMap['sources']! as List).add(sourceInfo);
        stop();
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
    unawaited(browser.close());
    final versioningFileContents = jsonEncode(versioningFileMap);
    await File(join(bundlesPath, 'versioning.json')).writeAsString(versioningFileContents);
    print((blue('Total Versioning File: ${versionTimer.elapsedMilliseconds}ms', bold: true)));
  }

  Future<Map<String, dynamic>> generateSourceInfo(
      Browser browser, String source, String directoryPath) async {
    final sourceJs = join(directoryPath, source, 'source.js');
    final sourceContents =
        await File(sourceJs).exists() ? await File(sourceJs).readAsString() : null;
    if (sourceContents == null) {
      throw FileNotFoundException(sourceJs);
    }
    final page = await browser.newPage();

    await page.evaluate(sourceContents);
    final String sourceId = await page.evaluate(kCliPrefix);
    final Map<String, dynamic> sourceInfo = await page.evaluate('${sourceId}Info');
    sourceInfo['id'] = sourceId;

    return sourceInfo;
  }

  Future<int> bundleSources() async {
    final tempBuildPath = join(output, 'temp_build');
    // delete all files in temp_build except kMinifiedLibrary
    if (!exists(tempBuildPath)) {
      await Directory(tempBuildPath).create(recursive: true);
    }
    final files = find('*', workingDirectory: tempBuildPath, recursive: false).toList();

    for (final file in files) {
      if (isFile(file) && basename(file) != kMinifiedLibrary) {
        await File(file).delete();
      } else if (isDirectory(file)) {
        await Directory(file).delete(recursive: true);
      }
    }

    final successCode = await _compileSources(tempBuildPath);
    if (successCode != 0) {
      return successCode;
    }

    final baseBundlesPath = join(output, 'bundles');
    final bundlesPath = join(baseBundlesPath, source);
    if (source != null) {
      if (await Directory(bundlesPath).exists()) {
        await Directory(bundlesPath).delete(recursive: true);
      }
      await Directory(bundlesPath).create(recursive: true);
    }

    final directoryPath = join(tempBuildPath, source);
    final targetDirPath = join(bundlesPath, source);
    if (!await Directory(targetDirPath).exists()) {
      await Directory(targetDirPath).create(recursive: true);
    }

    // TODO: Make async
    copyTree(directoryPath, targetDirPath, overwrite: true);

    await Directory(tempBuildPath).delete(recursive: true);
    return 0;
  }

  /// Installs paperback-extensions-common from npmjs.org
  Future<ProcessResult> installJsPackage(
    String package, {
    required String workingDirectory,
    bool global = false,
  }) async {
    return await Process.run(
      'npm',
      ['install', package, if (global) '-g'],
      workingDirectory: workingDirectory,
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified.""
      runInShell: Platform.isWindows,
    );
  }

  Future<int> _compileSources(String tempBuildPath) async {
    // Download paperback-extensions-common from npmjs.org
    if (!await Directory(join(output, '.pb_cache')).exists()) {
      await Directory(join(output, '.pb_cache')).create(recursive: true);
    }
    final minifiedLib = join(output, '.pb_cache', kMinifiedLibrary);
    if (!await File(minifiedLib).exists()) {
      time(prefix: 'Downloading dependencies');
      final successCode = await _bundleJsDependencies(minifiedLib);
      stop();
      if (successCode != 0) {
        return successCode;
      }
    }

    time(prefix: 'Compiling project');

    // TODO: Make async
    final sources = source != null
        ? [join(target, source)]
        : find('*', workingDirectory: target, types: [Find.directory], recursive: false).toList();
    for (final targetSource in sources) {
      final sourceFile = '${basename(targetSource)}.dart';
      final sourcePath = join(targetSource, sourceFile);
      if (!await File(sourcePath).exists()) {
        printerr(yellow(
          'Skipping "${basename(targetSource)}", expected source file "$sourceFile" not found',
        ));
        continue;
      }

      // compile source to js
      final tempSourceFolder = join(tempBuildPath, basename(targetSource));
      final tempJsPath = join(tempSourceFolder, 'temp.source.js');
      final finalJsPath = join(tempSourceFolder, 'source.js');
      if (!await File(tempSourceFolder).exists()) {
        await Directory(tempSourceFolder).create(recursive: true);
      }

      final exitCode = await runDartJsCompiler(sourcePath, output: tempJsPath);
      if (exitCode != 0) {
        await Directory(tempSourceFolder).delete(recursive: true);
        continue;
      }
      await File(minifiedLib).copy(finalJsPath);
      // append generated dart source to minified js dependencies
      await File(finalJsPath).writeAsBytes(
        await File(tempJsPath).readAsBytes(),
        mode: FileMode.append,
      );
      await File(tempJsPath).delete();

      // copy includes folder
      final includesPath = join(targetSource, 'includes');
      if (await Directory(includesPath).exists()) {
        final includesDestPath = join(tempSourceFolder, 'includes');
        if (!await Directory(includesDestPath).exists()) {
          await Directory(includesDestPath).create(recursive: true);
        }

        // TODO: Make async
        copyTree(includesPath, includesDestPath, overwrite: true);
      }
    }

    stop();
    return 0;
  }

  Future<int> _bundleJsDependencies(String outputFile) async {
    // TODO: make async
    final commonsTempDir = createTempDir();
    final commonResult = await installJsPackage(commonsPackage, workingDirectory: commonsTempDir);
    if (commonResult.exitCode != 0) {
      await Directory(commonsTempDir).delete(recursive: true);
      return commonResult.exitCode;
    }
    final browserifyResult =
        await installJsPackage(kBrowserifyPackage, workingDirectory: commonsTempDir, global: true);
    if (browserifyResult.exitCode != 0) {
      await Directory(commonsTempDir).delete(recursive: true);
      return browserifyResult.exitCode;
    }
    if (!exists(dirname(outputFile))) {
      await Directory(dirname(outputFile)).create(recursive: true);
    }
    await _bundleCommons(commonsTempDir, output: outputFile);
    await Directory(commonsTempDir).delete(recursive: true);
    return 0;
  }

  Future<int> _bundleCommons(String tempDir, {required String output}) async {
    return (await Process.run(
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
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified.""
      runInShell: Platform.isWindows,
    ))
        .exitCode;
  }

  /// Runs the dart compiler to compile the given [script] to js.
  /// The compiled js file will be saved to [output].
  ///
  /// Returns the exit code of the process.
  Future<int> runDartJsCompiler(
    String script, {
    required String output,
    bool minify = true,
  }) async {
    final process = await Process.run(
      'dart',
      ['compile', 'js', script, '-o', output, if (minify) '-m', '--no-source-maps'],
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified.""
      runInShell: Platform.isWindows,
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

  Future<int> generateHomepage() async {
    // TODO: Add check at start of bundle for pubspec required paperback fields

    final pubspecFile = File(pubspecPath);
    if (!await pubspecFile.exists()) {
      printerr(yellow('Warning: Could not find pubspec.yaml'));
      printerr(yellow('Skipping homepage generation\n'));
      return 1;
    }

    time(prefix: 'Total Homepage Generation');

    // Read versioning.json file
    final Map<String, dynamic> extensionsData =
        json.decode(await File(join(output, 'bundles', 'versioning.json')).readAsString());
    final YamlMap pubspec = loadYaml(await pubspecFile.readAsString());

    final List<dynamic> sources = extensionsData['sources'];
    final List<Map<String, dynamic>> extensionsList = [];
    for (final extension in sources) {
      extensionsList.add({
        'name': extension['name'],
        'tags': extension['tags'],
      });
    }

    // To be used by homepage.pug file, repositoryData must by of the format:
    /*
      {
        repositoryName: "",
        repositoryDescription: "",
        baseURL: "https://yourlinkhere",
        sources: [{name: sourceName, tags[]: []}]
        repositoryLogo: "url",
        noAddToPaperbackButton: true,
      }
    */
    final Map<String, dynamic> repositoryData = {};
    final YamlMap paperbackSection = pubspec['paperback'];
    final String repositoryName = paperbackSection['repository_name'];
    final String description = paperbackSection['description'];
    final bool? noAddToPaperbackButton = paperbackSection['no_add_to_paperback_button'];
    final String? repositoryLogo = paperbackSection['repository_logo'];
    final String? baseURL = paperbackSection['base_url'];

    repositoryData['repositoryName'] = repositoryName;
    repositoryData['repositoryDescription'] = description;
    repositoryData['sources'] = extensionsList;

    // The repository can register a custom base URL. If not, this file will try to deduct one from GITHUB_REPOSITORY
    if (baseURL != null) {
      repositoryData['baseURL'] = baseURL;
    } else {}

    if (noAddToPaperbackButton != null) {
      repositoryData['noAddToPaperbackButton'] = noAddToPaperbackButton;
    }

    if (repositoryLogo != null) {
      repositoryData['repositoryLogo'] = repositoryLogo;
    }

    final cacheDir = join(pwd, '.pb_cache');
    if (!await Directory(cacheDir).exists()) {
      await Directory(cacheDir).create(recursive: true);
    }

    // Increment version number if you change the homepage.pug file
    final pugPath = join(cacheDir, 'homepage_v1.pug');
    if (!await File(pugPath).exists()) {
      final pugResource = ResourceRegistry.resources['website_generation/homepage.pug']!;
      await pugResource.unpackAsync(pugPath);
    }

    final pugResult = await installJsPackage(kPugPackage, global: true, workingDirectory: pwd);
    if (pugResult.exitCode != 0) {
      stop();
      printerr(red('\nError: Could not install pug-cli'));
      printerr(pugResult.stdout);
      printerr(pugResult.stderr);
      return pugResult.exitCode;
    }
    final optionsFile = File(join(cacheDir, 'options.json'));
    if (!await optionsFile.exists()) {
      await optionsFile.create(recursive: true);
    }

    await optionsFile.writeAsString(json.encode(repositoryData), flush: true);

    if (!await optionsFile.exists()) {
      stop();
      printerr(red('Warning: Could not find options.json'));
      printerr(red('Skipping homepage generation\n'));
      return 2;
    }
    if (!await File(pugPath).exists()) {
      stop();
      printerr(red('Warning: Could not pug at "$pugPath"'));
      printerr(red('Skipping homepage generation\n'));
      return 2;
    }
    final result = await runPugCompile(optionsFile.path, pugPath: pugPath);
    await optionsFile.delete();
    if (result.exitCode != 0) {
      stop();
      printerr(red('\nError: Could not compile html'));
      printerr(grey(result.stdout));
      printerr(red(result.stderr));

      return result.exitCode;
    }

    final tempIndex = File(join(output, 'bundles', '${basenameWithoutExtension(pugPath)}.html'));
    await tempIndex.rename(join(output, 'bundles', 'index.html'));

    stop();
    return 0;
  }

  /// The compiled js file will be saved to [pugPath].
  ///
  /// Returns the exit code of the process.
  Future<ProcessResult> runPugCompile(String optionsFile, {required String pugPath}) async {
    final dir = createTempDir();
    final bundlesDir = join(output, 'bundles');
    if (!await Directory(bundlesDir).exists()) {
      await Directory(bundlesDir).create(recursive: true);
    }
    final process = await Process.run(
      'pug',
      ['-o', bundlesDir, '-O', optionsFile, '-D', pugPath],
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified."
      runInShell: Platform.isWindows,
      workingDirectory: dir,
    );
    await Directory(dir).delete(recursive: true);

    return process;
  }
}
