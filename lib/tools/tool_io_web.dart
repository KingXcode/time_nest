import 'dart:convert';
import 'dart:js_interop';

import 'tool_image.dart';

@JS('shikeTools.pickImage')
external JSPromise<JSString?> _pick();
@JS('shikeTools.processImage')
external JSPromise<JSString> _process(JSString data, JSString options);
@JS('shikeTools.sampleColor')
external JSPromise<JSString> _sample(JSString data, JSNumber x, JSNumber y);
@JS('shikeTools.download')
external void _download(JSString data, JSString name);
@JS('shikeTools.readPalette')
external JSString _readPalette();
@JS('shikeTools.savePalette')
external JSBoolean _savePalette(JSString data);

Future<ToolImage?> pickToolImage() async {
  final result = await _pick().toDart;
  return result == null
      ? null
      : ToolImage.fromJson(jsonDecode(result.toDart) as Map<String, dynamic>);
}

Future<String> processToolImage(
  String data,
  Map<String, dynamic> options,
) async => (await _process(data.toJS, jsonEncode(options).toJS).toDart).toDart;
Future<String> sampleToolColor(String data, double x, double y) async =>
    (await _sample(data.toJS, x.toJS, y.toJS).toDart).toDart;
void downloadToolFile(String data, String name) =>
    _download(data.toJS, name.toJS);
List<String> readToolPalette() {
  try {
    return (jsonDecode(_readPalette().toDart) as List)
        .whereType<String>()
        .where((c) => RegExp(r'^#[0-9A-F]{6}$').hasMatch(c))
        .take(12)
        .toList();
  } catch (_) {
    return [];
  }
}

bool saveToolPalette(List<String> colors) {
  try {
    return _savePalette(jsonEncode(colors).toJS).toDart;
  } catch (_) {
    return false;
  }
}
