import 'browser_client.dart';

BrowserClient createBrowserClient() => MemoryBrowserClient();

/// A non-web/test implementation. It never claims browser capabilities.
class MemoryBrowserClient extends BrowserClient {
  MemoryBrowserClient({
    this.settings,
    this.introSeen = false,
    this.persistent = true,
  });

  String? settings;
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
}
