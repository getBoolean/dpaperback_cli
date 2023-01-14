import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/dcli/resource/generated/resource_registry.g.dart';
import 'package:dpaperback_cli/src/utils/time_mixin.dart';
import 'package:dpaperback_cli/src/utils/unpack_async.dart';
import 'package:puppeteer/puppeteer.dart' as ppt;
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
      ..addFlag(
        'homepage',
        help: 'When enabled, the homepage file be generated using pug-cli',
        negatable: true,
        defaultsTo: true,
      )
      ..addFlag(
        'minified-output',
        help: 'Generate minified JavaScript',
        negatable: true,
        defaultsTo: true,
      )
      ..addSeparator('Options:')
      ..addOption('output',
          abbr: 'o', help: 'The output directory.', defaultsTo: './', valueHelp: 'folder')
      ..addOption('target',
          abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib', valueHelp: 'folder')
      ..addOption('source', abbr: 's', help: 'Bundle a single source.', valueHelp: 'source name')
      ..addOption('subfolder',
          abbr: 'f',
          help: 'The subfolder under "bundles" folder the generated sources will be built at.',
          valueHelp: 'folder')
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
    final shouldGenerateHomepage = results['homepage'] as bool;
    final minifiedOutput = results['minified-output'] as bool;

    return BundleCli(
      output: output,
      target: target,
      source: source,
      commonsPackage: commonsPackage,
      container: container,
      pubspecPath: pubspecPath,
      subfolder: results['subfolder'] as String?,
      shouldGenerateHomepage: shouldGenerateHomepage,
      minifyOutput: minifiedOutput,
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

    if (!Directory(outputPath).existsSync()) {
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
  final String? subfolder;
  final bool shouldGenerateHomepage;
  final bool minifyOutput;
  late Future<ppt.Browser> futureBrowser;

  BundleCli({
    required this.output,
    required this.target,
    this.source,
    required this.commonsPackage,
    required this.container,
    required this.pubspecPath,
    required this.subfolder,
    required this.shouldGenerateHomepage,
    required this.minifyOutput,
  });

  Future<int> run() async {
    final executionTimer = Stopwatch()..start();
    futureBrowser = container.read(browserProvider.future);
    print('');
    final successCode = await bundleSources();
    if (successCode != 0) {
      executionTimer.stop();
      await futureBrowser.then((value) => value.close());
      return successCode;
    }

    await createVersioningFile();

    if (shouldGenerateHomepage) {
      final homepageSuccessCode = await generateHomepage();
      if (homepageSuccessCode != 0) {
        executionTimer.stop();
        return homepageSuccessCode;
      }
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
    final bundlesPath = join(output, 'bundles', subfolder);
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
        stop();
        printerr(yellow('Skipping "$source", source.js not found'));
        continue;
      } on DCliException catch (e) {
        stop();
        printerr(red('Skipping "$source", ${e.message}${e.cause != null ? ' - ${e.cause}' : ''}'));
        continue;
      } on FileSystemException catch (e) {
        stop();
        printerr(red(
            'Skipping "$source", ${e.message}: ${e.osError == null ? e.message : e.osError!.message}'));
        continue;
      } on Exception catch (e) {
        stop();
        printerr(red('Skipping "$source", ${e.toString()}'));
        continue;
      }
    }
    unawaited(browser.close());
    final versioningFileContents = jsonEncode(versioningFileMap);
    await File(join(bundlesPath, 'versioning.json')).writeAsString(versioningFileContents);
    versionTimer.stop();
    print((blue('Total Versioning File: ${versionTimer.elapsedMilliseconds}ms', bold: true)));
  }

  Future<Map<String, dynamic>> generateSourceInfo(
      ppt.Browser browser, String source, String directoryPath) async {
    final sourceJs = join(directoryPath, source, 'source.js');
    final sourceContents = File(sourceJs).existsSync() ? await File(sourceJs).readAsString() : null;
    if (sourceContents == null) {
      throw FileNotFoundException(sourceJs);
    }
    final page = await browser.newPage();

    await page.evaluate(sourceContents);
    // TODO: Find another way to get the source id. This might break if multiple sources are bundled
    final String? sourceId = await page.evaluate('Sources.$kCliPrefix');
    if (sourceId == null) {
      throw Exception('Could not find source id for $source');
    }
    final Map<String, dynamic>? sourceInfo = await page.evaluate('Sources.${sourceId}Info');
    if (sourceInfo == null) {
      throw Exception('Could not find source info for $source');
    }
    sourceInfo['id'] = sourceId;

    return sourceInfo;
  }

  Future<int> bundleSources() async {
    final workingDirectory = join(output, 'bundles', subfolder);
    if (!Directory(workingDirectory).existsSync()) {
      await Directory(workingDirectory).create(recursive: true);
    }
    final paths = find('*', workingDirectory: workingDirectory, recursive: false, types: [
      Find.file,
      Find.directory,
      Find.link,
    ]).toList();

    for (final path in paths) {
      if (FileSystemEntity.isFileSync(path)) {
        await File(path).delete();
      } else if (FileSystemEntity.isDirectorySync(path)) {
        await Directory(path).delete(recursive: true);
      } else if (FileSystemEntity.isLinkSync(path)) {
        await Link(path).delete();
      }
    }

    final tempBuildPath = join(output, 'temp_build');
    if (!Directory(tempBuildPath).existsSync()) {
      await Directory(tempBuildPath).create(recursive: true);
    }
    final successCode = await _compileSources(tempBuildPath);
    if (successCode != 0) {
      return successCode;
    }

    final baseBundlesPath = join(output, 'bundles');
    final bundlesPath = join(baseBundlesPath, subfolder, source);
    if (source != null) {
      if (Directory(bundlesPath).existsSync()) {
        await Directory(bundlesPath).delete(recursive: true);
      }
      await Directory(bundlesPath).create(recursive: true);
    }

    final directoryPath = join(tempBuildPath, source);
    final targetDirPath = bundlesPath;
    if (!Directory(targetDirPath).existsSync()) {
      await Directory(targetDirPath).create(recursive: true);
    }

    // TODO: Make async
    copyTree(directoryPath, targetDirPath, overwrite: true);

    await Directory(tempBuildPath).delete(recursive: true);
    return 0;
  }

  /// Installs extensions from npmjs.org
  ///
  /// Arguments:
  /// - [package]: The ID of the package to install
  /// - [workingDirectory]: The directory to run the command in (or install to)
  /// - [global]: Whether to install the package globally
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
    if (!Directory(join(output, '.pb_cache')).existsSync()) {
      await Directory(join(output, '.pb_cache')).create(recursive: true);
    }
    final minifiedLib = join(output, '.pb_cache', kMinifiedLibrary);
    if (!File(minifiedLib).existsSync()) {
      time(prefix: 'Downloading dependencies');
      final successCode = await _bundleJsDependencies(minifiedLib);
      stop();
      if (successCode != 0) {
        printerr(red('Failed to bundle dependencies'));
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
      if (!File(sourcePath).existsSync()) {
        printerr(yellow(
          'Skipping "${basename(targetSource)}", expected source file "$sourceFile" not found',
        ));
        continue;
      }

      // compile source to js
      final tempSourceFolder = join(tempBuildPath, basename(targetSource));
      final tempJsPath = join(tempSourceFolder, 'temp.source.js');
      final finalJsPath = join(tempSourceFolder, 'source.js');
      if (!File(tempSourceFolder).existsSync()) {
        await Directory(tempSourceFolder).create(recursive: true);
      }

      final exitCode = await runDartJsCompiler(sourcePath, output: tempJsPath, minify: minifyOutput);
      if (exitCode != 0) {
        await Directory(tempSourceFolder).delete(recursive: true);
        continue;
      }
      await File(minifiedLib).copy(finalJsPath);
      await File(finalJsPath).writeAsString(
        '\nconst self = globalThis;\n',
        mode: FileMode.append,
      );
      // append generated dart source to minified js dependencies
      await File(finalJsPath).writeAsBytes(
        await File(tempJsPath).readAsBytes(),
        mode: FileMode.append,
      );
      await File(tempJsPath).delete();

      // copy includes folder
      final includesPath = join(targetSource, 'includes');
      if (Directory(includesPath).existsSync()) {
        final includesDestPath = join(tempSourceFolder, 'includes');
        if (!Directory(includesDestPath).existsSync()) {
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
      stop();
      printerr(yellow(commonResult.stdout));
      printerr(red(commonResult.stderr));
      await Directory(commonsTempDir).delete(recursive: true);
      return commonResult.exitCode;
    }

    final es6Result = await installJsPackage('es6', workingDirectory: commonsTempDir);
    if (es6Result.exitCode != 0) {
      stop();
      printerr(yellow(es6Result.stdout));
      printerr(red(es6Result.stderr));
      await Directory(commonsTempDir).delete(recursive: true);
      return es6Result.exitCode;
    }

    final browserifyResult =
        await installJsPackage(kBrowserifyPackage, workingDirectory: commonsTempDir, global: true);
    if (browserifyResult.exitCode != 0) {
      stop();
      printerr(yellow(browserifyResult.stdout));
      printerr(red(browserifyResult.stderr));
      await Directory(commonsTempDir).delete(recursive: true);
      return browserifyResult.exitCode;
    }
    if (!Directory(dirname(outputFile)).existsSync()) {
      await Directory(dirname(outputFile)).create(recursive: true);
    }
    final bundleResult = await _bundleCommons(commonsTempDir, output: outputFile);
    if (bundleResult.exitCode != 0) {
      stop();
      printerr(yellow(bundleResult.stdout));
      printerr(red(bundleResult.stderr));
      await Directory(commonsTempDir).delete(recursive: true);
      return bundleResult.exitCode;
    }
    await Directory(commonsTempDir).delete(recursive: true);
    return 0;
  }

  Future<ProcessResult> _bundleCommons(String tempDir, {required String output}) async {
    return await Process.run(
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
        '-r',
        'es6',
        '-o',
        output,
      ],
      workingDirectory: tempDir,
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified.""
      runInShell: Platform.isWindows,
    );
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
    if (!pubspecFile.existsSync()) {
      stop();
      printerr(yellow('Warning: Could not find pubspec.yaml'));
      printerr(yellow('Skipping homepage generation\n'));
      return 1;
    }

    final homepageTimer = Stopwatch()..start();

    // Read versioning.json file
    final bundlesPath = join(output, 'bundles', subfolder);
    final Map<String, dynamic> extensionsData =
        json.decode(await File(join(bundlesPath, 'versioning.json')).readAsString());
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
    } else {
      final githubRepositoryEnvironmentVariable = env['GITHUB_REPOSITORY'];
      if (githubRepositoryEnvironmentVariable == null) {
        // If it's not possible to determine the baseURL, using noAddToPaperbackButton will mask the field from the homepage
        // The repository can force noAddToPaperbackButton to false by adding the field to package.json
        repositoryData['noAddToPaperbackButton'] = true;
      } else {
        final split = githubRepositoryEnvironmentVariable.toLowerCase().split('/');
        // The capitalization of folder is important, using subfolder.toLowerCase() make a non working link
        repositoryData['baseURL'] =
            'https://${split[0]}.github.io/${split[1]}${(subfolder == null || subfolder == '') ? '' : '/$subfolder'}';
      }
    }

    if (noAddToPaperbackButton != null) {
      repositoryData['noAddToPaperbackButton'] = noAddToPaperbackButton;
    }

    if (repositoryLogo != null) {
      repositoryData['repositoryLogo'] = repositoryLogo;
    }

    final cacheDir = join(pwd, '.pb_cache');
    if (!Directory(cacheDir).existsSync()) {
      await Directory(cacheDir).create(recursive: true);
    }

    // Increment version number if you change the homepage.pug file
    final pugPath = join(cacheDir, 'homepage_v1.pug');
    if (!File(pugPath).existsSync()) {
      final pugResource = ResourceRegistry.resources['website_generation/homepage.pug']!;
      await pugResource.unpackAsync(pugPath);
    }

    time(prefix: 'Install pug-cli');
    final pugResult = await installJsPackage(kPugPackage, workingDirectory: pwd, global: true);
    if (pugResult.exitCode != 0) {
      stop();
      printerr(red('\nError: Could not install pug-cli'));
      printerr(pugResult.stdout);
      printerr(pugResult.stderr);
      return pugResult.exitCode;
    }
    stop();

    final optionsFile = File(join(cacheDir, 'options.json'));
    if (!optionsFile.existsSync()) {
      await optionsFile.create(recursive: true);
    }

    await optionsFile.writeAsString(json.encode(repositoryData), flush: true);

    if (!optionsFile.existsSync()) {
      printerr(red('Warning: Could not find options.json'));
      printerr(red('Skipping homepage generation\n'));
      return 2;
    }
    if (!File(pugPath).existsSync()) {
      printerr(red('Warning: Could not pug at "$pugPath"'));
      printerr(red('Skipping homepage generation\n'));
      return 2;
    }

    time(prefix: 'Compile Homepage PUG to HTML');
    try {
      final result = await runPugCompile(optionsFile.path, pugPath: pugPath);
      if (result.exitCode != 0) {
        stop();
        printerr(red('\nError: Could not compile html'));
        printerr(grey(result.stdout));
        printerr(red(result.stderr));

        return result.exitCode;
      }
    } on ProcessException catch (e) {
      stop();
      printerr(red('\nError: Could not compile html - ${e.message}'));
      printerr(red(e.toString()));
      return 1;
    } on Exception catch (e) {
      stop();
      printerr(red('\nError: Could not compile html - ${e.toString()}'));
      return 1;
    }
    stop();

    try {
      await optionsFile.delete();
    } on FileSystemException catch (e) {
      printerr(red('Warning: Could not delete options.json - ${e.message}'));
    } on Exception catch (e) {
      printerr(red('Warning: Could not delete options.json - ${e.toString()}'));
    }

    final tempIndex = File(join(bundlesPath, '${basenameWithoutExtension(pugPath)}.html'));
    await tempIndex.rename(join(bundlesPath, 'index.html'));

    homepageTimer.stop();
    print((blue('Total Homepage Generation: ${homepageTimer.elapsedMilliseconds}ms')));
    return 0;
  }

  /// The compiled js file will be saved to [pugPath].
  ///
  /// Returns the exit code of the process.
  Future<ProcessResult> runPugCompile(String optionsFile, {required String pugPath}) async {
    final dir = createTempDir();
    final bundlesDir = join(output, 'bundles', subfolder);
    if (!Directory(bundlesDir).existsSync()) {
      await Directory(bundlesDir).create(recursive: true);
    }
    final process = await Process.run(
      'pug3',
      [pugPath, '-o', bundlesDir, '-O', optionsFile, '-D'],
      // Must be true on windows,
      // otherwise this exception is thrown:
      // "The system cannot find the file specified."
      runInShell: true,
      workingDirectory: dir,
    );
    await Directory(dir).delete(recursive: true);

    return process;
  }
}
