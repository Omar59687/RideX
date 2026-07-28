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
    this.padding,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.useSafeArea = true,
  });

  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showBack;
  final double maxContentWidth;
  final bool extendBodyBehindAppBar;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(
              automaticallyImplyLeading: showBack,
              title: Text(title!),
              actions: actions,
              scrolledUnderElevation: 0,
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 600
              ? AppSpacing.xxl
              : constraints.maxWidth < 360
                  ? AppSpacing.md
                  : AppSpacing.lg;
          final content = Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: padding ??
                    EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: body,
              ),
            ),
          );
          if (!useSafeArea) return content;
          return SafeArea(
            bottom: bottomNavigationBar == null,
            child: content,
          );
        },
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
