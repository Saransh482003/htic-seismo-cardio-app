import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class SimpleStorageHelper {
  static const String _sessionListKey = 'session_list';
  static const String _sessionCountKey = 'session_count';

  // Store readings data as binary file
  static Future<void> storeReadings(String sessionKey, List<Map<String, dynamic>> readings) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      
      // Create sessions directory if it doesn't exist
      if (!await sessionDir.exists()) {
        await sessionDir.create(recursive: true);
      }
      
      final binaryFile = File('${sessionDir.path}/$sessionKey.bin');
      final metadataFile = File('${sessionDir.path}/$sessionKey.meta');
      
      // Create metadata
      final metadata = {
        'sessionKey': sessionKey,
        'timestamp': DateTime.now().toIso8601String(),
        'totalReadings': readings.length,
        'version': '1.0',
        'dataFormat': 'float64',
        'columns': ['timestamp_ms', 'x', 'y', 'z']
      };
      
      // Write metadata as JSON
      await metadataFile.writeAsString(json.encode(metadata));
      
      // Write binary data
      final sink = binaryFile.openWrite();
      
      try {
        for (var reading in readings) {
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
        
        // Update session list in SharedPreferences
        await _updateSessionList(sessionKey);
        
        print('Stored ${readings.length} readings in binary format with key: $sessionKey');
        
      } catch (e) {
        await sink.close();
        throw Exception('Error writing binary data: $e');
      }
      
    } catch (e) {
      throw Exception('Error storing readings: $e');
    }
  }

  // Retrieve readings by session key from binary file
  static Future<Map<String, dynamic>?> getReadings(String sessionKey) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      
      final binaryFile = File('${sessionDir.path}/$sessionKey.bin');
      final metadataFile = File('${sessionDir.path}/$sessionKey.meta');
      
      if (!await binaryFile.exists() || !await metadataFile.exists()) {
        print('Binary or metadata file not found for session: $sessionKey');
        return null;
      }
      
      // Read metadata
      final metadataString = await metadataFile.readAsString();
      final metadata = json.decode(metadataString);
      
      // Read binary data
      final binaryData = await binaryFile.readAsBytes();
      final readings = <Map<String, dynamic>>[];
      
      // Each reading is 32 bytes (4 doubles of 8 bytes each)
      const int recordSize = 32;
      final int numRecords = binaryData.length ~/ recordSize;
      
      for (int i = 0; i < numRecords; i++) {
        final offset = i * recordSize;
        final recordBytes = binaryData.sublist(offset, offset + recordSize);
        final floatView = recordBytes.buffer.asFloat64List();
        
        final timestampMs = floatView[0].toInt();
        final x = floatView[1];
        final y = floatView[2];
        final z = floatView[3];
        
        readings.add({
          'timestamp': DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String(),
          'x': x,
          'y': y,
          'z': z,
        });
      }
      
      return {
        'sessionKey': metadata['sessionKey'],
        'timestamp': metadata['timestamp'],
        'totalReadings': metadata['totalReadings'],
        'readings': readings,
      };
      
    } catch (e) {
      print('Error reading binary data for session $sessionKey: $e');
      return null;
    }
  }

  // Get all session keys from SharedPreferences
  static Future<List<String>> getAllSessionKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionList = prefs.getStringList(_sessionListKey) ?? [];
      
      // Also scan the sessions directory for any binary files
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      
      if (await sessionDir.exists()) {
        final files = await sessionDir.list().toList();
        final binaryFiles = files
            .where((file) => file is File && file.path.endsWith('.bin'))
            .map((file) => file.path.split('/').last.replaceAll('.bin', ''))
            .toList();
        
        // Merge and deduplicate
        final allSessions = {...sessionList, ...binaryFiles}.toList();
        
        // Update SharedPreferences with the complete list
        await prefs.setStringList(_sessionListKey, allSessions);
        
        return allSessions;
      }
      
      return sessionList;
    } catch (e) {
      print('Error getting session keys: $e');
      return [];
    }
  }

  // Delete readings by session key
  static Future<void> deleteReadings(String sessionKey) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      
      final binaryFile = File('${sessionDir.path}/$sessionKey.bin');
      final metadataFile = File('${sessionDir.path}/$sessionKey.meta');
      
      if (await binaryFile.exists()) {
        await binaryFile.delete();
      }
      
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      
      // Remove from session list
      final prefs = await SharedPreferences.getInstance();
      final sessionList = prefs.getStringList(_sessionListKey) ?? [];
      sessionList.remove(sessionKey);
      await prefs.setStringList(_sessionListKey, sessionList);
      
      // Update session count
      await prefs.setInt(_sessionCountKey, sessionList.length);
      
      print('Deleted session: $sessionKey');
      
    } catch (e) {
      throw Exception('Error deleting session: $e');
    }
  }

  // Clear all stored data
  static Future<void> clearAllReadings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      
      if (await sessionDir.exists()) {
        // Delete all files in the sessions directory
        final files = await sessionDir.list().toList();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          }
        }
      }
      
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionListKey);
      await prefs.setInt(_sessionCountKey, 0);
      
      print('Cleared all stored readings');
      
    } catch (e) {
      throw Exception('Error clearing all readings: $e');
    }
  }

  // Get total number of sessions
  static Future<int> getSessionCount() async {
    try {
      final sessions = await getAllSessionKeys();
      
      // Update count in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_sessionCountKey, sessions.length);
      
      return sessions.length;
    } catch (e) {
      print('Error getting session count: $e');
      return 0;
    }
  }

  // Helper method to update session list in SharedPreferences
  static Future<void> _updateSessionList(String sessionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionList = prefs.getStringList(_sessionListKey) ?? [];
      
      if (!sessionList.contains(sessionKey)) {
        sessionList.add(sessionKey);
        await prefs.setStringList(_sessionListKey, sessionList);
        await prefs.setInt(_sessionCountKey, sessionList.length);
      }
    } catch (e) {
      print('Error updating session list: $e');
    }
  }

  // Helper method to get session metadata only
  static Future<Map<String, dynamic>?> getSessionMetadata(String sessionKey) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      final metadataFile = File('${sessionDir.path}/$sessionKey.meta');
      
      if (await metadataFile.exists()) {
        final metadataString = await metadataFile.readAsString();
        return json.decode(metadataString);
      }
      
      return null;
    } catch (e) {
      print('Error reading metadata for session $sessionKey: $e');
      return null;
    }
  }

  // Helper method to get binary file size
  static Future<int> getBinaryFileSize(String sessionKey) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${directory.path}/sessions');
      final binaryFile = File('${sessionDir.path}/$sessionKey.bin');
      
      if (await binaryFile.exists()) {
        return await binaryFile.length();
      }
      
      return 0;
    } catch (e) {
      print('Error getting file size for session $sessionKey: $e');
      return 0;
    }
  }
}