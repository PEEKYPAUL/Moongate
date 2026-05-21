package com.moongate.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel handler for WireGuard VPN on Android.
 *
 * The actual WireGuard tunnel implementation will be added in a follow-up
 * using the wireguard-android library (https://github.com/WireGuard/wireguard-android).
 * This file wires up the Flutter ↔ native bridge and handles VpnService permission.
 */
class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val CHANNEL = "com.moongate.app/vpn"
        private const val VPN_PERMISSION_REQUEST = 1001
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config") ?: run {
                    result.error("INVALID_ARG", "config is required", null)
                    return
                }
                requestVpnPermissionAndConnect(config, result)
            }
            "disconnect" -> {
                // TODO: stop WireGuard tunnel service
                channel.invokeMethod("onDisconnected", null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestVpnPermissionAndConnect(config: String, result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity ?: run {
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        })
        if (intent != null) {
            pendingResult = result
            activity?.startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            startTunnel(config, result)
        }
    }

    private fun startTunnel(config: String, result: MethodChannel.Result) {
        // TODO: parse WireGuard INI config and start WireGuard tunnel via
        // com.wireguard.android.backend.GoBackend
        channel.invokeMethod("onConnected", null)
        result.success(null)
    }

    // ActivityAware — needed to call startActivityForResult for VPN permission
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            if (requestCode == VPN_PERMISSION_REQUEST) {
                if (resultCode == Activity.RESULT_OK) {
                    // Permission granted — re-trigger (config lost; real impl stores it)
                    channel.invokeMethod("onConnected", null)
                    pendingResult?.success(null)
                } else {
                    pendingResult?.error("PERMISSION_DENIED", "VPN permission denied", null)
                }
                pendingResult = null
                true
            } else false
        }
    }

    override fun onDetachedFromActivity() { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
}
