import 'dart:convert';
import 'dart:typed_data';

class ToolImage {
  ToolImage({
    required this.name,
    required this.dataUrl,
    required this.width,
    required this.height,
    required this.sourceSize,
  });
  factory ToolImage.fromJson(Map<String, dynamic> value) => ToolImage(
    name: value['name'] as String,
    dataUrl: value['dataUrl'] as String,
    width: value['width'] as int,
    height: value['height'] as int,
    sourceSize: value['sourceSize'] as int,
  );
  final String name, dataUrl;
  final int width, height, sourceSize;
  late final Uint8List bytes = base64Decode(dataUrl.split(',').last);
}
