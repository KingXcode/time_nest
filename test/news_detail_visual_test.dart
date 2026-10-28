// Deterministic Flutter rendering, not browser or iPhone acceptance testing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/news_article.dart';
import 'package:time_nest/dashboard/news_detail_screen.dart';

import 'dashboard_widget_test.dart' show FixtureDashboardClient;

void main() {
  testWidgets('news detail renders with bundled fonts and phone safe areas', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('ShikeSans', 'assets/fonts/ShikeSans-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    for (final viewport in [
      (const Size(390, 844), 1.0, 'phone'),
      (const Size(320, 568), 2.0, 'phone-large-text'),
      (const Size(1280, 800), 1.0, 'desktop'),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.$1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'ShikeSans',
              ),
              scaffoldBackgroundColor: const Color(0xFF08090B),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.$2)),
              child: child!,
            ),
            home: NewsDetailScreen(
              client: FixtureDashboardClient(),
              article: NewsArticle.fromJson(const {
                'title': '科技资讯阅读页：标题下即可打开原文，返回保留阅读位置',
                'source': '少数派',
                'sourceId': 'sspai',
                'url': 'https://sspai.com/post/100001',
                'time': 1792278000,
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['NEWS_DETAIL_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/news-detail-previews/${viewport.$3}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
