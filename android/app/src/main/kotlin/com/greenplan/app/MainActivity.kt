package com.greenplan.app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 任务进行中的中断监测（规格 1.5）。
 *
 * 向 Dart 侧上报：息屏/亮屏、窗口焦点、分屏/画中画、通话状态。
 * 判定逻辑不在这里，Kotlin 只负责「报告发生了什么」。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "greenplan/native_monitor"
        private const val EVENT_CHANNEL = "greenplan/native_events"
        private const val PHONE_PERMISSION_REQUEST = 1001
    }

    private var eventSink: EventChannel.EventSink? = null
    private var monitoring = false
    private var screenReceiver: BroadcastReceiver? = null
    private var phoneStateListener: PhoneStateListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMonitoring" -> {
                        startMonitoring()
                        result.success(null)
                    }
                    "stopMonitoring" -> {
                        stopMonitoring()
                        result.success(null)
                    }
                    "isScreenOn" -> result.success(isScreenOn())
                    "isPhonePermissionGranted" -> result.success(hasPhonePermission())
                    "requestPhonePermission" -> {
                        requestPhonePermission()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun startMonitoring() {
        monitoring = true
        registerScreenReceiver()
        startPhoneStateListener()
    }

    private fun stopMonitoring() {
        monitoring = false
        unregisterScreenReceiver()
        stopPhoneStateListener()
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> emit("screenOff")
                    Intent.ACTION_SCREEN_ON -> emit("screenOn")
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        screenReceiver = receiver
    }

    private fun unregisterScreenReceiver() {
        val receiver = screenReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // 已经注销过，忽略
        }
        screenReceiver = null
    }

    /** 通话状态：响铃/接通视为豁免，空闲解除。 */
    @Suppress("DEPRECATION")
    private fun startPhoneStateListener() {
        if (!hasPhonePermission()) {
            emit("phonePermissionDenied")
            return
        }
        if (phoneStateListener != null) return
        val manager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                when (state) {
                    TelephonyManager.CALL_STATE_RINGING -> emit("phoneRinging")
                    TelephonyManager.CALL_STATE_OFFHOOK -> emit("phoneOffhook")
                    TelephonyManager.CALL_STATE_IDLE -> emit("phoneIdle")
                }
            }
        }
        phoneStateListener = listener
        manager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    @Suppress("DEPRECATION")
    private fun stopPhoneStateListener() {
        val listener = phoneStateListener ?: return
        val manager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        manager.listen(listener, PhoneStateListener.LISTEN_NONE)
        phoneStateListener = null
    }

    private fun hasPhonePermission(): Boolean {
        return checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPhonePermission() {
        if (hasPhonePermission()) return
        requestPermissions(
            arrayOf(Manifest.permission.READ_PHONE_STATE),
            PHONE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PHONE_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startPhoneStateListener()
        } else {
            emit("phonePermissionDenied")
        }
    }

    private fun isScreenOn(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!monitoring) return
        emit(if (hasFocus) "focusGained" else "focusLost")
    }

    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (!monitoring) return
        emit(if (isInMultiWindowMode) "multiWindowEntered" else "multiWindowExited")
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!monitoring) return
        emit(if (isInPictureInPictureMode) "pipEntered" else "pipExited")
    }

    override fun onDestroy() {
        stopMonitoring()
        super.onDestroy()
    }

    private fun emit(name: String) {
        eventSink?.success(name)
    }
}
