import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class FairestOneApp extends StatelessWidget {
  const FairestOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fairest One',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
