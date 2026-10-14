import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class MonitorInfo {
  /// e.g. `\\.\DISPLAY1`. Stable per GPU output while topology is unchanged.
  final String device;
  final int left;
  final int top;
  final int width;
  final int height;
  final bool primary;

  const MonitorInfo({
    required this.device,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.primary,
  });

  String get label =>
      '$device  ${width}x$height${primary ? ' (주)' : ''}';
}

class MonitorRect {
  final int x;
  final int y;
  final int w;
  final int h;
  const MonitorRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

/// Currently connected monitors, via EnumDisplayMonitors.
/// Never throws — returns empty on failure.
Future<List<MonitorInfo>> listMonitors() async {
  final out = <MonitorInfo>[];
  try {
    final cb = NativeCallable<MONITORENUMPROC>.isolateLocal(
      (int hMonitor, int hdc, Pointer lpRect, int lParam) {
        try {
          final ex = calloc<MONITORINFOEX>();
          try {
            ex.ref.monitorInfo.cbSize = sizeOf<MONITORINFOEX>();
            if (GetMonitorInfo(hMonitor, ex.cast<MONITORINFO>()) != 0) {
              final r = ex.ref.monitorInfo.rcMonitor;
              out.add(MonitorInfo(
                device: ex.ref.szDevice,
                left: r.left,
                top: r.top,
                width: r.right - r.left,
                height: r.bottom - r.top,
                primary: (ex.ref.monitorInfo.dwFlags &
                        MONITORINFOF_PRIMARY) !=
                    0,
              ));
            }
          } finally {
            calloc.free(ex);
          }
        } catch (_) {}
        return 1; // continue enumeration
      },
      exceptionalReturn: 0,
    );
    try {
      EnumDisplayMonitors(0, nullptr, cb.nativeFunction, 0);
    } finally {
      cb.close();
    }
  } catch (_) {}
  return out;
}

/// Bounding region of the selected monitors (matched by device name).
///
/// Empty [selected] means "all connected monitors".
/// Returns null when [selected] matches nothing (caller falls back to the
/// primary monitor) or when there are no monitors at all.
MonitorRect? resolveRegion(
    List<MonitorInfo> monitors, List<String> selected) {
  final targets = selected.isEmpty
      ? monitors
      : monitors.where((m) => selected.contains(m.device)).toList();
  if (targets.isEmpty) return null;
  var l = targets.first.left;
  var t = targets.first.top;
  var r = l + targets.first.width;
  var b = t + targets.first.height;
  for (final m in targets.skip(1)) {
    if (m.left < l) l = m.left;
    if (m.top < t) t = m.top;
    final mr = m.left + m.width;
    final mb = m.top + m.height;
    if (mr > r) r = mr;
    if (mb > b) b = mb;
  }
  if (r <= l || b <= t) return null;
  return MonitorRect(x: l, y: t, w: r - l, h: b - t);
}
