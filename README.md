# Dart Paperback CLI

Status: **In Development**

While the majority of major tasks have been completed, there is still a number of bugs to be fixed

A commandline tool for bundling and serving Dart Paperback 0.6/0.7 extensions
using [dart_pb_extensions_common](https://github.com/getBoolean/dart_pb_extensions_common)

## Getting Started

Install the latest version as a global package via [Pub](https://pub.dev/).
The Dart global scripts directory should also be added to your path, following
[dart.dev instructions](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).
Once added to PATH, the `dpaperback` command can be used.

```bash
dart pub global activate https://github.com/getBoolean/dpaperback_cli -s git

# Or alternatively to specify a specific version (once published):
# pub global activate dpaperback_cli 0.4.1
```

Alternatively, it can be added as a dev dependency to your `pubspec.yaml` file. Use the command `dart run dpaperback_cli:dpaperback` to use the CLI. (Note the `:` in the middle)

```yaml
dev_dependencies:
  dpaperback_cli:
    git: https://github.com/getBoolean/dpaperback_cli
```

### Documentation

Documentation will be provided in the future.

### Commands

Full commands list and args can be viewed by running `dpaperback --help`.

```bash
> dpaperback --help

A commandline tool for bundling and serving Paperback extensions written in Dart

Usage: dpaperback <command> [arguments]

Global options:
-h, --help        Print this usage information.

Available commands:
  bundle          Builds all the sources in the repository and generates a versioning file
  serve           Build the sources and start a local server
  clean           Deletes the modules directory and cached dependencies

Run "dpaperback help <command>" for more information about a command.
```

## Requirements

- Dart 2.18.6 or higher on the path
- Node 14.0.0 or higher on the path
