import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';

class EnviarDatosScreen extends StatefulWidget {
  const EnviarDatosScreen({super.key});

  @override
  State<EnviarDatosScreen> createState() => _EnviarDatosScreenState();
}

class _EnviarDatosScreenState extends State<EnviarDatosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _recordsPending = [];
  List<Map<String, dynamic>> _recordsSent = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final pendingData = await _dbHelper.getPendingToSendMonitoreos();
    final sentData = await _dbHelper.getSentMonitoreos();
    
    setState(() {
      _recordsPending = pendingData;
      _recordsSent = sentData;
      _isLoading = false;
      _selectedIds.clear();
    });
  }

  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';
    debugPrint(logMessage);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sync_log.txt');
      await file.writeAsString('$logMessage\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('🚨 Error writing log: $e');
    }
  }

  /// Converts an image to Base64 with prefix.
  /// NOTE: For actual JPEG compression, packages like 'flutter_image_compress' or 'image' are recommended.
  Future<String?> _compressAndEncodeImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      await _log('⚠️ Error encoding image ($path): $e');
      return null;
    }
  }

  Future<void> _enviarDatosSeleccionados() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona al menos un registro.')),
      );
      return;
    }

    await _log('🚀 [SYNC] Iniciando envío de ${_selectedIds.length} monitoreos al servidor...');
    
    // Loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay una configuración de API activa.');

      // --- DYNAMIC ENDPOINT RESOLUTION ---
      final endpoints = await _dbHelper.getEndpoints();
      String? dynamicEndpoint;
      
      // Search for an endpoint containing 'sync' or 'monit'
      for (var ep in endpoints) {
        String name = (ep['nombre'] ?? '').toLowerCase();
        if (name.contains('sync') || name.contains('monit')) {
          dynamicEndpoint = ep['nombre'];
          break;
        }
      }

      if (dynamicEndpoint == null) {
        throw Exception('No se encontró un endpoint dinámico para sincronización en la base de datos.');
      }

      final baseUrl = config['url'];
      final syncUrl = baseUrl.endsWith('/') ? '$baseUrl$dynamicEndpoint' : '$baseUrl/$dynamicEndpoint';
      
      await _log('🌐 [SYNC] POST Request dirigida a: $syncUrl');

      // --- PAYLOAD CONSTRUCTION ---
      final List<Map<String, dynamic>> payloadList = [];
      
      for (var record in _recordsPending) {
        if (_selectedIds.contains(record['id'])) {
          await _log('📦 [SYNC] Procesando registro ID: ${record['id']} para envío...');
          
          final fotoPath = await _compressAndEncodeImage(record['foto_path']);
          final fotoMulti = await _compressAndEncodeImage(record['foto_multiparametro']);
          final fotoTurb = await _compressAndEncodeImage(record['foto_turbiedad']);

          payloadList.add({
            "id": record['id'],
            "device_id": "MOBILE-DATA",
            "programa_id": record['programa_id'],
            "estacion_id": record['estacion_id'],
            "fecha_hora": record['fecha_hora'],
            "monitoreo_fallido": record['monitoreo_fallido'],
            "observacion": record['observacion'],
            "matriz_id": record['matriz_id'],
            "equipo_multi_id": record['equipo_multi_id'],
            "turbidimetro_id": record['turbidimetro_id'],
            "metodo_id": record['metodo_id'],
            "hidroquimico": record['hidroquimico'],
            "isotopico": record['isotopico'],
            "cod_laboratorio": record['cod_laboratorio'],
            "usuario_id": record['usuario_id'],
            "is_draft": 0,
            "equipo_nivel_id": record['equipo_nivel_id'],
            "tipo_pozo": record['tipo_pozo'],
            "fecha_hora_nivel": record['fecha_hora_nivel'],
            "temperatura": record['temperatura'],
            "ph": record['ph'],
            "conductividad": record['conductividad'],
            "oxigeno": record['oxigeno'],
            "turbiedad": record['turbiedad'],
            "profundidad": record['profundidad'],
            "nivel": record['nivel'],
            "latitud": record['latitud'],
            "longitud": record['longitud'],
            "foto_path": fotoPath,
            "foto_multiparametro": fotoMulti,
            "foto_turbiedad": fotoTurb,
          });
        }
      }

      final Map<String, dynamic> finalPayload = {"monitoreos": payloadList};
      await _log('📦 [SYNC] Payload construido. Enviando ${payloadList.length} registros.');

      final auth = '${config['usuario']}:${config['contrasenia']}';
      final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';

      final response = await http.post(
        Uri.parse(syncUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': basicAuth,
        },
        body: jsonEncode(finalPayload),
      ).timeout(const Duration(seconds: 45));

      await _log('📡 [SYNC] Código de respuesta: ${response.statusCode}');
      await _log('📄 [SYNC] Respuesta body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = jsonDecode(response.body);
        
        // Handle server-side success confirmation
        if (jsonResponse['status'] == 'success' && jsonResponse['data'] != null) {
          List<dynamic> syncedIdsDyn = jsonResponse['data']['synced_ids'] ?? [];
          List<int> syncedIds = syncedIdsDyn.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
          
          await _log('✅ [SYNC] Identificadores sincronizados confirmados por servidor: $syncedIds');

          for (int id in syncedIds) {
            await _dbHelper.updateMonitoreoSyncStatus(id, 'success');
          }
        } else {
          await _log('⚠️ [SYNC] Respuesta OK pero sin estructura de éxito específica. Aplicando fallback de estado.');
          for (int id in _selectedIds) {
            await _dbHelper.updateMonitoreoSyncStatus(id, 'success');
          }
        }
        
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronización finalizada correctamente.')),
          );
          _loadData();
        }
      } else {
        throw Exception('El servidor respondió con error: ${response.statusCode}');
      }
    } catch (e) {
      await _log('❌ [SYNC] Error crítico: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en sincronización: $e')),
        );
      }
    }
  }

  Future<void> _verificarConexion() async {
    await _log('🔍 [DEBUG] Verificando alcance de red con la URL base...');
    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay configuración activa.');
      
      final String baseUrl = config['url'];
      final Uri testUrl = Uri.parse(baseUrl);
      
      await _log('🌐 [DEBUG] Intento de GET a URL base: $testUrl');

      // Un simple GET a la raíz para verificar si el servidor responde
      final response = await http.get(testUrl).timeout(const Duration(seconds: 10));
      
      await _log('📡 [DEBUG] El servidor respondió con status: ${response.statusCode}');

      if (mounted) {
        // Cualquier respuesta (200, 403, 404, etc.) significa que el servidor es alcanzable
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Conexión exitosa con el servidor en: $baseUrl'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      await _log('❌ [DEBUG] No se pudo conectar al servidor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo conectar al servidor. Verifica tu red e IP.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(currentRoute: '/enviar_datos'),
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          title: const Text('Sync de Datos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'enviar') _enviarDatosSeleccionados();
                if (value == 'verificar') _verificarConexion();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'enviar',
                  child: ListTile(
                    leading: Icon(Icons.storage, color: Colors.blue),
                    title: Text('Enviar datos a servidor'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'verificar',
                  child: ListTile(
                    leading: Icon(Icons.sync_alt, color: Colors.orange),
                    title: Text('Verificar conexion con servidor'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'PENDIENTES'),
              Tab(text: 'ENVIADOS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildPendingList(),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildSentList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_recordsPending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No hay monitoreos pendientes',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final bool allSelected = _selectedIds.length == _recordsPending.length;

    return Column(
      children: [
        // Selection Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds = _recordsPending.map((r) => r['id'] as int).toSet();
                    } else {
                      _selectedIds.clear();
                    }
                  });
                },
              ),
              const Text(
                'Seleccionar Todo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_selectedIds.isNotEmpty)
                Text(
                  '${_selectedIds.length} seleccionados',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _recordsPending.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = _recordsPending[index];
              final int id = record['id'];
              final bool isSelected = _selectedIds.contains(id);

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  activeColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                ),
                title: Text(
                  record['nombre_estacion'] ?? 'Estación S/N',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Fecha: ${record['fecha_hora'] ?? 'S/F'}'),
                trailing: const Icon(Icons.pending_actions, color: Colors.orangeAccent),
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedIds.remove(id);
                    } else {
                      _selectedIds.add(id);
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSentList() {
    if (_recordsSent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Historial de envíos vacío',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _recordsSent.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = _recordsSent[index];
        return ListTile(
          leading: const Icon(Icons.cloud_done, color: Colors.green),
          title: Text(
            record['nombre_estacion'] ?? 'Estación S/N',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('Enviado: ${record['fecha_hora'] ?? 'S/F'}'),
          trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
        );
      },
    );
  }
}
