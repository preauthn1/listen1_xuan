package com.xiebian.listen1_xuan

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    private var feedbackChannel: MethodChannel? = null
    private val feedbackNotifications by lazy { FeedbackPushNotifications(this) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        feedbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "listen1_xuan/feedback_push").also {
            it.setMethodCallHandler(feedbackNotifications::handle)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "listen1_xuan/build_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "getBuildNumber") {
                    result.success(getString(R.string.app_build_number))
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        feedbackNotifications.takeTap(intent)?.let { feedbackChannel?.invokeMethod("notificationTapped", it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 真正的边到边：内容画到状态栏和手势条下方，系统栏透明且不加灰色遮罩。
        // 旧的 FLAG_TRANSLUCENT_* 会在原生 Android 上叠一层半透明灰，已弃用。
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }
}
