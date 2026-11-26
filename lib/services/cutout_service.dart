// 抠图服务：ML Kit 人体/主体分割（google_mlkit_subject_segmentation），
// 只在导入衣服时调用，平时不创建、不加载。
// 失败（没检出主体、无网络模型等）时返回 null，调用方直接用原图，绝不报错闪退。

import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CutoutService {
  CutoutService._();
  static final CutoutService instance = CutoutService._();

  SubjectSegmenter? _segmenter;

  SubjectSegmenter get _seg => _segmenter ??= SubjectSegmenter(
        options: SubjectSegmenterOptions(
          enableForegroundBitmap: true,
          // 插件文档写明 foregroundBitmap 需要同时开启置信度遮罩才返回，
          // 为稳妥起见两个都开（只多一点内存）。
          enableForegroundConfidenceMask: true,
          enableMultipleSubjects: SubjectResultOptions(
            enableConfidenceMask: false,
            enableSubjectBitmap: false,
          ),
        ),
      );

  /// 对 [imageFile] 做主体抠图，成功返回透明底 PNG 文件，失败返回 null。
  Future<File?> cutout(File imageFile) async {
    try {
      final input = InputImage.fromFilePath(imageFile.path);
      final result = await _seg.processImage(input);
      final Uint8List? bitmap = result.foregroundBitmap;
      if (bitmap == null || bitmap.isEmpty) return null;
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'wardrobe', 'cutout'));
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final out = File(p.join(
        outDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.png',
      ));
      await out.writeAsBytes(bitmap, flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _segmenter?.close();
    _segmenter = null;
  }
}
