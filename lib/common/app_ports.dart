import 'package:fl_clash/common/provider_reader.dart';
import 'package:fl_clash/models/models.dart';

/// The desktop window, as the action layer needs it. `common/window.dart`
/// implements this; nothing else may, and no consumer of these interfaces
/// imports `window_manager` to reach them.
abstract interface class WindowPort {
  Future<void> show();

  Future<void> hide();

  Future<void> close();

  Future<bool> get isVisible;

  void forceExit();
}

/// The system tray, as the action layer needs it. `common/tray.dart`
/// implements this.
abstract interface class TrayPort {
  Future<void> shutdown();

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  });
}

/// The navigable pages, as the provider layer needs them. `views/navigation.dart`
/// implements this; the items carry a `WidgetBuilder`, so the table has to be
/// built by the layer that owns the widgets rather than handed down to it.
abstract interface class NavigationPort {
  List<NavigationItem> getItems({bool openLogs, bool hasProxies});
}

/// Bound once by the app layer, which is the only place that may import the
/// platform modules and the view tree. They stay null on a host without a
/// desktop shell, and in tests, where every call through them is a no-op.
WindowPort? windowPort;
TrayPort? trayPort;
NavigationPort? navigationPort;
