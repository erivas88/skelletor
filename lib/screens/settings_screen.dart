import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_provider.dart';
import '../widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSyncEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutoSyncState();
  }

  Future<void> _loadAutoSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSyncEnabled = prefs.getBool('auto_sync') ?? false;
    });
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync', value);
    setState(() {
      _autoSyncEnabled = value;
    });
  }

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
        appBar: AppBar(title: const Text('Configuración')),
        drawer: const AppDrawer(currentRoute: '/settings'),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Dark Mode Section
            Card(
              child: SwitchListTile(
                title: const Text('Modo Oscuro'),
                subtitle: Text(isDarkMode ? 'Tema Oscuro Activo' : 'Tema Claro Activo'),
                secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
                value: isDarkMode,
                onChanged: (value) {
                  themeProvider.toggleTheme(value);
                },
              ),
            ),
            const SizedBox(height: 8),
            // Auto-Sync Section
            Card(
              child: SwitchListTile(
                title: const Text('Envío automático de datos'),
                subtitle: const Text('Enviar monitoreos en segundo plano cuando haya conexión'),
                secondary: const Icon(Icons.sync),
                value: _autoSyncEnabled,
                onChanged: _toggleAutoSync,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
