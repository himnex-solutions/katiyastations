import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// Extension on [BuildContext] for responsive layout helpers.
extension ResponsiveContext on BuildContext {
  /// True when width is 0–599 px (phone).
  bool get isMobile => ResponsiveBreakpoints.of(this).isMobile;

  /// True when width is 600–899 px (tablet).
  bool get isTablet => ResponsiveBreakpoints.of(this).isTablet;

  /// True when width is 900+ px (desktop / large screen).
  bool get isDesktop => ResponsiveBreakpoints.of(this).isDesktop;

  /// True when width is 600+ px (tablet or desktop).
  bool get isTabletOrDesktop =>
      ResponsiveBreakpoints.of(this).isTablet ||
      ResponsiveBreakpoints.of(this).isDesktop;

  /// Picks a value based on the current breakpoint.
  ///
  /// Falls back: tablet → desktop, mobile → tablet.
  T responsiveValue<T>({required T mobile, T? tablet, required T desktop}) {
    if (isDesktop) return desktop;
    if (isTablet) return tablet ?? desktop;
    return mobile;
  }

  /// Screen width shorthand.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Screen height shorthand.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Caps a desktop-sized dialog/panel width at the actual viewport width
  /// (minus [margin] for the dialog's own inset padding on each side) so a
  /// fixed `width: 400`-style value doesn't overflow on a phone.
  double dialogWidth(double preferred, {double margin = 48}) {
    return preferred < screenWidth - margin ? preferred : screenWidth - margin;
  }
}

/// Centers [child] and caps its width at [maxWidth] on wide screens so
/// single-column list/detail content doesn't stretch edge-to-edge on a
/// desktop/web viewport. On phones and tablets it is a transparent
/// pass-through (the constraint never bites below [maxWidth]).
///
/// Use it to wrap the scrolling body of a screen, e.g.
/// `body: ResponsiveContent(child: ListView(...))`.
class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
