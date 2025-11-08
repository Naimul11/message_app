package com.example.message_app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.message_app/dual_sim"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSmsBySim" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                        val phoneNumber = call.argument<String>("phoneNumber")
                        val message = call.argument<String>("message")
                        val simSlot = call.argument<Int>("simSlot")

                        if (phoneNumber == null || message == null || simSlot == null) {
                            result.error("INVALID_ARGUMENTS", "Phone number, message, and SIM slot are required", null)
                        } else {
                            DualSimHelper.sendSmsBySim(this, phoneNumber, message, simSlot, result)
                        }
                    } else {
                        result.error("UNSUPPORTED", "Dual SIM is only supported on Android 5.1+", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

