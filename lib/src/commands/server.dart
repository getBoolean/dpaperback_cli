import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/utils/time_mixin.dart';
import 'package:intranet_ip/intranet_ip.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

class Server extends Command<int> {
  final ProviderContainer container;
  Server([ProviderContainer? container]) : container = container ?? ProviderContainer() {
    argParser
      ..addSeparator('Flags:')
      ..addFlag('skip-bundle',
          help: 'Skip bundling the sources when first starting', negatable: false)
      ..addFlag(
        'homepage',
        help: 'When enabled, the homepage file be generated using pug-cli',
        negatable: true,
        defaultsTo: true,
      )
      ..addFlag('hot-restart', negatable: true, help: 'Rebuild sources on save', defaultsTo: true)
      ..addFlag('hide-ip-address',
          help: 'Hide the ip address when the server starts', negatable: false)
      ..addFlag(
        'minified-output',
        help: 'Generate minified JavaScript',
        negatable: true,
        defaultsTo: true,
      )
      ..addSeparator('Options:')
      ..addOption('subfolder',
          abbr: 'f',
          help:
              'The subfolder under "bundles" folder the generated sources will be built at and served from.',
          valueHelp: 'folder')
      ..addOption('hot-restart-throttle',
          defaultsTo: '10000',
          abbr: 'd',
          help:
              'Number of milliseconds after a hot restart was triggered in which another hot restart cannot be triggered.')
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
      ..addOption('ip', valueHelp: 'value')
      ..addOption('port', abbr: 'p', defaultsTo: '8080', valueHelp: 'value')
      ..addOption('host', valueHelp: 'ip-address', help: 'Override the host address')
      ..addOption(
        'pubspec',
        abbr: 'P',
        help: 'The path to the pubspec.yaml',
        valueHelp: 'file-path',
        defaultsTo: './pubspec.yaml',
      );
  }
  @override
  String get description => 'Build the sources and start a local server';

  @override
  String get name => 'serve';

  @override
  List<String> get aliases => ['server'];

  @override
  Future<int> run() async {
    final results = argResults;
    if (results == null) return 0;

    final output = await parseOutputPath(results);
    final target = parseTargetPath(results);
    final commonsPackage = results['paperback-extensions-common'] as String;
    final int port = int.parse(results['port']);
    final String? host = results['host'];
    final source = results['source'];
    final pubspecPath = parsePubspecPath(results);
    final enableHotRestart = results['hot-restart'] as bool;
    final hotRestartThrottleMilliseconds = int.tryParse(results['hot-restart-throttle'] as String);
    final hideIpAddress = results['hide-ip-address'] as bool;
    final subfolder = results['subfolder'] as String?;
    final shouldGenerateHomepage = results['homepage'] as bool;
    final minifiedOutput = results['minified-output'] as bool;
    if (hotRestartThrottleMilliseconds == null || hotRestartThrottleMilliseconds < 1000) {
      printerr(red('Invalid hot restart throttle value. Must be 1000 or greater'));
      return 2;
    }

    final skipBundle = results['skip-bundle'] as bool;
    if (!skipBundle) {
      await BundleCli(
        output: output,
        target: target,
        source: source,
        commonsPackage: commonsPackage,
        subfolder: subfolder,
        container: container,
        pubspecPath: pubspecPath,
        shouldGenerateHomepage: shouldGenerateHomepage,
        minifyOutput: minifiedOutput,
      ).run();
    }
    final successCode = ServerCli(
      enableHotRestart: enableHotRestart,
      hotRestartThrottleMilliseconds: hotRestartThrottleMilliseconds,
      output: output,
      target: target,
      source: source,
      port: port,
      host: host,
      commonsPackage: commonsPackage,
      container: container,
      hideIpAddress: hideIpAddress,
      pubspecPath: pubspecPath,
      subfolder: subfolder,
      shouldGenerateHomepage: shouldGenerateHomepage,
        minifyOutput: minifiedOutput,
    ).run();

    return successCode;
  }

  String parseTargetPath(ArgResults command) {
    final targetArgument = command['target'] as String;
    final targetPath = canonicalize(targetArgument);
    if (!exists(targetPath)) {
      print(red('The target directory "$targetArgument" could not be found'));
      io.exit(2);
    }

    return targetPath;
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

  Future<String> parseOutputPath(ArgResults command) async {
    final outputArgument = command['output'] as String;
    final outputPath = canonicalize(outputArgument);

    if (!exists(outputPath)) {
      await io.Directory(outputPath).create(recursive: true);
    }
    return outputPath;
  }
}

class ServerCli with CommandTime {
  final String output;
  final String target;
  final String? source;
  final String commonsPackage;
  final int port;
  final String? host;
  final ProviderContainer container;
  final bool enableHotRestart;
  final int hotRestartThrottleMilliseconds;
  final bool hideIpAddress;
  final String pubspecPath;
  final String? subfolder;
  final bool shouldGenerateHomepage;
  final bool minifyOutput;

  ServerCli({
    required this.output,
    required this.target,
    this.source,
    required this.pubspecPath,
    required this.port,
    required this.host,
    required this.commonsPackage,
    required this.container,
    required this.enableHotRestart,
    required this.hotRestartThrottleMilliseconds,
    required this.hideIpAddress,
    required this.subfolder,
    required this.shouldGenerateHomepage,
    required this.minifyOutput,
  });

  Future<int> run() async {
    if (!stdin.hasTerminal) {
      printerr(red(
          'This command requires a terminal. It cannot be run from CI such as GitHub Actions.'));
      return 1;
    }

    final bundlesPath = join(output, 'bundles', subfolder);
    final pipeline = const shelf.Pipeline()..addMiddleware(shelf.logRequests());
    final handler = pipeline.addHandler(
      createStaticHandler(
        bundlesPath,
        defaultDocument: 'index.html',
        listDirectories: false,
      ),
    );
    final ip = await intranetIpv4();
    try {
      final HttpServer server = await shelf_io.serve(handler, host ?? ip.address, port);
      printServerStarted(server);

      stdout.write(prefixTime(' :'));

      late StreamSubscription<List<int>> subscription;
      subscription = stdin.listen((event) async {
        final input = utf8.decode(event).trim();

        if (input == 'h' || input == 'help') {
          print(blue('\nHelp'));
          print('  h, help - Display this message');
          print('  q, quit - Stops the server and quits the CLI');
          print('  r, rebuild - Rebuilds the sources\n');
        } else if (input == 'quit' ||
            input == 'q' ||
            input == 'exit' ||
            input == 's' ||
            input == 'stop') {
          print('\n${blue('Stopping server...')}');
          exit(0);
        } else if (input == 'r' || input == 'restart') {
          await rebuildSources(subscription, server);
        }

        stdout.write(prefixTime(' :'));
      });

      if (enableHotRestart) {
        Watcher(join(target, source))
            .events
            .throttle(Duration(milliseconds: hotRestartThrottleMilliseconds))
            .listen((_) async {
          await rebuildSources(subscription, server);
          stdout.write(prefixTime(' :'));
        });
      }

      await subscription.asFuture();
    } on SocketException catch (e) {
      printerr(red('Error starting server: ${e.osError == null ? e.message : e.osError!.message}'));
      return 1;
    } on FileSystemException catch (e) {
      printerr(red('Error starting server: ${e.osError == null ? e.message : e.osError!.message}'));
      return 1;
    } on FormatException catch (e) {
      printerr(red('Error starting server: ${e.message}\n${e.toString()}'));
      return 1;
    } on Exception catch (e) {
      printerr(red('Error starting server: ${e.toString()}'));
      return 1;
    }

    return 0;
  }

  Future<void> rebuildSources(
      StreamSubscription<List<int>> subscription, io.HttpServer server) async {
    subscription.pause();
    // Make sure the repo is bundled
    final exitCode = await BundleCli(
      output: output,
      target: target,
      source: source,
      commonsPackage: commonsPackage,
      container: container,
      pubspecPath: pubspecPath,
      subfolder: subfolder,
      shouldGenerateHomepage: shouldGenerateHomepage,
      minifyOutput: minifyOutput,
    ).run();
    if (exitCode != 0) {
      printerr(prefixTime() + red('Failed to build sources, stopping server...'));
      exit(2);
    }
    printServerStarted(server);
    subscription.resume();
  }

  void printServerStarted(io.HttpServer server) {
    if (hideIpAddress) {
      print(blue(
          '\nStarting server at ${green('http://${'*' * 10}:${server.port}')}${enableHotRestart ? grey(' (auto hot restart enabled)') : ''}'));
    } else {
      print(blue(
          '\nStarting server at ${green('http://${server.address.host}:${server.port}')}${enableHotRestart ? grey(' (auto hot restart enabled)') : ''}'));
    }
    print('\nFor a list of commands type ${green('h')} or ${green('help')}');
  }
}

String prefixTime([String separator = '']) {
  final now = DateTime.now();
  final time =
      '[${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}:${now.millisecond.toString().padLeft(4, '0')}]$separator ';
  return grey(time);
}
