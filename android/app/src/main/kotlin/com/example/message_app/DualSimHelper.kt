package com.example.message_app

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel

class DualSimHelper {
    companion object {
        private const val SENT_ACTION = "SMS_SENT"
        private const val DELIVERED_ACTION = "SMS_DELIVERED"

        @RequiresApi(Build.VERSION_CODES.LOLLIPOP_MR1)
        fun sendSmsBySim(
            context: Context,
            phoneNumber: String,
            message: String,
            simSlot: Int,
            result: MethodChannel.Result
        ) {
            try {
                val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                
                // Get subscription ID for the given SIM slot
                val subscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                
                if (subscriptionInfoList.isNullOrEmpty()) {
                    result.error("NO_SIM", "No active SIM cards found", null)
                    return
                }

                // Find the subscription for the requested slot
                val subscriptionInfo = subscriptionInfoList.find { it.simSlotIndex == simSlot }
                
                if (subscriptionInfo == null) {
                    result.error("INVALID_SLOT", "No SIM found in slot $simSlot", null)
                    return
                }

                val subscriptionId = subscriptionInfo.subscriptionId

                // Get SmsManager for the specific subscription
                val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                }

                // Create pending intents for sent and delivered status
                val sentIntent = PendingIntent.getBroadcast(
                    context,
                    0,
                    Intent(SENT_ACTION),
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                )

                val deliveredIntent = PendingIntent.getBroadcast(
                    context,
                    0,
                    Intent(DELIVERED_ACTION),
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                )

                // Send SMS
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    sentIntent,
                    deliveredIntent
                )

                result.success("SMS sent successfully from SIM slot $simSlot")
            } catch (e: SecurityException) {
                result.error("PERMISSION_DENIED", "SMS permission not granted", e.message)
            } catch (e: Exception) {
                result.error("SEND_FAILED", "Failed to send SMS: ${e.message}", e.toString())
            }
        }
    }
}
