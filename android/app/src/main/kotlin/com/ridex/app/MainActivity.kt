package com.ridex.app

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ridex/maps_configuration",
        ).setMethodCallHandler { call, result ->
            if (call.method == "isConfigured") {
                result.success(hasMapsApiKey())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun hasMapsApiKey(): Boolean {
        val applicationInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA,
        )
        val key = applicationInfo.metaData?.getString("com.google.android.geo.API_KEY")
        return !key.isNullOrBlank()
    }
}
