// ignore_for_file: deprecated_member_use
// Uses tray_manager's 0.5.x-compat API (stable) instead of the new native API.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'capture_service.dart';

/// System-tray residence: hide-on-close, tray menu, click-to-toggle.
///
/// Close (X) hides to tray; real exit happens only via tray menu → 종료.
/// If tray setup fails, prevent-close is never armed so the window
/// keeps working normally.
class TrayService with TrayListener, WindowListener {
  final CaptureService svc;

  TrayService(this.svc);

  Future<void> init() async {
    try {
      await trayManager.setIcon(_iconPath());
      await trayManager.setToolTip('VTT - 오늘 타임라인');
      await _refreshMenu();
      trayManager.addListener(this);
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      svc.addListener(_onSvcChanged);
    } catch (_) {}
  }

  String _iconPath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(
        exeDir, 'data', 'flutter_assets', 'assets', 'tray_icon.ico');
  }

  void _onSvcChanged() {
    unawaited(_refreshMenu());
  }

  Future<void> _refreshMenu() async {
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '열기'),
        MenuItem(
            key: 'record',
            label: svc.running ? '녹화 중지' : '녹화 시작'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '종료'),
      ]));
    } catch (_) {}
  }

  Future<void> _toggleWindow() async {
    try {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggleWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(() async {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        }());
        break;
      case 'record':
        unawaited(() async {
          try {
            if (svc.running) {
              await svc.stop();
            } else {
              await svc.start();
            }
          } catch (_) {}
        }());
        break;
      case 'exit':
        unawaited(shutdown());
        break;
    }
  }

  @override
  void onWindowClose() async {
    try {
      if (await windowManager.isPreventClose()) {
        await windowManager.hide();
      }
    } catch (_) {}
  }

  Future<void> shutdown() async {
    try {
      await svc.stop();
    } catch (_) {}
    dispose();
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
  }

  void dispose() {
    try {
      svc.removeListener(_onSvcChanged);
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      unawaited(trayManager.destroy());
    } catch (_) {}
  }
}
