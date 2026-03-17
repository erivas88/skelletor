import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import 'dart:math';

class ChartData {
  ChartData(this.x, this.y);
  final DateTime x;
  final double y;
}

class ChartAnalysisScreen extends StatefulWidget {
  final String estacion;
  final String parametro;
  final double? currentInputValue;

  const ChartAnalysisScreen({
    super.key,
    required this.estacion,
    required this.parametro,
    this.currentInputValue,
  });

  @override
  State<ChartAnalysisScreen> createState() => _ChartAnalysisScreenState();
}

class _ChartAnalysisScreenState extends State<ChartAnalysisScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ChartData> _historicalData = [];
  late Future<void> _chartDataFuture;
  
  double _mean = 0;
  double _sigma = 0;
  double? _min3Sigma;
  double? _max3Sigma;
  bool _isOutOfRange = false;
  
  // Custom unit mapping (simplified)
  String _unit = '';

  @override
  void initState() {
    super.initState();
    _setUnit();
    _chartDataFuture = _loadAndCalculateData();
  }

  void _setUnit() {
    switch (widget.parametro.toLowerCase()) {
      case 'temperatura': _unit = '°C'; break;
      case 'ph': _unit = 'u.pH'; break;
      case 'conductividad': _unit = 'µS/cm'; break;
      case 'oxigeno': _unit = 'mg/l'; break;
      case 'turbiedad': _unit = 'NTU'; break;
      case 'profundidad':
      case 'nivel': _unit = 'm'; break;
      default: _unit = '';
    }
  }

  Future<void> _loadAndCalculateData() async {
    // Fetch from normalized table
    final historyRows = await _dbHelper.getHistorialMuestrasByStationName(widget.estacion);
    
    // Filter by parameter
    final paramRows = historyRows.where((row) => row['parametro'] == widget.parametro).toList();
    
    // Sort by date ascending
    paramRows.sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));

    final List<ChartData> parsedData = [];
    final List<double> numericValues = [];

    for (var row in paramRows) {
      if (row['valor'] != null && row['fecha'] != null) {
        final val = (row['valor'] as num).toDouble();
        final date = DateTime.tryParse(row['fecha'].toString());
        if (date != null) {
          parsedData.add(ChartData(date, val));
          numericValues.add(val);
        }
      }
    }

    if (numericValues.isEmpty) return;

    // Do the math
    _calculateRanges(numericValues);

    // Assign data for the chart
    _historicalData = parsedData; 
  }

  void _calculateRanges(List<double> data) {
    if (data.isEmpty) return;
    
    final double sum = data.reduce((a, b) => a + b);
    _mean = sum / data.length;
    
    final double variance = data.map((x) => pow(x - _mean, 2)).reduce((a, b) => a + b) / (data.length > 1 ? data.length - 1 : 1);
    _sigma = variance > 0 ? sqrt(variance) : 0.0;
    
    setState(() {
      _min3Sigma = _mean - (3 * _sigma);
      _max3Sigma = _mean + (3 * _sigma);
      
      if (widget.currentInputValue != null) {
        _isOutOfRange = widget.currentInputValue! < _min3Sigma! || widget.currentInputValue! > _max3Sigma!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.estacion} [${widget.parametro}]'),
      ),
      body: FutureBuilder<void>(
        future: _chartDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar datos: ${snapshot.error}'));
          }

          if (_historicalData.isEmpty) {
            return const Center(child: Text('Sin datos históricos para este punto'));
          }
          
          return Column(
            children: [
              _buildStatusBanner(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChart(),
                ),
              ),
              _buildStatsCards(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner() {
    final bool outOfRange = _isOutOfRange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: outOfRange ? Colors.redAccent.withValues(alpha: 0.2) : Colors.greenAccent.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(
            outOfRange ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: outOfRange ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),
          Text(
            outOfRange ? 'Valor fuera de rango típico (3σ)' : 'Valor normal y típico',
            style: TextStyle(
              color: outOfRange ? Colors.red[900] : Colors.green[900],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final TooltipBehavior tooltip = TooltipBehavior(
      enable: true,
      header: '',
      canShowMarker: true,
      format: 'point.x : point.y $_unit',
    );

    return SfCartesianChart(
      tooltipBehavior: tooltip,
      primaryXAxis: DateTimeAxis(
        title: const AxisTitle(text: 'Fecha'),
        dateFormat: DateFormat('dd/MM/yyyy'),
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: '$_unit'),
        plotBands: <PlotBand>[
          if (_max3Sigma != null)
            PlotBand(
              isVisible: true,
              start: _max3Sigma!,
              end: _max3Sigma!,
              borderWidth: 2,
              borderColor: Colors.redAccent,
              dashArray: const <double>[5, 5],
              text: 'Máx 3σ',
              textStyle: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10),
              horizontalTextAlignment: TextAnchor.end,
            ),
          if (_min3Sigma != null)
            PlotBand(
              isVisible: true,
              start: _min3Sigma!,
              end: _min3Sigma!,
              borderWidth: 2,
              borderColor: Colors.redAccent,
              dashArray: const <double>[5, 5],
              text: 'Mín 3σ',
              textStyle: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10),
              horizontalTextAlignment: TextAnchor.end,
            ),
        ],
      ),
      series: <CartesianSeries>[
        LineSeries<ChartData, DateTime>(
          dataSource: _historicalData,
          xValueMapper: (ChartData data, _) => data.x,
          yValueMapper: (ChartData data, _) => data.y,
          name: widget.parametro,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
        if (widget.currentInputValue != null)
          ScatterSeries<ChartData, DateTime>(
            dataSource: [ChartData(DateTime.now(), widget.currentInputValue!)],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.red,
            markerSettings: const MarkerSettings(
              isVisible: true, 
              height: 12, 
              width: 12, 
              shape: DataMarkerType.circle,
              borderWidth: 2,
              borderColor: Colors.white,
            ),
            name: 'Valor Actual',
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('Media (μ)', '${_mean.toStringAsFixed(2)} $_unit'),
          _buildStatCard('Sig (σ)', '${_sigma.toStringAsFixed(2)} $_unit'),
          _buildStatCard('Tot Muestras', '${_historicalData.length}'),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
