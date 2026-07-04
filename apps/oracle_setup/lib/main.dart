import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/wizard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

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
      title: 'Oracle AI — Instalação',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6CF0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SetupWizard(),
    );
  }
}
