import 'package:flutter/foundation.dart';

/// Centralized navigation state and tab switcher for the App Shell.
/// Decouples child pages from requiring a direct dependency on `uKonekMainShellPage`.
class ShellNavigation {
  ShellNavigation._();

  static const int tabDashboard = 0;
  static const int tabMedicineScheduler = 1;
  static const int tabQueue = 2;
  static const int tabProfile = 3;

  /// Notifier for the currently active tab index in the shell.
  static final ValueNotifier<int> currentTab = ValueNotifier<int>(tabDashboard);

  /// Event trigger for newly issued prescription checks.
  static final ValueNotifier<int> prescriptionAlertTrigger = ValueNotifier<int>(0);

  /// Switch to a target tab in the shell.
  static void switchTab(int index) {
    if (currentTab.value != index) {
      currentTab.value = index;
    }
  }

  /// Request an immediate check for newly issued prescriptions.
  static void checkPrescriptions() {
    prescriptionAlertTrigger.value++;
  }
}
