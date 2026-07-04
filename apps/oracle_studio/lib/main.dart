import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Registers the app identity for the "start with Windows" toggle (Settings).
  launchAtStartup.setup(
    appName: 'Oracle Studio',
    appPath: Platform.resolvedExecutable,
  );

  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1000, 640),
    center: true,
    title: 'Oracle Studio',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OracleStudioApp());
}
