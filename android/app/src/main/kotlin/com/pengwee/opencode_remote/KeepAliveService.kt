package com.pengwee.opencode_remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "opencode_keepalive_channel"
        const val NOTIFICATION_ID = 2001

        const val ACTION_START = "com.pengwee.opencode_remote.action.START"
        const val ACTION_STOP = "com.pengwee.opencode_remote.action.STOP"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_CONTENT = "extra_content"

        @Volatile
        var isServiceRunning = false
            private set

        fun start(context: Context, title: String, content: String) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_CONTENT, content)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, content: String) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (manager != null) {
                val notification = buildNotification(context, title, content)
                manager.notify(NOTIFICATION_ID, notification)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun buildNotification(context: Context, title: String, content: String): Notification {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, pendingFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            return builder
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(R.drawable.ic_stat_opencode)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        createNotificationChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_STOP -> {
                releaseLocks()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                isServiceRunning = false
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Opencode Remote - 后台保活中"
                val content = intent.getStringExtra(EXTRA_CONTENT) ?: "保持活动 SSH 会话与端口转发连接"
                val notification = buildNotification(this, title, content)

                if (Build.VERSION.SDK_INT >= 34) {
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, 0)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isServiceRunning = false
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        // 1. Partial WakeLock: Keep CPU awake when screen is off
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "OpencodeRemote:KeepAliveWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            wakeLock?.let {
                if (!it.isHeld) {
                    // Safe hold for 2 hours to prevent excessive battery drain if forgotten
                    it.acquire(2 * 60 * 60 * 1000L)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // 2. WifiLock: Keep Wi-Fi high performance when screen is off
        try {
            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifiManager.createWifiLock(mode, "OpencodeRemote:KeepAliveWifiLock").apply {
                    setReferenceCounted(false)
                }
            }
            wifiLock?.let {
                if (!it.isHeld) {
                    it.acquire()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        wakeLock = null

        try {
            wifiLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        wifiLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Opencode 会话后台保活",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "在切屏和熄屏时保持 SSH 连接与端口转发不断开"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
