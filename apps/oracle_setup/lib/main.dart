import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:window_manager/window_manager.dart';

import 'src/core/brand.dart';
import 'src/wizard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Single instance: opening the installer again focuses the running one.
  final primary = await SingleInstance.ensureSingle(49678, 'oracle-setup-v1',
      onActivate: () async {
    await windowManager.show();
    await windowManager.focus();
  });
  if (!primary) exit(0);

  const options = WindowOptions(
    size: Size(960, 700),
    minimumSize: Size(860, 620),
    center: true,
    title: 'Oracle AI — Instalação',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OracleSetupApp());
}

class OracleSetupApp extends StatelessWidget {
  const OracleSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oracle AI Setup',
      debugShowCheckedModeBanner: false,
      theme: OracleBrand.theme(),
      home: const SetupWizard(),
    );
  }
}
