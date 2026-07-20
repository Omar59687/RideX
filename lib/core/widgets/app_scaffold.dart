import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.showBack = true,
    this.maxContentWidth = 560,
    this.extendBodyBehindAppBar = false,
  });

  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showBack;
  final double maxContentWidth;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: title == null
          ? null
          : AppBar(
              automaticallyImplyLeading: showBack,
              title: Text(title!),
              actions: actions,
              scrolledUnderElevation: 0,
            ),
      body: SafeArea(
        bottom: bottomNavigationBar == null,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: body,
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
