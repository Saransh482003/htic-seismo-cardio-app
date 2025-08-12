import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:scg_app/constants.dart';

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
  Timer? _postTimer; // Timer for POST requests every 5 seconds
  AccelerometerEvent? _currentEvent;
  bool _isReading = false; // Track if accelerometer is currently reading
  
  // Data storage for graphs
  final List<FlSpot> _xData = [];
  final List<FlSpot> _yData = [];
  final List<FlSpot> _zData = [];
  
  // Data collection for 5-second intervals
  final List<Map<String, dynamic>> _collectedData = []; // Store collected data for 5 seconds
  
  double _timeCounter = 0;
  final int _maxDataPoints = 100; // Keep last 100 data points
  
  // API configuration
  // static const String apiBaseUrl = 'http://127.0.0.1:5000'; // Change this to your backend URL
  String _lastPostStatus = 'Not started';
  int _postCount = 0;
  int _currentBatchSize = 0; // Track current batch size
  
  @override
  void initState() {
    super.initState();
    // Initialize with default zero event for display
    _currentEvent = AccelerometerEvent(0.0, 0.0, 0.0, DateTime.now());
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _postTimer?.cancel(); // Cancel the POST timer
    super.dispose();
  }

  void _stopAccelerometerListening() {
    _accelerometerSubscription?.cancel();
    _postTimer?.cancel(); // Stop the POST timer
    setState(() {
      _isReading = false;
      _lastPostStatus = 'Stopped';
      _collectedData.clear(); // Clear any remaining collected data
      _currentBatchSize = 0;
    });
  }

  void _startAccelerometerListening() {
    setState(() {
      _isReading = true;
      _lastPostStatus = 'Starting...';
      _postCount = 0;
      _collectedData.clear(); // Clear any previous data
      _currentBatchSize = 0;
    });
    
    // Start accelerometer listening
    _accelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        setState(() {
          _currentEvent = event;
          _timeCounter += 0.1; // Increment time by 100ms
          
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
          
          // Collect data for 5-second batch sending
          _collectedData.add({
            'timestamp': DateTime.now().toIso8601String(),
            'x': event.x,
            'y': event.y,
            'z': event.z,
          });
          _currentBatchSize = _collectedData.length;
        });
        
        // Log accelerometer data to terminal (optional, can be commented out for performance)
        // print('Accelerometer - X: ${event.x.toStringAsFixed(2)}, '
        //       'Y: ${event.y.toStringAsFixed(2)}, '
        //       'Z: ${event.z.toStringAsFixed(2)}');
      },
      onError: (error) {
        print('Accelerometer error: $error');
        setState(() {
          _isReading = false;
          _lastPostStatus = 'Error occurred';
        });
      },
    );
    
    // Start the separate timer for POST requests (this runs every 5 seconds)
    _startPostTimer();
  }

  void _startPostTimer() {
    _postTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isReading && _currentEvent != null) {
        _sendAccelerometerData();
      }
    });
  }

  Future<void> _sendAccelerometerData() async {
    if (_collectedData.isEmpty) {
      print('No data collected in this 5-second interval');
      return;
    }
    
    try {
      // Create a copy of the collected data and clear the original list
      final List<Map<String, dynamic>> dataToSend = List.from(_collectedData);
      _collectedData.clear();
      
      // Prepare the data to send
      final Map<String, dynamic> payload = {
        'batch_timestamp': DateTime.now().toIso8601String(),
        'batch_info': {
          'post_count': _postCount + 1,
          'data_points_in_batch': dataToSend.length,
          'time_interval_seconds': 5,
        },
        'accelerometer_data': dataToSend, // List of dictionaries with timestamps
      };

      print('Sending POST request to $apiBaseUrl/accelerometer-data');
      print('Batch size: ${dataToSend.length} data points');
      // print('Data sample: ${json.encode(payload)}');

      final response = await http.post(
        Uri.parse('$apiBaseUrl/accelerometer-data'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _postCount++;
        _currentBatchSize = 0; // Reset batch size after sending
        if (response.statusCode == 200 || response.statusCode == 201) {
          _lastPostStatus = 'Success (${response.statusCode}) - Batch #$_postCount (${dataToSend.length} points)';
          // print('POST request successful: ${response.body}');
        } else {
          _lastPostStatus = 'Failed (${response.statusCode}) - Batch #$_postCount';
          print('POST request failed: ${response.statusCode} - ${response.body}');
        }
      });

    } catch (e) {
      setState(() {
        _postCount++;
        _currentBatchSize = 0;
        _lastPostStatus = 'Error - Batch #$_postCount: $e';
      });
      print('Error sending POST request: $e');
    }
  }

  // Calculate dynamic Y-axis range for better visibility of small fluctuations
  Map<String, double> _calculateYAxisRange(List<FlSpot> data) {
    if (data.isEmpty) {
      return {'min': -10.0, 'max': 10.0};
    }

    double minValue = data.map((spot) => spot.y).reduce(min);
    double maxValue = data.map((spot) => spot.y).reduce(max);
    
    // Calculate the range
    double range = maxValue - minValue;
    
    // Add 25% padding above and below for better visualization
    double padding = range * 0.25;
    
    // Ensure minimum range for very stable readings (minimum 0.5 units)
    if (range < 0.5) {
      padding = 0.25;
    }
    
    // Ensure we don't have identical min/max values
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
    // Get dynamic Y-axis range for auto-scaling
    Map<String, double> yRange = _calculateYAxisRange(data);
    
    return Container(
      height: 140, // Slightly increased height for better visibility
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
              // Show current Y-axis range
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
                    barWidth: 2.5, // Slightly thicker line for better visibility
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
            value.toStringAsFixed(3), // Increased precision for small values
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

  Widget _buildApiStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isReading ? Colors.green[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isReading ? Colors.green[300]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isReading ? Icons.cloud_upload : Icons.cloud_off,
                color: _isReading ? Colors.green[700] : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'API Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isReading ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lastPostStatus,
            style: TextStyle(
              fontSize: 12,
              color: _isReading ? Colors.green[600] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          if (_isReading) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      'Batch Size',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '$_currentBatchSize',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Batches Sent',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '$_postCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        title: const Text(
          'Seismo Cardio App',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 4,
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
                    child: const Column(
                      children: [
                        Icon(
                          Icons.sensors,
                          size: 40,
                          color: Colors.white,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Real-time Accelerometer',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Motion Sensing & Analysis',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // API Status Card
                  _buildApiStatusCard(),
                  
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
                          Icons.auto_graph,
                          color: Colors.amber[700],
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Data Points: ${_xData.length}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Charts auto-scale for optimal visibility of fluctuations',
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
                _isReading ? 'Stop Reading' : 'Start Reading',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
    );
  }
}
