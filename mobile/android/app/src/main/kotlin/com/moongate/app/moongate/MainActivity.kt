package com.moongate.app.moongate

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.moongate.app.VpnPlugin

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val NETWORK_CHANNEL = "com.moongate.app/network"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(VpnPlugin())

        // Channel that forces all Dart HTTP traffic through the WiFi interface.
        // Without this, Android's Smart Network Switch can route local-subnet
        // requests (192.168.x.x) over mobile data → EHOSTUNREACH (errno 113).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                when (call.method) {
                    "bindToWifi" -> {
                        val wifiNet = cm.allNetworks.firstOrNull { net ->
                            cm.getNetworkCapabilities(net)
                                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        }
                        val bound = cm.bindProcessToNetwork(wifiNet)
                        result.success(bound)
                    }
                    "releaseNetwork" -> {
                        cm.bindProcessToNetwork(null)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
