package com.ftpclient.ftp_client

import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ftpclient/native_sftp",
        )
        channel.setMethodCallHandler(NativeSftp(channel)::onMethodCall)

        // Index finished downloads so Gallery / Files app can see them
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ftpclient/media")
            .setMethodCallHandler { call, result ->
                if (call.method == "scanFile") {
                    val path = call.argument<String>("path")!!
                    MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
