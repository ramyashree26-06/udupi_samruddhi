import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'theme.dart';

/// Taking or choosing a picture (dish photo, purchase slip).
/// Phone: camera or gallery. Windows: a file chooser.
class Pics {
  static bool get hasCamera => Platform.isAndroid || Platform.isIOS;

  /// Returns the saved picture path, or null if cancelled.
  static Future<String?> pick(BuildContext context, String prefix) async {
    ImageSource? src = ImageSource.gallery;
    if (hasCamera) {
      src = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (src == null) return null;
    try {
      final x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1600, imageQuality: 80);
      if (x == null) return null;
      final dir = Directory(p.join(Db.baseDir, 'pictures'));
      await dir.create(recursive: true);
      var ext = p.extension(x.path);
      if (ext.isEmpty) ext = '.jpg';
      final dest = p.join(
          dir.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(x.path).copy(dest);
      return dest;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not get the picture: $e')));
      }
      return null;
    }
  }
}

/// Shows a saved picture file (a grey icon if the file is missing).
Widget fileImage(String path,
    {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  if (path.isEmpty || !File(path).existsSync()) {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: Icon(Icons.image_not_supported_outlined, color: kMuted)),
    );
  }
  return Image.file(File(path), width: width, height: height, fit: fit);
}
