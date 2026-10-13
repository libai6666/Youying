package dev.youying.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaBridge: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaBridge = MediaBridge(this, flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.platformViewsController.registry)
    }

    override fun onStop() {
        mediaBridge?.pauseAll()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaBridge?.dispose()
        mediaBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
