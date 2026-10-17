import 'tool_image.dart';

Future<ToolImage?> pickToolImage() async =>
    throw const FormatException('图片选择目前仅支持网页版');
Future<String> processToolImage(
  String data,
  Map<String, dynamic> options,
) async => throw const FormatException('图片处理目前仅支持网页版');
Future<String> sampleToolColor(String data, double x, double y) async =>
    throw const FormatException('图片取色目前仅支持网页版');
void downloadToolFile(String data, String name) =>
    throw const FormatException('文件保存目前仅支持网页版');
List<String> readToolPalette() => [];
bool saveToolPalette(List<String> colors) => false;
