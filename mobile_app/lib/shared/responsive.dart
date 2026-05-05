import 'package:flutter/material.dart';

/// Breakpoints
const double kMobileBreak = 600;
const double kTabletBreak = 1024;

bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < kMobileBreak;

bool isTablet(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  return w >= kMobileBreak && w < kTabletBreak;
}

bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= kTabletBreak;

/// Wraps content in a centered, max-width container on wide screens.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    if (isMobile(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
