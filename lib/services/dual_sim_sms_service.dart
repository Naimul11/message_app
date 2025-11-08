import 'package:flutter/services.dart';

class DualSimSmsService {
  static const platform = MethodChannel('com.example.message_app/dual_sim');

  /// Send SMS using a specific SIM card slot
  /// 
  /// [phoneNumber] - The recipient's phone number
  /// [message] - The message to send
  /// [simSlot] - The SIM slot index (0 for SIM 1, 1 for SIM 2)
  /// 
  /// Returns true if SMS was sent successfully, false otherwise
  static Future<bool> sendSmsBySim({
    required String phoneNumber,
    required String message,
    required int simSlot,
  }) async {
    try {
      print('DualSimSmsService: Sending SMS via slot $simSlot');
      print('To: $phoneNumber');
      print('Message length: ${message.length}');
      
      final String result = await platform.invokeMethod('sendSmsBySim', {
        'phoneNumber': phoneNumber,
        'message': message,
        'simSlot': simSlot,
      });
      
      print('DualSimSmsService: $result');
      return true;
    } on PlatformException catch (e) {
      print('DualSimSmsService Error: ${e.code} - ${e.message}');
      print('Details: ${e.details}');
      rethrow;
    } catch (e) {
      print('DualSimSmsService Unexpected error: $e');
      rethrow;
    }
  }
}
