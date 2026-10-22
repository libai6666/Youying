package dev.youying.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaBridge: MediaBridge? = null
    private var downloadBridge: DownloadBridge? = null
    private var castBridge: CastBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaBridge = MediaBridge(this, flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.platformViewsController.registry)
        downloadBridge = DownloadBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        castBridge = CastBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onStop() {
        mediaBridge?.pauseAll()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        downloadBridge?.dispose()
        downloadBridge = null
        mediaBridge?.dispose()
        mediaBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
