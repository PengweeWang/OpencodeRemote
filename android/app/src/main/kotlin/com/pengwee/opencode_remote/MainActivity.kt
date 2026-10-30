package com.pengwee.opencode_remote

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pengwee.opencode_remote/keepalive"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Opencode Remote - 后台保活中"
                    val content = call.argument<String>("content") ?: "保持活动 SSH 会话与端口转发连接"
                    requestNotificationPermissionIfNeeded()
                    KeepAliveService.start(this, title, content)
                    result.success(true)
                }
                "update" -> {
                    val title = call.argument<String>("title") ?: "Opencode Remote - 后台保活中"
                    val content = call.argument<String>("content") ?: "保持活动 SSH 会话与端口转发连接"
                    if (KeepAliveService.isServiceRunning) {
                        KeepAliveService.update(this, title, content)
                    } else {
                        requestNotificationPermissionIfNeeded()
                        KeepAliveService.start(this, title, content)
                    }
                    result.success(true)
                }
                "stop" -> {
                    KeepAliveService.stop(this)
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("BATTERY_OPTIMIZATION_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }
}
