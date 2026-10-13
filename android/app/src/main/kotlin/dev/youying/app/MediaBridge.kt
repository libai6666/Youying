package dev.youying.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry
import java.io.File

/** Newly written Media3 bridge. Names/arguments/events follow the recovered
 * g1/b.java, g1/f.java and g1/i.java. No original app dex or native code is
 * bundled in the reconstructed project.
 */
class MediaBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    registry: PlatformViewRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "flutter_player_av/methods")
    private val events = EventChannel(messenger, "flutter_player_av/events")
    private val players = mutableMapOf<Long, ExoPlayer>()
    private val views = mutableMapOf<Long, MutableSet<PlayerView>>()
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var active = true
    private val ticker = object : Runnable {
        override fun run() {
            if (!active) return
            for ((id, player) in players) {
                if (player.playbackState != Player.STATE_IDLE) {
                    notify(id, "position", player.currentPosition.coerceAtLeast(0))
                    if (player.duration > 0) notify(id, "duration", player.duration)
                    notify(id, "buffer", player.bufferedPosition.coerceAtLeast(0))
                }
            }
            handler.postDelayed(this, 250)
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        registry.registerViewFactory("flutter_player_av/player_view", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                val id = (args as? Map<*, *>)?.get("playerId") as? Number
                    ?: throw IllegalArgumentException("playerId is required")
                val key = id.toLong()
                val view = PlayerView(context).apply {
                    useController = false
                    player = players[key] ?: makePlayer(key)
                }
                views.getOrPut(key) { mutableSetOf() }.add(view)
                return object : PlatformView {
                    override fun getView(): View = view
                    override fun dispose() {
                        view.player = null
                        views[key]?.remove(view)
                    }
                }
            }
        })
        handler.post(ticker)
    }

    private fun notify(id: Long, type: String, value: Any) {
        sink?.success(mapOf("playerId" to id, "type" to type, "value" to value))
    }

    private fun makePlayer(id: Long): ExoPlayer = players.getOrPut(id) {
        ExoPlayer.Builder(context).build().also { player ->
            player.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    notify(id, "playing", isPlaying)
                }

                override fun onPlaybackStateChanged(state: Int) {
                    notify(id, "buffering", state == Player.STATE_BUFFERING)
                    if (state == Player.STATE_READY) notify(id, "loaded", true)
                    if (state == Player.STATE_ENDED) notify(id, "completed", true)
                }

                override fun onPlayerError(error: PlaybackException) {
                    notify(id, "error", mapOf("domain" to "Media3", "code" to error.errorCode))
                }
            })
        }
    }

    private fun mediaItem(uri: Uri): MediaItem {
        val path = uri.path?.lowercase() ?: ""
        val mime = when {
            path.endsWith(".m3u8") || path.contains("/m3u8/") -> MimeTypes.APPLICATION_M3U8
            path.endsWith(".mpd") -> MimeTypes.APPLICATION_MPD
            else -> null
        }
        return MediaItem.Builder().setUri(uri).setMimeType(mime).build()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val data = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("arguments required")
            val id = (data["playerId"] as? Number)?.toLong()
                ?: throw IllegalArgumentException("playerId required")
            if (!active) throw IllegalStateException("Bridge already disposed")
            if (call.method == "dispose") {
                views.remove(id)?.forEach { it.player = null }
                players.remove(id)?.release()
                result.success(null)
                return
            }
            if (call.method == "create") {
                makePlayer(id)
                result.success(null)
                return
            }
            val player = makePlayer(id)
            when (call.method) {
                "open" -> {
                    val file = data["filePath"] as? String
                    val url = data["url"] as? String
                    val uri = if (!file.isNullOrBlank()) Uri.fromFile(File(file)) else {
                        require(!url.isNullOrBlank()) { "Missing media address" }
                        require(Uri.parse(url).scheme == "https") { "HTTPS media required" }
                        Uri.parse(url)
                    }
                    val headers = (data["headers"] as? Map<*, *>)?.entries?.mapNotNull { item ->
                        val k = item.key as? String
                        val v = item.value as? String
                        if (k == null || v == null || k.contains('\r') || k.contains('\n') ||
                            v.contains('\r') || v.contains('\n')) null else k to v
                    }?.toMap() ?: emptyMap()
                    val factory = DefaultHttpDataSource.Factory()
                        .setAllowCrossProtocolRedirects(false)
                        .setDefaultRequestProperties(headers)
                    player.setMediaSource(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, factory))
                        .createMediaSource(mediaItem(uri)))
                    player.seekTo((data["startMs"] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0)
                    notify(id, "hasMedia", true)
                    player.prepare()
                    player.playWhenReady = data["play"] != false
                }
                "play" -> player.play()
                "pause" -> player.pause()
                "seek" -> player.seekTo(((data["positionMs"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("positionMs required")).coerceAtLeast(0))
                "stop" -> player.stop()
                "setRate" -> {
                    val rate = (data["rate"] as? Number)?.toFloat() ?: 0f
                    require(rate.isFinite() && rate > 0f) { "Invalid rate" }
                    player.setPlaybackSpeed(rate)
                    notify(id, "rate", rate)
                }
                "setBoxFit" -> {
                    val mode = if (data["fit"] == "cover") AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        else AspectRatioFrameLayout.RESIZE_MODE_FIT
                    views[id]?.forEach { it.resizeMode = mode }
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (_: Exception) {
            result.error("MEDIA3_ERROR", "播放器请求失败，请检查参数和网络", null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        for ((id, player) in players) {
            notify(id, "playing", player.isPlaying)
            notify(id, "buffering", player.playbackState == Player.STATE_BUFFERING)
            if (player.duration > 0) notify(id, "duration", player.duration)
        }
    }
    override fun onCancel(arguments: Any?) { sink = null }

    fun pauseAll() { players.values.forEach { it.pause() } }

    fun dispose() {
        active = false
        handler.removeCallbacks(ticker)
        sink = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        views.values.flatten().forEach { it.player = null }
        views.clear()
        players.values.forEach { it.release() }
        players.clear()
    }
}
