import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';
import 'package:intranet_ip/intranet_ip.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

class Server extends Command<int> {
  final ProviderContainer container;
  Server([ProviderContainer? container]) : container = container ?? ProviderContainer() {
    argParser
      ..addSeparator('Flags:')
      ..addFlag('skip-bundle', defaultsTo: false)
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
      ..addOption('host', valueHelp: 'ip-address', help: 'Override the host address');
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
    final skipBundle = results['skip-bundle'] as bool;
    if (!skipBundle) {
      await BundleCli(
        output: output,
        target: target,
        source: source,
        commonsPackage: commonsPackage,
        container: container,
      ).run();
    }
    final successCode = ServerCli(
      output: output,
      target: target,
      source: source,
      port: port,
      host: host,
      commonsPackage: commonsPackage,
      container: container,
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

  ServerCli({
    required this.output,
    required this.target,
    this.source,
    required this.port,
    required this.host,
    required this.commonsPackage,
    required this.container,
  });

  Future<int> run() async {
    final bundlesPath = join(output, 'bundles');
    final pipeline = const shelf.Pipeline()
      ..addMiddleware(shelf.logRequests());
    final handler = pipeline.addHandler(
      createStaticHandler(bundlesPath,
          /*defaultDocument: 'versioning.json', */ listDirectories: true),
    );
    final ip = await intranetIpv4();
    // TODO: Move server onto isolate
    final HttpServer server = await shelf_io.serve(handler, host ?? ip.address, port);
    print(blue('\nStarting server at http://${server.address.host}:${server.port}'));
    print('\nFor a list of commands type ${green('h')} or ${green('help')}');

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
        subscription.pause();
        // Make sure the repo is bundled
        final exitCode = await BundleCli(
          output: output,
          target: target,
          source: source,
          commonsPackage: commonsPackage,
          container: container,
        ).run();
        if (exitCode != 0) {
          printerr(prefixTime() + red('Failed to build sources, stopping server...'));
          exit(2);
        }
        print('\n${blue('Starting server at http://${server.address.host}:${server.port}')}');
        print('\nFor a list of commands type ${green('h')} or ${green('help')}');
        subscription.resume();
      }

      stdout.write(prefixTime(' :'));
    });

    await subscription.asFuture();

    return 0;
  }
}

String prefixTime([String separator = '']) {
  final now = DateTime.now();
  final time =
      '[${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}:${now.millisecond.toString().padLeft(4, '0')}]$separator ';
  return grey(time);
}
