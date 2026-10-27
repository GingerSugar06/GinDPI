import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app/controller.dart';
import 'system/settings_store.dart';
import 'system/win_system.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  // Kaldırma sihirbazı çağırır: Windows'a yazdığımız her şeyi (PAC, DNS kuralı, görev) sil.
  if (args.contains('--cleanup')) {
    final s = await SettingsStore.load();
    await WinSystem.restorePac(s);
    await WinSystem.removeNrpt();
    await WinSystem.setLaunchAtStartup(false);
    exit(0);
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Zaten çalışıyorsa mevcut pencereyi öne getirip çık.
  final first = await SingleInstance.acquire(() async {
    await windowManager.show();
    await windowManager.focus();
  });
  if (!first) exit(0);

  final settings = await SettingsStore.load();
  final controller = AppController(settings);
  await controller.init();

  const options = WindowOptions(
    size: Size(1080, 720),
    minimumSize: Size(920, 640),
    center: true,
    title: 'GinDPI',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: P.bg,
  );
  final startHidden = args.contains('--minimized');
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    if (!startHidden) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  controller.setWindowVisible(!startHidden);

  runApp(GinApp(controller: controller));
  if (settings.autoConnect || startHidden && settings.autoConnect) controller.connect();
}

class GinApp extends StatefulWidget {
  const GinApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<GinApp> createState() => _GinAppState();
}

class _GinAppState extends State<GinApp> with WindowListener, TrayListener {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    c.addListener(_refreshTray);
    _initTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    c.removeListener(_refreshTray);
    super.dispose();
  }

  // ----------------------------------------------------------------- tepsi

  bool _lastOn = false;

  Future<void> _initTray() async {
    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('GinDPI');
    await _buildMenu();
  }

  void _refreshTray() {
    if (_lastOn != c.isOn) {
      _lastOn = c.isOn;
      _buildMenu();
      trayManager.setToolTip(c.isOn ? 'GinDPI · Korumalı' : 'GinDPI · Kapalı');
    }
  }

  Future<void> _buildMenu() => trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'GinDPI\'yı aç'),
        MenuItem(key: 'toggle', label: c.isOn ? 'Bağlantıyı kes' : 'Bağlan'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Çıkış'),
      ]));

  Future<void> _show() async {
    c.setWindowVisible(true);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'show':
        _show();
      case 'toggle':
        c.toggle();
      case 'quit':
        _quit();
    }
  }

  Future<void> _quit() async {
    await c.shutdown();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // ---------------------------------------------------------------- pencere

  @override
  void onWindowClose() async {
    if (c.settings.closeToTray) {
      c.setWindowVisible(false);
      await windowManager.hide();
    } else {
      await _quit();
    }
  }

  @override
  void onWindowMinimize() => c.setWindowVisible(false);

  @override
  void onWindowRestore() => c.setWindowVisible(true);

  @override
  void onWindowFocus() => c.setWindowVisible(true);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GinDPI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: c,
          builder: (_, _) => Shell(c: c),
        ),
      );
}

