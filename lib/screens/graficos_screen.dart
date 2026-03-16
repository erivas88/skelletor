import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import 'registrar_monitoreo_screen.dart'; // To use SearchableDropdown

class ChartData {
  final DateTime x;
  final double y;
  ChartData(this.x, this.y);
}

class GraficosScreen extends StatefulWidget {
  const GraficosScreen({super.key});

  @override
  State<GraficosScreen> createState() => _GraficosScreenState();
}

class _GraficosScreenState extends State<GraficosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // State variables for dynamic data
  List<Station> _estaciones = [];
  List<Parametro> _parametros = [];
  Station? _estacionSeleccionada;
  List<Parametro> _parametrosSeleccionados = [];
  Map<String, List<ChartData>> _multiChartData = {};
  bool _isLoadingData = true;
  bool _hasGraphed = false;
  
  // Mock options state
  bool _ejeSecundario = false;
  bool _invertirEje = false;

  // Mapping connects selected parameter clave_interna to DB column name
  final Map<String, String> _parameterToColumnMap = {
    'ph': 'ph',
    'temperatura': 'temperatura',
    'conductividad': 'conductividad',
    'oxigeno': 'oxigeno',
    'caudal': 'caudal',
    'nivel': 'nivel',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    try {
      // 1. Get Stations
      final stationsFull = await _dbHelper.getStationsWithPrograms();
      // 2. Get Parameters
      final parametros = await _dbHelper.getParametros();
      
      // 3. Filter Parameters that can be graphed (checking against our map)
      final filteredParametros = parametros.where((p) => _parameterToColumnMap.containsKey(p.claveInterna.toLowerCase())).toList();

      setState(() {
        _estaciones = stationsFull.map((s) => Station(
          id: s['id'], 
          name: s['name'],
          latitude: s['latitude'] ?? 0.0,
          longitude: s['longitude'] ?? 0.0,
        )).toList();
        _parametros = filteredParametros;
        _isLoadingData = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/graficos'),
      body: Column(
        children: [
          // 1. Chart Area
          _buildChartContent(isDarkMode),

          // 2. Bottom Control Panel
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: Colors.blue,
                    labelColor: Colors.blue,
                    unselectedLabelColor: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: const [
                      Tab(icon: Icon(Icons.show_chart, size: 20), text: 'GRAFICAR'),
                      Tab(icon: Icon(Icons.settings, size: 20), text: 'OPCIONES'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // View 1: Graficar
                        _buildGraficarView(isDarkMode),
                        // View 2: Opciones
                        _buildOpcionesView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContent(bool isDarkMode) {
    if (_isLoadingData) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_multiChartData.isEmpty && !_hasGraphed) {
      return Expanded(
        child: Container(
          width: double.infinity,
          color: isDarkMode ? Colors.black87 : Colors.grey.shade200,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Icon(
                    Icons.crop_din,
                    color: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    size: 20,
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Sin Datos para mostrar',
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_multiChartData.isEmpty && _hasGraphed) {
      return const Expanded(child: Center(child: Text('No hay registros históricos para esta combinación', style: TextStyle(color: Colors.grey, fontSize: 16), textAlign: TextAlign.center)));
    }

    final paramNames = _parametrosSeleccionados.map((p) => p.nombreParametro).join(' / ');
    final titleText = '${_estacionSeleccionada?.name ?? ""} [$paramNames]';
    final unitsText = _parametrosSeleccionados.map((p) => p.unidad).toSet().join(' / ');

    return Expanded(
      child: SfCartesianChart(
        backgroundColor: Colors.transparent,
        plotAreaBorderWidth: 0,
        title: ChartTitle(text: titleText, textStyle: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        legend: Legend(isVisible: true, position: LegendPosition.bottom, alignment: ChartAlignment.center, textStyle: const TextStyle(fontSize: 10, color: Colors.grey)),
        tooltipBehavior: TooltipBehavior(enable: true, header: titleText),
        primaryXAxis: DateTimeAxis(
          majorGridLines: const MajorGridLines(width: 0.5, color: Colors.grey),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          dateFormat: DateFormat('dd/MM/yyyy'),
        ),
        primaryYAxis: NumericAxis(
          name: 'yAxis1',
          minimum: _parametrosSeleccionados.isNotEmpty ? _parametrosSeleccionados.first.min : null,
          maximum: _parametrosSeleccionados.isNotEmpty ? _parametrosSeleccionados.first.max : null,
          title: AxisTitle(
            text: _parametrosSeleccionados.isNotEmpty 
              ? '${_parametrosSeleccionados.first.nombreParametro} [${_parametrosSeleccionados.first.unidad}]' 
              : '', 
            textStyle: const TextStyle(color: Colors.green, fontSize: 10)
          ),
          majorGridLines: const MajorGridLines(width: 0.5, color: Colors.grey),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          labelFormat: '{value}',
        ),
        axes: <ChartAxis>[
          if (_parametrosSeleccionados.length > 1)
            NumericAxis(
              name: 'yAxis2',
              opposedPosition: true,
              minimum: _parametrosSeleccionados[1].min,
              maximum: _parametrosSeleccionados[1].max,
              title: AxisTitle(
                text: '${_parametrosSeleccionados[1].nombreParametro} [${_parametrosSeleccionados[1].unidad}]',
                textStyle: const TextStyle(color: Colors.purple, fontSize: 10),
              ),
              majorGridLines: const MajorGridLines(width: 0), // Hide grid lines for second axis to avoid clutter
              labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
              labelFormat: '{value}',
            ),
        ],
        series: _parametrosSeleccionados.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          final color = idx == 0 ? Colors.green : Colors.purple;
          return LineSeries<ChartData, DateTime>(
            dataSource: _multiChartData[p.nombreParametro] ?? [],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            yAxisName: idx == 0 ? 'yAxis1' : 'yAxis2',
            color: color,
            width: 2,
            markerSettings: const MarkerSettings(isVisible: false),
            name: p.nombreParametro,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGraficarView(bool isDarkMode) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              children: [
                // Compact Horizontal List
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Estaciones Item
                      InkWell(
                        onTap: () {
                          _mostrarDialogoSeleccion(
                            titulo: 'Seleccionar Estación',
                            opciones: _estaciones.map((e) => e.name).toList(),
                            seleccionActual: _estacionSeleccionada != null ? [_estacionSeleccionada!.name] : [],
                            onSeleccionado: (List<String> seleccion) {
                              setState(() {
                                if (seleccion.isNotEmpty) {
                                  _estacionSeleccionada = _estaciones.firstWhere((e) => e.name == seleccion.first);
                                } else {
                                  _estacionSeleccionada = null;
                                }
                                _hasGraphed = false;
                              });
                              _fetchAndGraphData();
                            },
                          );
                        },
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 12),
                              const Text('Estaciones', style: TextStyle(fontSize: 14, color: Colors.blueAccent)),
                              const Spacer(),
                              Text(
                                _estacionSeleccionada?.name ?? 'Seleccione',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      ),
                      // Divider
                      Divider(height: 1, thickness: 1, color: isDarkMode ? Colors.white10 : Colors.black12),
                      // Parámetros Item
                      InkWell(
                        onTap: () {
                          _mostrarDialogoSeleccion(
                            titulo: 'Seleccionar Parámetro',
                            opciones: _parametros.map((p) => p.nombreParametro).toList(),
                            seleccionActual: _parametrosSeleccionados.map((p) => p.nombreParametro).toList(),
                            multiSelect: true,
                            onSeleccionado: (List<String> seleccion) {
                              setState(() {
                                _parametrosSeleccionados = _parametros.where((p) => seleccion.contains(p.nombreParametro)).toList();
                                _hasGraphed = false;
                              });
                              _fetchAndGraphData();
                            },
                          );
                        },
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.science, color: Colors.green, size: 20),
                              const SizedBox(width: 12),
                              const Text('Parámetros', style: TextStyle(fontSize: 14, color: Colors.blueAccent)),
                              const Spacer(),
                              Text(
                                _parametrosSeleccionados.isEmpty 
                                  ? 'Seleccione' 
                                  : _parametrosSeleccionados.length == 1 
                                    ? _parametrosSeleccionados.first.nombreParametro 
                                    : '${_parametrosSeleccionados.length} Seleccionados',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoSeleccion({
    required String titulo,
    required List<String> opciones,
    required List<String> seleccionActual,
    required Function(List<String>) onSeleccionado,
    bool multiSelect = false,
  }) async {
    List<String> seleccionTemporal = List.from(seleccionActual);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(titulo, style: const TextStyle(fontSize: 16)),
              contentPadding: const EdgeInsets.only(top: 12),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: opciones.length,
                  itemBuilder: (context, index) {
                    final opcion = opciones[index];
                    if (multiSelect) {
                      return CheckboxListTile(
                        title: Text(opcion, style: const TextStyle(fontSize: 14)),
                        value: seleccionTemporal.contains(opcion),
                        activeColor: Colors.blueAccent,
                        onChanged: (bool? checked) {
                          setStateDialog(() {
                            if (checked == true) {
                              if (seleccionTemporal.length < 2) {
                                seleccionTemporal.add(opcion);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Máximo 2 parámetros'), duration: Duration(seconds: 1)),
                                );
                              }
                            } else {
                              seleccionTemporal.remove(opcion);
                            }
                          });
                        },
                      );
                    } else {
                      return RadioListTile<String>(
                        title: Text(opcion, style: const TextStyle(fontSize: 14)),
                        value: opcion,
                        groupValue: seleccionTemporal.isNotEmpty ? seleccionTemporal.first : null,
                        activeColor: Colors.blueAccent,
                        onChanged: (String? value) {
                          setStateDialog(() {
                            if (value != null) {
                              seleccionTemporal = [value];
                            }
                          });
                        },
                      );
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.blueAccent)),
                ),
                TextButton(
                  onPressed: () {
                    onSeleccionado(seleccionTemporal);
                    Navigator.of(context).pop();
                  },
                  child: const Text('SELECCIONAR', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchAndGraphData() async {
    if (_estacionSeleccionada == null || _parametrosSeleccionados.isEmpty) {
      setState(() {
        _multiChartData = {};
        _hasGraphed = false;
      });
      return;
    }

    try {
      final data = await _dbHelper.getHistorialMuestrasByStationName(_estacionSeleccionada!.name);
      final Map<String, List<ChartData>> newMultiData = {};

      for (var p in _parametrosSeleccionados) {
        final String columnKey = _parameterToColumnMap[p.claveInterna.toLowerCase()] ?? '';
        if (columnKey.isEmpty) continue;

        final List<ChartData> mappedData = data.map((sample) {
          final dateValue = DateTime.tryParse(sample['fecha'] ?? '');
          final dynamicRaw = sample[columnKey];
          final double? yValue = dynamicRaw is double ? dynamicRaw : double.tryParse(dynamicRaw?.toString() ?? '');
          if (dateValue != null && yValue != null) {
            return ChartData(dateValue, yValue);
          }
          return null;
        }).whereType<ChartData>().toList();

        // Sort data by date for proper charting
        mappedData.sort((a, b) => a.x.compareTo(b.x));
        newMultiData[p.nombreParametro] = mappedData;
      }

      setState(() {
        _multiChartData = newMultiData;
        _hasGraphed = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al graficar: $e')));
      }
    }
  }

  Widget _buildOpcionesView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            _buildSwitchRow(
              label: 'Eje Secundario',
              value: _ejeSecundario,
              onChanged: (val) => setState(() => _ejeSecundario = val),
            ),
            const Divider(height: 1),
            _buildSwitchRow(
              label: 'Invert. Eje1',
              value: _invertirEje,
              onChanged: (val) => setState(() => _invertirEje = val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }
}
