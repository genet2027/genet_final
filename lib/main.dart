import 'package:flutter/material.dart';

import 'core/config/genet_config.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GenetConfig.syncToNative();
  runApp(const GenetApp());
}

class GenetApp extends StatelessWidget {
  const GenetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Genet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
