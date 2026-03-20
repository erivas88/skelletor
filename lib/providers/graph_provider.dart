import 'package:flutter/material.dart';
import '../models/models.dart';

class GraphProvider with ChangeNotifier {
  List<List<ChartData>> _chartDataList = [];
  bool _hasGraphed = false;
  List<Parametro> _parametrosSeleccionados = [];
  Map<String, dynamic>? _selectedStation;
  
  // Options state
  bool _invertirEje = false;
  Color _colorSerie1 = const Color(0xFF0D47A1);
  Color _colorSerie2 = const Color(0xFFFF9800);

  List<List<ChartData>> get chartDataList => _chartDataList;
  bool get hasGraphed => _hasGraphed;
  List<Parametro> get parametrosSeleccionados => _parametrosSeleccionados;
  Map<String, dynamic>? get selectedStation => _selectedStation;
  bool get invertirEje => _invertirEje;
  Color get colorSerie1 => _colorSerie1;
  Color get colorSerie2 => _colorSerie2;

  void updateGraphData({
    required List<List<ChartData>> data,
    required bool hasGraphed,
    required List<Parametro> params,
    required Map<String, dynamic>? station,
  }) {
    _chartDataList = data;
    _hasGraphed = hasGraphed;
    _parametrosSeleccionados = params;
    _selectedStation = station;
    notifyListeners();
  }

  void updateOptions({
    bool? invertirEje,
    Color? color1,
    Color? color2,
  }) {
    if (invertirEje != null) _invertirEje = invertirEje;
    if (color1 != null) _colorSerie1 = color1;
    if (color2 != null) _colorSerie2 = color2;
    notifyListeners();
  }
}
