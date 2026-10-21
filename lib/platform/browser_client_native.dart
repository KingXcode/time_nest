import 'browser_client.dart';
import 'browser_client_stub.dart';
import 'native_runtime.dart';

BrowserClient createBrowserClient() => NativeRuntime.current == null
    ? MemoryBrowserClient()
    : MacBrowserClient(NativeRuntime.current!);

class MacBrowserClient extends BrowserClient {
  MacBrowserClient(this.runtime) {
    runtime.addListener(notifyListeners);
  }
  final NativeRuntime runtime;
  @override
  BrowserState get state => BrowserState.fromJson({
    ...runtime.hostState,
    'nativeApp': true,
    'standalone': true,
    'storageAvailable': runtime.store.available,
    'offlineStatus': 'ready',
  });
  @override
  String? readSettings() => runtime.store.read('shike.settings.v1');
  @override
  bool writeSettings(String value) => runtime.write('shike.settings.v1', value);
  @override
  String? readTimer() => runtime.store.read('shike.timer.v1');
  @override
  bool writeTimer(String value) => runtime.write('shike.timer.v1', value);
  @override
  bool readIntroSeen() => runtime.store.read('shike.intro.v1') == '1';
  @override
  bool markIntroSeen() => runtime.write('shike.intro.v1', '1');
  @override
  void armTimerSound() {}
  @override
  void playTimerSound() => runtime.host('playSound');
  @override
  void setKeepAwake(bool enabled) => runtime.host('keepAwake', enabled);
  @override
  void startPresentation() => runtime.host('presentation');
  @override
  void toggleFullscreen() => runtime.host('fullscreen');
  // Native packages require a signed app release; browser updates cannot update them.
  @override
  void checkForUpdate() {}
  @override
  void applyUpdate() {}
  @override
  void refreshPage() {}
  @override
  void dispose() {
    runtime.removeListener(notifyListeners);
    setKeepAwake(false);
    super.dispose();
  }
}
