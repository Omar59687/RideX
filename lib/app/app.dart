import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
import 'package:ridex/core/widgets/app_error_view.dart';

class RideXApp extends ConsumerWidget {
  const RideXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appearanceThemeModeProvider);
    return MaterialApp.router(
      title: 'RideX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class RideXInitializationFailureApp extends StatelessWidget {
  const RideXInitializationFailureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: AppErrorView(
              title: 'Unable to start RideX',
              message: 'RideX could not start safely. Please contact support.',
            ),
          ),
        ),
      ),
    );
  }
}
