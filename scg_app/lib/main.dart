import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:fl_chart/fl_chart.dart';
// Remove the http import since we're not using API
// import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
// Add this import
import 'services/data_storage.dart';
import 'saved_readings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seismo Cardio App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AccelerometerPage(),
        '/saved_readings': (context) => const SavedReadingsPage(),
      },
    );
  }
}

class AccelerometerPage extends StatefulWidget {
  const AccelerometerPage({super.key});

  @override
  State<AccelerometerPage> createState() => _AccelerometerPageState();
}

class _AccelerometerPageState extends State<AccelerometerPage> {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _saveTimer; // Timer for saving data every 5 seconds
  AccelerometerEvent? _currentEvent;
  bool _isReading = false;
  
  // Data storage for graphs
  final List<FlSpot> _xData = [];
  final List<FlSpot> _yData = [];
  final List<FlSpot> _zData = [];
  
  // Data collection for local storage
  final List<Map<String, dynamic>> _collectedData = [];
  
  double _timeCounter = 0;
  final int _maxDataPoints = 100;
  
  // Local storage variables
  String _currentSessionKey = '';
  bool _isStoringLocally = false;
  String _lastSaveStatus = 'Not started';
  int _saveCount = 0;
  int _currentBatchSize = 0;
  int _totalSessions = 0;
  
  @override
  void initState() {
    super.initState();
    _currentEvent = AccelerometerEvent(0.0, 0.0, 0.0, DateTime.now());
    _loadSessionCount();
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSessionCount() async {
    final count = await SimpleStorageHelper.getSessionCount();
    setState(() {
      _totalSessions = count;
    });
  }

  void _stopAccelerometerListening() {
    _accelerometerSubscription?.cancel();
    _saveTimer?.cancel();
    setState(() {
      _isReading = false;
      _isStoringLocally = false;
      _lastSaveStatus = 'Stopped';
      _collectedData.clear();
      _currentBatchSize = 0;
    });
  }

  void _startAccelerometerListening() {
    setState(() {
      _isReading = true;
      _isStoringLocally = true;
      _lastSaveStatus = 'Starting...';
      _saveCount = 0;
      _timeCounter = 0;
      _xData.clear();
      _yData.clear();
      _zData.clear();
      _collectedData.clear();
      _currentBatchSize = 0;
      
      // Create session key using current timestamp
      _currentSessionKey = 'session_${DateTime.now().millisecondsSinceEpoch}';
    });
    
    // Start accelerometer listening
    _accelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        setState(() {
          _currentEvent = event;
          _timeCounter += 0.1;
          
          // Add new data points for visualization
          _xData.add(FlSpot(_timeCounter, event.x));
          _yData.add(FlSpot(_timeCounter, event.y));
          _zData.add(FlSpot(_timeCounter, event.z));
          
          // Remove old data points to maintain performance
          if (_xData.length > _maxDataPoints) {
            _xData.removeAt(0);
            _yData.removeAt(0);
            _zData.removeAt(0);
          }
          
          // Collect data for local storage
          _collectedData.add({
            'timestamp': DateTime.now().toIso8601String(),
            'x': event.x,
            'y': event.y,
            'z': event.z,
          });
          
          _currentBatchSize = _collectedData.length;
        });
      },
      onError: (error) {
        print('Accelerometer error: $error');
        setState(() {
          _isReading = false;
          _isStoringLocally = false;
          _lastSaveStatus = 'Error occurred';
        });
      },
    );
    
    // Start the timer for saving data every 5 seconds
    _startSaveTimer();
  }

  void _startSaveTimer() {
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isStoringLocally && _currentEvent != null) {
        _saveDataToLocalStorage();
      }
    });
  }

  Future<void> _saveDataToLocalStorage() async {
    if (_collectedData.isEmpty) {
      print('No data collected in this 5-second interval');
      return;
    }
    
    try {
      // Create a copy of the collected data and clear the original list
      final List<Map<String, dynamic>> dataToSave = List.from(_collectedData);
      _collectedData.clear();
      
      // Save to local storage with the session key
      await SimpleStorageHelper.storeReadings(_currentSessionKey, dataToSave);

      setState(() {
        _saveCount++;
        _currentBatchSize = 0;
        _lastSaveStatus = 'Saved batch #$_saveCount (${dataToSave.length} points)';
      });

      print('Saved ${dataToSave.length} readings to local storage with key: $_currentSessionKey');

    } catch (e) {
      setState(() {
        _saveCount++;
        _currentBatchSize = 0;
        _lastSaveStatus = 'Save error - Batch #$_saveCount: $e';
      });
      print('Error saving to local storage: $e');
    }
  }

  // Calculate dynamic Y-axis range for better visibility
  Map<String, double> _calculateYAxisRange(List<FlSpot> data) {
    if (data.isEmpty) {
      return {'min': -10.0, 'max': 10.0};
    }

    double minValue = data.map((spot) => spot.y).reduce(min);
    double maxValue = data.map((spot) => spot.y).reduce(max);
    
    double range = maxValue - minValue;
    double padding = range * 0.25;
    
    if (range < 0.5) {
      padding = 0.25;
    }
    
    if (minValue == maxValue) {
      minValue -= 1.0;
      maxValue += 1.0;
    } else {
      minValue -= padding;
      maxValue += padding;
    }

    return {
      'min': minValue,
      'max': maxValue,
    };
  }

  Widget _buildChart(String title, List<FlSpot> data, Color color) {
    Map<String, double> yRange = _calculateYAxisRange(data);
    
    return Container(
      height: 140,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Range: ${yRange['min']!.toStringAsFixed(1)} to ${yRange['max']!.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: data.isNotEmpty ? data.first.x : 0,
                maxX: data.isNotEmpty ? data.last.x : 10,
                minY: yRange['min']!,
                maxY: yRange['max']!,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (yRange['max']! - yRange['min']!) / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (yRange['max']! - yRange['min']!) / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        );
                      },
                      reservedSize: 35,
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: data,
                    isCurved: false,
                    color: color,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
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

  Widget _buildReadingCard(String axis, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            axis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.toStringAsFixed(3),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'm/s²',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalStorageCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isStoringLocally ? Colors.green[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isStoringLocally ? Colors.green[300]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isStoringLocally ? Icons.storage : Icons.storage_outlined,
                color: _isStoringLocally ? Colors.green[700] : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Local Storage',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isStoringLocally ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lastSaveStatus,
            style: TextStyle(
              fontSize: 12,
              color: _isStoringLocally ? Colors.green[600] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          if (_isStoringLocally) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Current batch: $_currentBatchSize points',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Session Key: $_currentSessionKey',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green[400],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        title: const Text(
          'Seismo Cardio App',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: () => Navigator.pushNamed(context, '/saved_readings'),
            tooltip: 'View Stored Data',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.blue[500]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.sensors,
                    size: 40,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Real-time Accelerometer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Motion Sensing & Local Storage',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Local Storage Card
            _buildLocalStorageCard(),
            
            const SizedBox(height: 24),
            
            // Current readings
            const Text(
              'Current Readings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildReadingCard(
                    'X-Axis',
                    _currentEvent!.x,
                    Colors.red[600]!,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadingCard(
                    'Y-Axis',
                    _currentEvent!.y,
                    Colors.green[600]!,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadingCard(
                    'Z-Axis',
                    _currentEvent!.z,
                    Colors.blue[600]!,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Charts section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Auto-Scaling Strip Charts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AUTO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // X-axis chart
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildChart('X-Axis Acceleration', _xData, Colors.red[600]!),
            ),
            
            const SizedBox(height: 16),
            
            // Y-axis chart
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildChart('Y-Axis Acceleration', _yData, Colors.green[600]!),
            ),
            
            const SizedBox(height: 16),
            
            // Z-axis chart
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildChart('Z-Axis Acceleration', _zData, Colors.blue[600]!),
            ),
            
            const SizedBox(height: 24),
            
            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.storage,
                    color: Colors.amber[700],
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total Sessions: $_totalSessions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Data is stored locally on your device with session keys',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isReading ? _stopAccelerometerListening : _startAccelerometerListening,
        backgroundColor: _isReading ? Colors.red[600] : Colors.green[600],
        foregroundColor: Colors.white,
        icon: Icon(_isReading ? Icons.stop : Icons.play_arrow),
        label: Text(
          _isReading ? 'Stop Recording' : 'Start Recording',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
