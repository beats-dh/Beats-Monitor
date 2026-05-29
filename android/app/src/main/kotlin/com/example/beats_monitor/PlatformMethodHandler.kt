package com.example.beats_monitor

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PlatformMethodHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    private val notificationChannelId = "penultima_web_chat_alerts"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_PATH", "File path is null", null)
                    return
                }
                
                try {
                    val file = File(filePath)
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.provider",
                        file
                    )
                    
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }
                    
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            }
            "showNotification" -> {
                val title = call.argument<String>("title") ?: "Penultima Web"
                val body = call.argument<String>("body") ?: ""
                val tag = call.argument<String>("tag") ?: "penultima-web-chat"

                try {
                    if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(false)
                        return
                    }

                    createNotificationChannel()

                    val launchIntent = context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                        ?.apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                    val pendingIntent = launchIntent?.let {
                        PendingIntent.getActivity(
                            context,
                            0,
                            it,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                    }

                    val notification = NotificationCompat.Builder(context, notificationChannelId)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .setContentIntent(pendingIntent)
                        .build()

                    NotificationManagerCompat.from(context)
                        .notify(tag, tag.hashCode(), notification)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("NOTIFICATION_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(notificationChannelId) != null) {
            return
        }

        val channel = NotificationChannel(
            notificationChannelId,
            "Penultima Web chat alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Private messages and Help channel alerts."
        }
        manager.createNotificationChannel(channel)
    }
}
