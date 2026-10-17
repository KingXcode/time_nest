import 'package:flutter/foundation.dart';

import 'browser_client_stub.dart'
    if (dart.library.js_interop) 'browser_client_web.dart'
    as implementation;

class BrowserState {
  const BrowserState({
    this.visible = true,
    this.resumeSerial = 0,
    this.storageAvailable = true,
    this.wakeSupported = false,
    this.wakeStatus = 'unsupported',
    this.fullscreenSupported = false,
    this.fullscreen = false,
    this.fullscreenError = false,
    this.standalone = false,
    this.offlineStatus = 'unavailable',
    this.offlineCompleted = 0,
    this.offlineTotal = 0,
    this.updateAvailable = false,
    this.updateError = false,
    this.secureContext = false,
  });

  factory BrowserState.fromJson(Map<String, dynamic> json) => BrowserState(
    visible: json['visible'] != false,
    resumeSerial: (json['resumeSerial'] as num?)?.toInt() ?? 0,
    storageAvailable: json['storageAvailable'] != false,
    wakeSupported: json['wakeSupported'] == true,
    wakeStatus: json['wakeStatus'] as String? ?? 'unsupported',
    fullscreenSupported: json['fullscreenSupported'] == true,
    fullscreen: json['fullscreen'] == true,
    fullscreenError: json['fullscreenError'] == true,
    standalone: json['standalone'] == true,
    offlineStatus: json['offlineStatus'] as String? ?? 'unavailable',
    offlineCompleted: (json['offlineCompleted'] as num?)?.toInt() ?? 0,
    offlineTotal: (json['offlineTotal'] as num?)?.toInt() ?? 0,
    updateAvailable: json['updateAvailable'] == true,
    updateError: json['updateError'] == true,
    secureContext: json['secureContext'] == true,
  );

  final bool visible;
  final int resumeSerial;
  final bool storageAvailable;
  final bool wakeSupported;
  final String wakeStatus;
  final bool fullscreenSupported;
  final bool fullscreen;
  final bool fullscreenError;
  final bool standalone;
  final String offlineStatus;
  final int offlineCompleted;
  final int offlineTotal;
  final bool updateAvailable;
  final bool updateError;
  final bool secureContext;

  String get wakeLabel => switch (wakeStatus) {
    'active' => '常亮已开启',
    'requesting' => '正在申请常亮',
    'released' => '常亮被系统释放',
    'failed' => '常亮申请失败',
    'off' => '常亮未开启',
    _ => '此浏览器不支持常亮',
  };

  String get offlineLabel => switch (offlineStatus) {
    'ready' => '离线资源已就绪',
    'checking' =>
      offlineTotal > 0
          ? '正在准备离线资源 · $offlineCompleted/$offlineTotal 项'
          : '正在准备离线资源',
    'failed' => '离线缓存失败，可联网重试',
    _ => '离线尚未就绪（需发布构建与 HTTPS）',
  };
}

abstract class BrowserClient extends ChangeNotifier {
  BrowserState get state;
  String? readSettings();
  bool writeSettings(String settings);
  String? readTimer();
  bool writeTimer(String value);
  void armTimerSound();
  void playTimerSound();
  bool readIntroSeen();
  bool markIntroSeen();
  void setKeepAwake(bool enabled);
  void startPresentation();
  void toggleFullscreen();
  void checkForUpdate();
  void applyUpdate();
}

BrowserClient createBrowserClient() => implementation.createBrowserClient();
