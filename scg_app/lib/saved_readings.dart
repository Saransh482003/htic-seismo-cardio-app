import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'services/data_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class SavedReadingsPage extends StatefulWidget {
  const SavedReadingsPage({super.key});

  @override
  State<SavedReadingsPage> createState() => _SavedReadingsPageState();
}

class _SavedReadingsPageState extends State<SavedReadingsPage> {
  List<String> _sessionKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sessions = await SimpleStorageHelper.getAllSessionKeys();
      setState(() {
        _sessionKeys = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sessions: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession(String sessionKey) async {
    try {
      await SimpleStorageHelper.deleteReadings(sessionKey);
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting session: $e')),
        );
      }
    }
  }

  Future<void> _clearAllSessions() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear All Sessions'),
          content: const Text(
            'Are you sure you want to delete all recorded sessions? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await SimpleStorageHelper.clearAllReadings();
                  await _loadSessions();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All sessions cleared')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error clearing sessions: $e')),
                    );
                  }
                }
              },
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );
  }

  String _formatSessionName(String sessionKey) {
    // Extract timestamp from session key (format: session_1692307200000)
    final timestampStr = sessionKey.replaceFirst('session_', '');
    try {
      final timestamp = int.parse(timestampStr);
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return sessionKey;
    }
  }

  Future<String> _getSessionInfo(String sessionKey) async {
    try {
      final metadata = await SimpleStorageHelper.getSessionMetadata(sessionKey);
      final fileSize = await SimpleStorageHelper.getBinaryFileSize(sessionKey);
      
      if (metadata != null) {
        final readings = metadata['totalReadings'] ?? 0;
        final sizeKB = (fileSize / 1024).toStringAsFixed(1);
        return '$readings readings • ${sizeKB}KB binary';
      }
      
      return 'Unknown size';
    } catch (e) {
      return 'Error loading info';
    }
  }

  Widget _buildSessionCard(String sessionKey, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          _formatSessionName(sessionKey),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session: $sessionKey',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            FutureBuilder<String>(
              future: _getSessionInfo(sessionKey),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green[600],
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'delete') {
              _deleteSession(sessionKey);
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _navigateToSessionDetails(sessionKey),
      ),
    );
  }

  void _navigateToSessionDetails(String sessionKey) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionDetailsPage(sessionKey: sessionKey),
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
          'Saved Sessions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 4,
        actions: [
          if (_sessionKeys.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAllSessions,
              tooltip: 'Clear All Sessions',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _sessionKeys.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    // Summary header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[50]!, Colors.blue[100]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_open,
                            color: Colors.blue[700],
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_sessionKeys.length} Recorded Sessions',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              Text(
                                'Tap any session to view detailed readings',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Sessions list
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sessionKeys.length,
                        itemBuilder: (context, index) {
                          return _buildSessionCard(_sessionKeys[index], index);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Sessions Found',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start recording to create your first session',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.sensors),
            label: const Text('Start Recording'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class SessionDetailsPage extends StatefulWidget {
  final String sessionKey;

  const SessionDetailsPage({
    super.key,
    required this.sessionKey,
  });

  @override
  State<SessionDetailsPage> createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  Map<String, dynamic>? _sessionData;
  bool _isLoading = true;
  List<Map<String, dynamic>> _readings = [];
  String _sessionTimestamp = '';
  int _totalReadings = 0;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await SimpleStorageHelper.getReadings(widget.sessionKey);
      if (data != null) {
        setState(() {
          _sessionData = data;
          _readings = List<Map<String, dynamic>>.from(data['readings'] ?? []);
          _sessionTimestamp = data['timestamp'] ?? '';
          _totalReadings = data['totalReadings'] ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session data not found')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading session data: $e')),
        );
      }
    }
  }

  Future<String> exportToCSV() async {
    List<List<dynamic>> rows = [];
    rows.add(["Timestamp", "X-Axis (m/s²)", "Y-Axis (m/s²)", "Z-Axis (m/s²)"]); 
    for (var item in _readings) {
      rows.add([_formatReadingTimestamp(item['timestamp']), item["x"], item["y"], item["z"]]);
    }

    String csvData = const ListToCsvConverter().convert(rows);

    final directory = await getApplicationDocumentsDirectory();
    DateTime now = DateTime.now();
    final fileName = "exported_data_${now.year}-${now.month}-${now.day}_${now.hour}:${now.minute}:${now.second}.csv";
    final path = "${directory.path}/$fileName";

    // Write file
    final file = File(path);
    await file.writeAsString(csvData);

    print("CSV file saved at: $path");
    return path;
  }

  Future<String> exportToBinary() async {
    final directory = await getApplicationDocumentsDirectory();
    DateTime now = DateTime.now();
    final fileName = "exported_data_${now.year}-${now.month}-${now.day}_${now.hour}:${now.minute}:${now.second}.bin";
    final path = "${directory.path}/$fileName";

    // Create binary data
    final file = File(path);
    final sink = file.openWrite();
    
    try {
      // Write header information
      final headerJson = {
        'version': '1.0',
        'sessionKey': widget.sessionKey,
        'timestamp': _sessionTimestamp,
        'totalReadings': _totalReadings,
        'dataFormat': 'float64',
        'columns': ['timestamp_ms', 'x', 'y', 'z']
      };
      
      final headerString = json.encode(headerJson);
      final headerBytes = utf8.encode(headerString);
      final headerLength = headerBytes.length;
      
      // Write header length (4 bytes)
      final headerLengthBytes = Uint8List(4);
      headerLengthBytes.buffer.asUint32List()[0] = headerLength;
      sink.add(headerLengthBytes);
      
      // Write header
      sink.add(headerBytes);
      
      // Write readings data in binary format
      for (var reading in _readings) {
        // Convert timestamp to milliseconds since epoch
        final timestamp = DateTime.parse(reading['timestamp']).millisecondsSinceEpoch;
        final x = reading['x'] as double;
        final y = reading['y'] as double;
        final z = reading['z'] as double;
        
        // Create byte buffer for one reading (32 bytes total: 8 bytes each for timestamp, x, y, z)
        final buffer = Uint8List(32);
        final floatView = buffer.buffer.asFloat64List();
        
        floatView[0] = timestamp.toDouble();
        floatView[1] = x;
        floatView[2] = y;
        floatView[3] = z;
        
        sink.add(buffer);
      }
      
      await sink.close();
      print("Binary file saved at: $path");
      return path;
      
    } catch (e) {
      await sink.close();
      throw Exception('Error writing binary file: $e');
    }
  }

  Future<String> exportToJSON() async {
    final directory = await getApplicationDocumentsDirectory();
    DateTime now = DateTime.now();
    final fileName = "exported_data_${now.year}-${now.month}-${now.day}_${now.hour}:${now.minute}:${now.second}.json";
    final path = "${directory.path}/$fileName";

    // Create JSON structure
    final jsonData = {
      'metadata': {
        'sessionKey': widget.sessionKey,
        'exportTimestamp': now.toIso8601String(),
        'originalTimestamp': _sessionTimestamp,
        'totalReadings': _totalReadings,
        'version': '1.0',
        'units': {
          'acceleration': 'm/s²',
          'timestamp': 'ISO8601'
        }
      },
      'readings': _readings.map((reading) => {
        'timestamp': reading['timestamp'],
        'accelerometer': {
          'x': reading['x'],
          'y': reading['y'],
          'z': reading['z']
        }
      }).toList()
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
    
    final file = File(path);
    await file.writeAsString(jsonString);

    print("JSON file saved at: $path");
    return path;
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  String _formatReadingTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}.${dateTime.millisecond.toString().padLeft(3, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildDataTable() {
    return Container(
      margin: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.table_chart, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Accelerometer Readings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
          // Table content
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateColor.resolveWith(
                    (states) => Colors.grey[100]!,
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        'Timestamp',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'X-Axis (m/s²)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Y-Axis (m/s²)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Z-Axis (m/s²)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                  ],
                  rows: _readings.map((reading) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            _formatReadingTimestamp(reading['timestamp']),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        DataCell(
                          Text(
                            reading['x'].toStringAsFixed(3),
                            style: TextStyle(
                              color: Colors.red[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            reading['y'].toStringAsFixed(3),
                            style: TextStyle(
                              color: Colors.green[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            reading['z'].toStringAsFixed(3),
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.blue[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.blue[700],
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Session Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Session ID:', widget.sessionKey),
          _buildInfoRow('Recorded:', _formatTimestamp(_sessionTimestamp)),
          _buildInfoRow('Total Readings:', _totalReadings.toString()),
          if (_readings.isNotEmpty) ...[
            _buildInfoRow('Duration:', _calculateDuration()),
            _buildInfoRow('Sampling Rate:', _calculateSamplingRate()),
            _buildInfoRow('Storage Format:', 'Binary (.bin + .meta)'),
            FutureBuilder<int>(
              future: SimpleStorageHelper.getBinaryFileSize(widget.sessionKey),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final sizeKB = (snapshot.data! / 1024).toStringAsFixed(1);
                  return _buildInfoRow('File Size:', '${sizeKB}KB');
                }
                return _buildInfoRow('File Size:', 'Loading...');
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blue[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.blue[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _calculateDuration() {
    if (_readings.length < 2) return 'N/A';
    
    try {
      final firstReading = DateTime.parse(_readings.first['timestamp']);
      final lastReading = DateTime.parse(_readings.last['timestamp']);
      final duration = lastReading.difference(firstReading);
      
      return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    } catch (e) {
      return 'N/A';
    }
  }

  String _calculateSamplingRate() {
    if (_readings.length < 2) return 'N/A';
    
    try {
      final firstReading = DateTime.parse(_readings.first['timestamp']);
      final lastReading = DateTime.parse(_readings.last['timestamp']);
      final duration = lastReading.difference(firstReading);
      
      if (duration.inMilliseconds > 0) {
        final rate = (_readings.length - 1) / (duration.inMilliseconds / 1000);
        return '${rate.toStringAsFixed(1)} Hz';
      }
    } catch (e) {
      return 'N/A';
    }
    
    return 'N/A';
  }

  Future<void> _exportData(String format, {bool autoOpen = false}) async {
    try {
      String path;
      String formatName;
      
      switch (format) {
        case 'csv':
          path = await exportToCSV();
          formatName = 'CSV';
          break;
        case 'binary':
          path = await exportToBinary();
          formatName = 'Binary';
          break;
        case 'json':
          path = await exportToJSON();
          formatName = 'JSON';
          break;
        default:
          throw Exception('Unknown export format: $format');
      }
      
      // Auto-open file if requested (long press)
      if (autoOpen) {
        await _openFile(path);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(autoOpen 
              ? '$formatName export completed and opened' 
              : '$formatName export completed successfully'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            action: autoOpen ? null : SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () => _openFile(path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openFile(String path) async {
    try {
      if (await File(path).exists()) {
        print('Attempting to open file with OpenFilex: $path');
        
        final result = await OpenFilex.open(path);
        
        // Check if the file was opened successfully
        if (result.type == ResultType.done) {
          print('File opened successfully: $path');
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('File opened successfully'),
                backgroundColor: Colors.green[600],
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else if (result.type == ResultType.noAppToOpen) {
          print('No app available to open this file type');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No app available to open this file type'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          _showFileLocationDialog(path);
        } else if (result.type == ResultType.permissionDenied) {
          print('Permission denied to open file');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission denied to open file'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          _showFileLocationDialog(path);
        } else if (result.type == ResultType.error) {
          print('Error opening file: ${result.message}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error opening file: ${result.message}'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          _showFileLocationDialog(path);
        } else {
          print('Unknown result type: ${result.type}');
          _showFileLocationDialog(path);
        }
        
      } else {
        print('File does not exist: $path');
        _showFileLocationDialog(path);
      }
    } catch (e) {
      print('Exception opening file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _showFileLocationDialog(path);
    }
  }

  void _showFileLocationDialog(String path) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('File Saved'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('File saved to:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  path,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to open file automatically. You can:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              const Text('• Copy the path above and navigate manually'),
              const Text('• Use the "Open Folder" button below'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _openContainingFolder(path);
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openContainingFolder(String filePath) async {
    try {
      final directory = File(filePath).parent.path;
      print('Opening containing folder: $directory');
      
      if (Platform.isWindows) {
        // Open folder and select the file
        final result = await Process.run('explorer', ['/select,', filePath], runInShell: true);
        print('Explorer select result: ${result.exitCode}');
        
        if (result.exitCode != 0) {
          // Fallback: just open the folder
          await Process.run('explorer', [directory], runInShell: true);
        }
      } else if (Platform.isMacOS) {
        // Open finder and select the file
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        // Open file manager to the directory
        await Process.run('xdg-open', [directory]);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Folder opened'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error opening containing folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening folder: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        title: const Text(
          'Session Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _sessionData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Session not found',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildSessionInfo(),
                    Expanded(
                      child: _buildDataTable(),
                    ),
                    // Export buttons section
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Export Options',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to export • Long press to export & open',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // CSV Export Button
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _exportData('csv'),
                                  onLongPress: () => _exportData('csv', autoOpen: true),
                                  child: Container(
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.green[600]!, Colors.green[700]!],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.table_chart,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'CSV',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Binary Export Button
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _exportData('binary'),
                                  onLongPress: () => _exportData('binary', autoOpen: true),
                                  child: Container(
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.grey[800]!, Colors.black],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.memory,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Binary',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // JSON Export Button
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _exportData('json'),
                                  onLongPress: () => _exportData('json', autoOpen: true),
                                  child: Container(
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.blue[600]!, Colors.blue[700]!],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.code,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'JSON',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

    );
  }
}