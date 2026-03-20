import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/app_drawer.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/monitoreos');
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentRoute: '/settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: Text(isDarkMode ? 'Dark Theme Active' : 'Light Theme Active'),
              secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
              value: isDarkMode,
              onChanged: (value) {
                themeProvider.toggleTheme(value);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
}
