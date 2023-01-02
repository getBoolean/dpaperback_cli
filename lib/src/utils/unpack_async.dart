import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart';

extension UnpackAsync on PackedResource {
  /// Unpacks a resource saving it
  /// to the file at [pathTo].
  Future<void> unpackAsync(String pathTo) async {
    if (File(pathTo).existsSync() && !FileSystemEntity.isFileSync(pathTo)) {
      throw Exception('The unpack target $pathTo must be a file');
    }
    final normalized = normalize(pathTo);
    if (!Directory(dirname(normalized)).existsSync()) {
      await Directory(dirname(normalized)).create(recursive: true);
    }

    final file = await File(normalized).open(mode: FileMode.write);

    try {
      for (final line in content.split('\n')) {
        if (line.trim().isNotEmpty) {
          await file.writeFrom(base64.decode(line));
        }
      }
    } finally {
      await file.flush();
      await file.close();
    }
  }
}
