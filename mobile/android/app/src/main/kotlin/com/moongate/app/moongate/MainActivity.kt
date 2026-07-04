package com.moongate.app.moongate

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val SECURE_CHANNEL = "com.moongate.app/secure"
        private const val INSTALL_CHANNEL = "com.moongate.app/install"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // App lock: let Dart toggle FLAG_SECURE so the lock screen - and the
        // app's contents while it is locked - are excluded from screenshots
        // and blanked in the recent-apps thumbnail. Driven by the app-lock
        // gate (set on lock, cleared on unlock).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // In-app updater (GitHub/KIAUH sideload channel only): launch the system
        // package installer on an APK the Dart side has already downloaded. The
        // file is shared as a content:// URI via our FileProvider with a
        // temporary read grant (file:// is blocked from Android 7+); Android then
        // shows its standard install confirmation. Compiled OUT of the Play build
        // (BuildConfig.SELF_UPDATE == false), which ships no
        // REQUEST_INSTALL_PACKAGES and lets Google Play deliver updates.
        if (BuildConfig.SELF_UPDATE) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "installApk" -> {
                            val path = call.argument<String>("path")
                            if (path == null) {
                                result.error("no_path", "Missing apk path", null)
                                return@setMethodCallHandler
                            }
                            try {
                                val file = File(path)
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.fileprovider", file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(
                                        uri, "application/vnd.android.package-archive"
                                    )
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("install_failed", e.message, null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }
}
