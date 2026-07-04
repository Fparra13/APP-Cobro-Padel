import 'package:flutter/material.dart';

/// Marca pantallas embebidas en [OrganizerShell] / [PlayerShell] para reservar
/// espacio sobre la [NavigationBar] inferior.
class NavShellScope extends InheritedWidget {
  /// Espacio extra bajo el contenido scrollable (altura útil de la barra).
  final double bottomInset;

  const NavShellScope({
    super.key,
    required this.bottomInset,
    required super.child,
  });

  static NavShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavShellScope>();
  }

  static double bottomInsetOf(BuildContext context) {
    return maybeOf(context)?.bottomInset ?? 0;
  }

  static EdgeInsets listPadding(
    BuildContext context, {
    double left = 16,
    double top = 16,
    double right = 16,
    double bottom = 16,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      bottom + bottomInsetOf(context),
    );
  }

  @override
  bool updateShouldNotify(NavShellScope oldWidget) {
    return bottomInset != oldWidget.bottomInset;
  }
}

/// Scaffold secundario dentro del shell (evita solaparse con la barra inferior).
class ShellTabScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  const ShellTabScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // primary debe ser true: el shell exterior no tiene AppBar, así que este
    // scaffold debe reservar el inset superior (status bar).
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
