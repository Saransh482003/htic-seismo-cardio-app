import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SimpleStorageHelper {
  static const String _dataKey = 'seismo_readings';
  static const String _sessionCountKey = 'session_count';

  // Store readings data with a session key
  static Future<void> storeReadings(String sessionKey, List<Map<String, dynamic>> readings) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert readings to JSON string
    String jsonData = json.encode({
      'sessionKey': sessionKey,
      'timestamp': DateTime.now().toIso8601String(),
      'totalReadings': readings.length,
      'readings': readings,
    });
    
    // Store with the session key
    await prefs.setString('${_dataKey}_$sessionKey', jsonData);
    
    // Update session count
    int currentCount = prefs.getInt(_sessionCountKey) ?? 0;
    await prefs.setInt(_sessionCountKey, currentCount + 1);
    
    print('Stored ${readings.length} readings with key: ${_dataKey}_$sessionKey');
  }

  // Retrieve readings by session key
  static Future<Map<String, dynamic>?> getReadings(String sessionKey) async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonData = prefs.getString('${_dataKey}_$sessionKey');
    
    if (jsonData != null) {
      return json.decode(jsonData);
    }
    return null;
  }

  // Get all session keys
  static Future<List<String>> getAllSessionKeys() async {
    final prefs = await SharedPreferences.getInstance();
    Set<String> keys = prefs.getKeys();
    
    return keys
        .where((key) => key.startsWith(_dataKey))
        .map((key) => key.replaceFirst('${_dataKey}_', ''))
        .toList();
  }

  // Delete readings by session key
  static Future<void> deleteReadings(String sessionKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_dataKey}_$sessionKey');
    print('Deleted readings with key: ${_dataKey}_$sessionKey');
  }

  // Clear all stored data
  static Future<void> clearAllReadings() async {
    final prefs = await SharedPreferences.getInstance();
    Set<String> keys = prefs.getKeys();
    
    for (String key in keys) {
      if (key.startsWith(_dataKey)) {
        await prefs.remove(key);
      }
    }
    
    await prefs.setInt(_sessionCountKey, 0);
    print('Cleared all stored readings');
  }

  // Get total number of sessions
  static Future<int> getSessionCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sessionCountKey) ?? 0;
  }
}