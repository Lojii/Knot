import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ThemeController extends GetxController {
  final themeMode = ThemeMode.system.obs;

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
  }

  String get label {
    switch (themeMode.value) {
      case ThemeMode.system:
        return 'settings.follow_system';
      case ThemeMode.light:
        return 'settings.light';
      case ThemeMode.dark:
        return 'settings.dark';
    }
  }

  IconData get icon {
    switch (themeMode.value) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }
}
