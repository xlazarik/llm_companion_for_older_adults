import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class ImageCaptureService {
  static const int _maxDimension = 1920;
  static const int _quality = 78;

  Future<String> optimizePhoto(String sourcePath) async {
    final directory = await getTemporaryDirectory();
    final targetPath =
        '${directory.path}/captured_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: _maxDimension,
      minHeight: _maxDimension,
      quality: _quality,
      format: CompressFormat.jpeg,
    );

    final optimizedPath = compressedFile?.path ?? sourcePath;
    if (optimizedPath != sourcePath) {
      final originalFile = File(sourcePath);
      if (await originalFile.exists()) {
        await originalFile.delete();
      }
    }

    return optimizedPath;
  }
}