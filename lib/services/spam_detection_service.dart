import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class SpamDetectionService {
  // Use your computer's local IP address instead of 127.0.0.1 for mobile access
  static const String apiUrl = 'http://192.168.0.101:8000/predict';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if a message is spam using the local API
  /// Returns true if spam, false if ham
  static Future<bool> isSpam(String messageText) async {
    try {
      print('Calling spam detection API...');
      print('URL: $apiUrl');
      print('Message preview: ${messageText.substring(0, messageText.length > 50 ? 50 : messageText.length)}...');
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': messageText,
        }),
      );

      print('API Response status: ${response.statusCode}');
      print('API Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final prediction = result['prediction'] as String;
        print('Prediction: $prediction');
        return prediction.toLowerCase() == 'spam';
      } else {
        print('Spam detection API error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error calling spam detection API: $e');
      return false;
    }
  }

  /// Save spam sender to Firestore
  static Future<void> saveSpamSender({
    required String phoneNumber,
    required String? contactName,
    required String messageText,
  }) async {
    try {
      await _firestore.collection('spam').add({
        'phoneNumber': phoneNumber,
        'contactName': contactName ?? 'Unknown',
        'messageText': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'detectedAt': DateTime.now().toIso8601String(),
      });
      print('Spam sender saved to Firestore: $phoneNumber');
    } catch (e) {
      print('Error saving spam sender to Firestore: $e');
    }
  }

  /// Save ham (legitimate) message to Firestore
  static Future<void> saveHamMessage({
    required String phoneNumber,
    required String? contactName,
    required String messageText,
  }) async {
    try {
      await _firestore.collection('ham').add({
        'phoneNumber': phoneNumber,
        'contactName': contactName ?? 'Unknown',
        'messageText': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'detectedAt': DateTime.now().toIso8601String(),
      });
      print('Ham message saved to Firestore: $phoneNumber');
    } catch (e) {
      print('Error saving ham message to Firestore: $e');
    }
  }

  /// Check message for spam and save to Firestore if spam detected
  static Future<bool> checkAndSaveIfSpam({
    required String messageText,
    required String phoneNumber,
    String? contactName,
  }) async {
    final spam = await isSpam(messageText);
    
    if (spam) {
      await saveSpamSender(
        phoneNumber: phoneNumber,
        contactName: contactName,
        messageText: messageText,
      );
    } else {
      await saveHamMessage(
        phoneNumber: phoneNumber,
        contactName: contactName,
        messageText: messageText,
      );
    }
    
    return spam;
  }
}
