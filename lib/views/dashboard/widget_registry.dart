import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:fl_clash/widgets/widgets.dart';

/// Maps the persisted [DashboardWidget] names onto the widgets that render
/// them.
///
/// The enum is stored in the app settings, so it has to stay a plain data type;
/// keeping the widget on it put every dashboard card in the compile graph of
/// anything that imported `lib/enum/enum.dart`.
extension DashboardWidgetView on DashboardWidget {
  GridItem get widget => switch (this) {
    DashboardWidget.networkSpeed => const GridItem(
      crossAxisCellCount: 8,
      child: NetworkSpeed(),
    ),
    DashboardWidget.outboundModeV2 => const GridItem(
      crossAxisCellCount: 8,
      child: OutboundModeV2(),
    ),
    DashboardWidget.outboundMode => const GridItem(
      crossAxisCellCount: 4,
      child: OutboundMode(),
    ),
    DashboardWidget.trafficUsage => const GridItem(
      crossAxisCellCount: 4,
      child: TrafficUsage(),
    ),
    DashboardWidget.networkDetection => const GridItem(
      crossAxisCellCount: 4,
      child: NetworkDetection(),
    ),
    DashboardWidget.tunButton => const GridItem(
      crossAxisCellCount: 4,
      child: TUNButton(),
    ),
    DashboardWidget.vpnButton => const GridItem(
      crossAxisCellCount: 4,
      child: VpnButton(),
    ),
    DashboardWidget.systemProxyButton => const GridItem(
      crossAxisCellCount: 4,
      child: SystemProxyButton(),
    ),
    DashboardWidget.intranetIp => const GridItem(
      crossAxisCellCount: 4,
      child: IntranetIP(),
    ),
    DashboardWidget.memoryInfo => const GridItem(
      crossAxisCellCount: 4,
      child: MemoryInfo(),
    ),
  };
}

/// The reverse of [DashboardWidgetView.widget].
///
/// Every branch above returns a canonical const, so the grid's own children
/// compare equal to them by identity.
DashboardWidget dashboardWidgetOf(GridItem gridItem) {
  return DashboardWidget.values.firstWhere((item) => item.widget == gridItem);
}
