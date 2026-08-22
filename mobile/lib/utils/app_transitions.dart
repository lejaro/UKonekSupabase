import 'package:flutter/material.dart';

/// Curated suite of physics-based page transitions for uKonek.
/// Uses smooth easeOutCubic/easeOutQuart curves to avoid abrupt linear motion.
class AppPageRoute {
  /// Standard drilldown transition: slides in from the right with a subtle fade.
  static Route<T> slideRight<T>(
    Widget page, {
    Duration duration = const Duration(milliseconds: 320),
    Duration reverseDuration = const Duration(milliseconds: 260),
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final forwardCurved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final slideIn = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(forwardCurved);

        final fadeIn = Tween<double>(
          begin: 0.2,
          end: 1.0,
        ).animate(forwardCurved);

        return SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: child,
          ),
        );
      },
    );
  }

  /// Upward glide transition: moves up from bottom by 12% with a smooth opacity fade.
  /// Ideal for modal screens, setup flows, and full-screen dialogs.
  static Route<T> slideUp<T>(
    Widget page, {
    Duration duration = const Duration(milliseconds: 300),
    Duration reverseDuration = const Duration(milliseconds: 240),
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInQuart,
        );

        final slideUpAnim = Tween<Offset>(
          begin: const Offset(0.0, 0.12),
          end: Offset.zero,
        ).animate(curved);

        final fadeAnim = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(curved);

        return SlideTransition(
          position: slideUpAnim,
          child: FadeTransition(
            opacity: fadeAnim,
            child: child,
          ),
        );
      },
    );
  }

  /// Cross-fade transition for major state swaps, login/logout, and redirects.
  static Route<T> fadeThrough<T>(
    Widget page, {
    Duration duration = const Duration(milliseconds: 280),
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );

        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    );
  }
}
