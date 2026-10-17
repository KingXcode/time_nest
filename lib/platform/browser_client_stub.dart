import 'browser_client.dart';

BrowserClient createBrowserClient() => MemoryBrowserClient();

/// A non-web/test implementation. It never claims browser capabilities.
class MemoryBrowserClient extends BrowserClient {
  MemoryBrowserClient({
    this.settings,
    this.timer,
    this.introSeen = false,
    this.persistent = true,
  });

  String? settings;
  String? timer;
  bool introSeen;
  final bool persistent;
  @override
  BrowserState get state => BrowserState(storageAvailable: persistent);
  @override
  String? readSettings() => settings;
  @override
  bool writeSettings(String value) {
    settings = value;
    return true;
  }

  @override
  String? readTimer() => timer;
  @override
  bool writeTimer(String value) {
    timer = value;
    return persistent;
  }

  @override
  void armTimerSound() {}
  @override
  void playTimerSound() {}
  @override
  bool readIntroSeen() => introSeen;
  @override
  bool markIntroSeen() => introSeen = true;
  @override
  void setKeepAwake(bool enabled) {}
  @override
  void startPresentation() {}
  @override
  void toggleFullscreen() {}
  @override
  void checkForUpdate() {}
  @override
  void applyUpdate() {}
  @override
  void refreshPage() {}
}
