import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import 'package:zxing_lib/qrcode.dart' as zx;
import 'package:zxing_lib/common.dart' as zx;
import 'package:zxing_lib/zxing.dart' as zx;

import 'tool_image.dart';
import 'tool_io.dart';
import 'tool_logic.dart';
import 'tool_widgets.dart';

String fileSize(int size) => size >= 1024 * 1024
    ? '${(size / 1024 / 1024).toStringAsFixed(2)} MB'
    : '${(size / 1024).toStringAsFixed(1)} KB';
Uint8List dataBytes(String data) => base64Decode(data.split(',').last);

class ImageTool extends StatefulWidget {
  const ImageTool({super.key});
  @override
  State<ImageTool> createState() => _ImageToolState();
}

class _ImageToolState extends ToolState<ImageTool> {
  ToolImage? image;
  final width = TextEditingController(), height = TextEditingController();
  String crop = '不裁剪', format = 'JPEG', output = '', outputFormat = 'JPEG';
  double quality = .85;
  bool linked = true;
  double get ratio => switch (crop) {
    '正方形 1:1' => 1,
    '横向 16:9' => 16 / 9,
    '竖向 9:16' => 9 / 16,
    _ => image == null ? 1 : image!.width / image!.height,
  };
  @override
  void dispose() {
    width.dispose();
    height.dispose();
    super.dispose();
  }

  void choose() => performAsync(() async {
    final picked = await pickToolImage();
    if (picked == null || !mounted) return;
    setState(() {
      image = picked;
      width.text = '${picked.width}';
      height.text = '${picked.height}';
      crop = '不裁剪';
      output = '';
      result = '';
      linked = true;
    });
  });
  void dimensions(bool changingWidth) {
    setState(() {
      output = '';
      if (!linked) return;
      final n = int.tryParse(changingWidth ? width.text : height.text);
      if (n == null || n < 1 || n > 2048) return;
      if (changingWidth) {
        final h = (n / ratio).round();
        if (h > 2048) {
          height.text = '2048';
          width.text = '${(2048 * ratio).round().clamp(1, 2048)}';
        } else {
          height.text = '${h.clamp(1, 2048)}';
        }
      } else {
        final w = (n * ratio).round();
        if (w > 2048) {
          width.text = '2048';
          height.text = '${(2048 / ratio).round().clamp(1, 2048)}';
        } else {
          width.text = '${w.clamp(1, 2048)}';
        }
      }
    });
  }

  void process() => performAsync(() async {
    final w = int.tryParse(width.text), h = int.tryParse(height.text);
    if (w == null || h == null || w < 1 || h < 1 || w > 2048 || h > 2048) {
      throw const FormatException('输出宽高须为 1～2048 像素');
    }
    final selectedFormat = format;
    final selectedCrop = crop;
    final selectedQuality = quality;
    final data = await processToolImage(image!.dataUrl, {
      'width': w,
      'height': h,
      'ratio': crop == '不裁剪' ? 0 : ratio,
      'format': format,
      'quality': quality,
    });
    if (mounted &&
        width.text == '$w' &&
        height.text == '$h' &&
        format == selectedFormat &&
        crop == selectedCrop &&
        quality == selectedQuality) {
      setState(() {
        output = data;
        outputFormat = selectedFormat;
        result =
            '$w × $h · $selectedFormat · ${fileSize(dataBytes(data).length)}';
      });
    }
  });
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '轻量处理，方便分享',
      children: [
        toolAction(
          busy ? '处理中…' : '选择图片',
          busy ? null : choose,
          icon: Icons.add_photo_alternate_outlined,
        ),
        const SizedBox(height: 12),
        const Text(
          'PNG / JPEG / WebP，最大 32 MB。大图先按比例缩至最长边 2048 像素；不会修改原文件。',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        if (image != null) ...[
          const SizedBox(height: 18),
          Text(
            '${image!.name}\n原文件 ${fileSize(image!.sourceSize)} · 处理尺寸 ${image!.width} × ${image!.height}',
          ),
          const SizedBox(height: 18),
          toolChoice(
            '居中裁剪',
            crop,
            ['不裁剪', '正方形 1:1', '横向 16:9', '竖向 9:16'],
            (v) => setState(() {
              crop = v;
              linked = true;
              output = '';
              final source = image!;
              final w =
                  (source.width / source.height > ratio
                          ? source.height * ratio
                          : source.width)
                      .round();
              width.text = '$w';
              height.text = '${(w / ratio).round()}';
            }),
          ),
          toolField(
            width,
            '输出宽度（像素）',
            keyboard: TextInputType.number,
            onChanged: (_) => dimensions(true),
          ),
          toolField(
            height,
            '输出高度（像素）',
            keyboard: TextInputType.number,
            onChanged: (_) => dimensions(false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('保持比例'),
            value: linked,
            onChanged: (v) => setState(() {
              linked = v;
              output = '';
              if (v) dimensions(true);
            }),
          ),
          toolChoice(
            '导出格式',
            format,
            ['JPEG', 'PNG'],
            (v) => setState(() {
              format = v;
              output = '';
            }),
          ),
          if (format == 'JPEG') ...[
            Text('图片质量 ${(quality * 100).round()}% · 透明区域填白'),
            Slider(
              value: quality,
              min: .1,
              max: 1,
              divisions: 18,
              label: '${(quality * 100).round()}%',
              onChanged: (v) => setState(() {
                quality = v;
                output = '';
              }),
            ),
          ],
          toolAction(
            busy ? '处理中…' : '生成预览',
            busy ? null : process,
            icon: Icons.auto_fix_high_outlined,
          ),
        ],
      ],
    ),
    output: ToolResult(
      value: output.isEmpty ? '' : result,
      error: error,
      child: image == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    output.isEmpty ? image!.bytes : dataBytes(output),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(output.isEmpty ? '选择参数后生成预览，再保存图片。' : result),
                if (output.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  toolAction(
                    '保存图片',
                    () => perform(() {
                      downloadToolFile(
                        output,
                        'time-nest-image.${outputFormat == 'JPEG' ? 'jpg' : 'png'}',
                      );
                      return result;
                    }),
                    icon: Icons.download_outlined,
                  ),
                ],
              ],
            ),
    ),
  );
}

class ColorTool extends StatefulWidget {
  const ColorTool({super.key});
  @override
  State<ColorTool> createState() => _ColorToolState();
}

class _ColorToolState extends ToolState<ColorTool> {
  final hex = TextEditingController(text: '#9AE3CF'),
      red = TextEditingController(text: '154'),
      green = TextEditingController(text: '227'),
      blue = TextEditingController(text: '207');
  late List<String> palette = readToolPalette();
  int color = 0x9AE3CF;
  ToolImage? image;
  @override
  void dispose() {
    for (final c in [hex, red, green, blue]) {
      c.dispose();
    }
    super.dispose();
  }

  void applyColor(int value) {
    color = value;
    hex.text = hexText(value);
    red.text = '${(value >> 16) & 255}';
    green.text = '${(value >> 8) & 255}';
    blue.text = '${value & 255}';
    result = '${hex.text}\nRGB(${red.text}, ${green.text}, ${blue.text})';
  }

  void choose() => performAsync(() async {
    final picked = await pickToolImage();
    if (picked != null && mounted) setState(() => image = picked);
  });
  void sample(Offset point, Size size) => performAsync(() async {
    final value = await sampleToolColor(
      image!.dataUrl,
      point.dx / size.width,
      point.dy / size.height,
    );
    if (mounted) setState(() => applyColor(hexColor(value)));
  });
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '找到刚好喜欢的颜色',
      children: [
        toolField(hex, 'HEX 颜色', hint: '#9AE3CF 或 #ABC', maxLength: 7),
        toolAction(
          'HEX 转 RGB',
          () => perform(() {
            applyColor(hexColor(hex.text));
            return result;
          }),
          icon: Icons.palette_outlined,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: toolField(red, 'R', keyboard: TextInputType.number),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: toolField(green, 'G', keyboard: TextInputType.number),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: toolField(blue, 'B', keyboard: TextInputType.number),
            ),
          ],
        ),
        toolAction(
          'RGB 转 HEX',
          () => perform(() {
            final channels = [
              red,
              green,
              blue,
            ].map((c) => int.tryParse(c.text)).toList();
            if (channels.any((v) => v == null || v < 0 || v > 255)) {
              throw const FormatException('RGB 每个通道须为 0～255 的整数');
            }
            applyColor(channels[0]! << 16 | channels[1]! << 8 | channels[2]!);
            return result;
          }),
          icon: Icons.swap_horiz,
        ),
        const SizedBox(height: 24),
        toolAction(
          busy ? '读取中…' : '从图片取色',
          busy ? null : choose,
          icon: Icons.image_search_outlined,
        ),
        if (image != null) ...[
          const SizedBox(height: 12),
          const Text('轻点图片取色；透明区域按白色背景计算。'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, box) {
              final size = Size(
                box.maxWidth,
                box.maxWidth * image!.height / image!.width,
              );
              return GestureDetector(
                // A semantic tap has no pixel position and is synthesized at
                // the image center. Keep pointer coordinates for image picking;
                // HEX/RGB fields provide the keyboard-accessible alternative.
                excludeFromSemantics: true,
                onTapUp: busy
                    ? null
                    : (details) => sample(details.localPosition, size),
                child: Image.memory(
                  image!.bytes,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.fill,
                ),
              );
            },
          ),
        ],
      ],
    ),
    output: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolResult(
          value: result.isEmpty ? '#9AE3CF\nRGB(154, 227, 207)' : result,
          error: error,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | color),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                '${hexText(color)}\nRGB(${(color >> 16) & 255}, ${(color >> 8) & 255}, ${color & 255})',
                style: const TextStyle(fontSize: 20, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => perform(() {
            final value = hexText(color);
            palette = [
              value,
              ...palette.where((c) => c != value),
            ].take(12).toList();
            if (!saveToolPalette(palette)) {
              throw const FormatException('颜色仅保留在当前页面，本地保存不可用');
            }
            return result;
          }),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('保存到常用颜色'),
        ),
        if (palette.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('常用颜色 · 最多 12 个'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: palette
                .map(
                  (c) => InputChip(
                    avatar: CircleAvatar(
                      backgroundColor: Color(0xFF000000 | hexColor(c)),
                    ),
                    label: Text(c),
                    onPressed: () => setState(() => applyColor(hexColor(c))),
                    onDeleted: () => perform(() {
                      palette.remove(c);
                      if (!saveToolPalette(palette)) {
                        throw const FormatException('无法保存变更');
                      }
                      return result;
                    }),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    ),
  );
}

QrImage makeQr(String text) {
  if (text.trim().isEmpty) throw const FormatException('请输入文字或网址');
  if (utf8.encode(text).length > 1500) {
    throw const FormatException('内容较长，请限制在 1500 字节以内');
  }
  return QrImage(
    QrCode(
      payload: QrPayload()
        ..addECI(QrEciValue.utf8)
        ..addString(text),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );
}

class QrPainter extends CustomPainter {
  QrPainter(this.qr);
  final QrImage qr;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final cell = size.width / (qr.moduleCount + 8),
        paint = Paint()
          ..color = Colors.black
          ..isAntiAlias = false;
    for (var y = 0; y < qr.moduleCount; y++) {
      for (var x = 0; x < qr.moduleCount; x++) {
        if (qr.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH((x + 4) * cell, (y + 4) * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.qr != qr;
}

Future<Uint8List> qrPng(QrImage qr) async {
  final side = (qr.moduleCount + 8) * 8;
  final recorder = ui.PictureRecorder();
  QrPainter(qr).paint(Canvas(recorder), Size.square(side.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<String> readQr(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    final rgba = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List();
    final pixels = Int32List(image.width * image.height);
    for (var p = 0; p < pixels.length; p++) {
      final i = p * 4, a = rgba[i + 3] / 255;
      final r = (rgba[i] * a + 255 * (1 - a)).round(),
          g = (rgba[i + 1] * a + 255 * (1 - a)).round(),
          b = (rgba[i + 2] * a + 255 * (1 - a)).round();
      pixels[p] = (r << 16) | (g << 8) | b;
    }
    final bitmap = zx.BinaryBitmap(
      zx.HybridBinarizer(
        zx.RGBLuminanceSource(image.width, image.height, pixels),
      ),
    );
    return zx.QRCodeReader().decode(bitmap).text;
  } catch (_) {
    throw const FormatException('没有识别到二维码，请选择清晰、完整的二维码图片');
  } finally {
    image.dispose();
  }
}

class QrTool extends StatefulWidget {
  const QrTool({super.key});
  @override
  State<QrTool> createState() => _QrToolState();
}

class _QrToolState extends ToolState<QrTool> {
  final input = TextEditingController();
  QrImage? qr;
  String generatedText = '';
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void scan() => performAsync(() async {
    final image = await pickToolImage();
    if (image == null) return;
    final text = await readQr(image.bytes);
    if (mounted) {
      setState(() {
        result = text;
        qr = null;
      });
    }
  });
  @override
  Widget build(BuildContext context) => ToolSplit(
    input: ToolSection(
      title: '文字与网址，轻松传递',
      children: [
        toolField(
          input,
          '二维码内容',
          hint: '输入文字或 https:// 网址',
          lines: 4,
          maxLength: 1500,
        ),
        toolAction(
          '生成二维码',
          () => perform(() {
            qr = makeQr(input.text);
            generatedText = input.text;
            return input.text;
          }),
          icon: Icons.qr_code_2_rounded,
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        toolAction(
          busy ? '识别中…' : '选择图片识别',
          busy ? null : scan,
          icon: Icons.document_scanner_outlined,
        ),
        const SizedBox(height: 12),
        const Text(
          '识别结果仅显示为文本，不会自动打开链接。',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    ),
    output: ToolResult(
      value: result,
      error: error,
      child: qr == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(painter: QrPainter(qr!)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(generatedText),
                const SizedBox(height: 16),
                toolAction(
                  busy ? '准备中…' : '保存二维码',
                  busy
                      ? null
                      : () => performAsync(() async {
                          final png = await qrPng(qr!);
                          if (mounted) {
                            downloadToolFile(
                              'data:image/png;base64,${base64Encode(png)}',
                              'time-nest-qr.png',
                            );
                          }
                        }),
                  icon: Icons.download_outlined,
                ),
              ],
            ),
    ),
  );
}
