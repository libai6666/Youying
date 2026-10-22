package dev.youying.app

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MimeTypes
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.hls.offline.HlsDownloader
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParser
import androidx.media3.exoplayer.offline.DefaultDownloadIndex
import androidx.media3.exoplayer.offline.DefaultDownloaderFactory
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.offline.DownloaderFactory
import androidx.media3.exoplayer.scheduler.Requirements
import androidx.media3.exoplayer.scheduler.Scheduler
import androidx.media3.exoplayer.upstream.ParsingLoadable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal class OfflineFormatException(val reason: String) : IOException(reason)

internal class OfflinePlaylistParser : ParsingLoadable.Parser<HlsPlaylist> {
    override fun parse(uri: Uri, inputStream: InputStream): HlsPlaylist {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = inputStream.read(buffer)
            if (count < 0) break
            if (output.size() + count > 2 * 1024 * 1024) throw OfflineFormatException("MANIFEST_TOO_LARGE")
            output.write(buffer, 0, count)
        }
        val bytes = output.toByteArray()
        val text = bytes.toString(Charsets.UTF_8)
        for (line in text.lineSequence().map { it.trim() }) {
            if (!line.startsWith("#EXT-X-KEY:") && !line.startsWith("#EXT-X-SESSION-KEY:")) continue
            val input = line.substringAfter(':')
            val attributes = mutableMapOf<String, String>()
            var offset = 0
            for (match in Regex("([A-Z0-9-]+)=(\"[^\"\\r\\n]*\"|[^,\\s]+)(?:,|$)").findAll(input)) {
                if (match.range.first != offset || attributes.containsKey(match.groupValues[1])) throw OfflineFormatException("MANIFEST_INVALID")
                attributes[match.groupValues[1]] = match.groupValues[2].trim('"')
                offset = match.range.last + 1
            }
            if (offset != input.length) throw OfflineFormatException("MANIFEST_INVALID")
            val method = attributes["METHOD"] ?: throw OfflineFormatException("MANIFEST_INVALID")
            val format = attributes["KEYFORMAT"] ?: "identity"
            if (format != "identity") throw OfflineFormatException("DRM_OFFLINE_LICENSE_REQUIRED")
            if (method !in setOf("NONE", "AES-128")) {
                throw OfflineFormatException("HLS_ENCRYPTION_UNSUPPORTED")
            }
            if ((method == "AES-128" && attributes["URI"].isNullOrBlank()) ||
                (method == "NONE" && attributes.size != 1)) throw OfflineFormatException("MANIFEST_INVALID")
        }
        val playlist = try { HlsPlaylistParser().parse(uri, ByteArrayInputStream(bytes)) }
            catch (error: IOException) { throw OfflineFormatException("MANIFEST_INVALID") }
            catch (error: IllegalArgumentException) { throw OfflineFormatException("MANIFEST_INVALID") }
        if (playlist is HlsMediaPlaylist && !playlist.hasEndTag) throw OfflineFormatException("LIVE_UNSUPPORTED")
        return playlist
    }
}

internal fun downloadCacheFactory(cache: SimpleCache, id: String): CacheDataSource.Factory =
    CacheDataSource.Factory().setCache(cache).setCacheKeyFactory { spec -> "$id:${spec.key ?: spec.uri}" }

internal fun offlineHttpFactory(root: Uri, headers: Map<String, String>): DataSource.Factory {
    val origin = root.toString().toHttpUrl()
    val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .followSslRedirects(false)
        .addNetworkInterceptor { chain ->
            val request = chain.request()
            val url = request.url
            if (!url.isHttps || url.username.isNotEmpty() || url.password.isNotEmpty()) {
                throw OfflineFormatException("HTTPS_REQUIRED")
            }
            val builder = request.newBuilder()
            // OkHttp runs network interceptors again for each redirect hop.
            if (url.host != origin.host || url.port != origin.port) headers.keys.forEach { builder.removeHeader(it) }
            chain.proceed(builder.build())
        }.build()
    val upstream = OkHttpDataSource.Factory(client).setDefaultRequestProperties(headers)
    return ResolvingDataSource.Factory(upstream, object : ResolvingDataSource.Resolver {
        override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
            val uri = dataSpec.uri
            if (uri.scheme != "https" || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrEmpty()) {
                throw OfflineFormatException("HTTPS_REQUIRED")
            }
            return dataSpec
        }
    })
}

internal class OfflineStore private constructor(private val context: Context) {
    private val preferences = context.getSharedPreferences("offline_downloads", Context.MODE_PRIVATE)
    private val database = StandaloneDatabaseProvider(context)
    val cache = SimpleCache(File(context.filesDir, "media3_downloads"), NoOpCacheEvictor(), database)
    private val executor = Executors.newFixedThreadPool(10)
    private val index = DefaultDownloadIndex(database)
    private val pending = mutableSetOf<String>()
    val manager: DownloadManager
    val listeners = mutableSetOf<() -> Unit>()

    init {
        val factory = DownloaderFactory { request ->
            val metadata = JSONObject(request.data.toString(Charsets.UTF_8))
            val jsonHeaders = metadata.optJSONObject("headers") ?: JSONObject()
            val headers = jsonHeaders.keys().asSequence().associateWith { jsonHeaders.getString(it) }
            val data = downloadCacheFactory(cache, request.id)
                .setUpstreamDataSourceFactory(offlineHttpFactory(request.uri, headers))
                .setFlags(CacheDataSource.FLAG_BLOCK_ON_CACHE)
            if (request.mimeType == MimeTypes.APPLICATION_M3U8) {
                HlsDownloader(request.toMediaItem(), OfflinePlaylistParser(), data, executor, 0L)
            } else DefaultDownloaderFactory(data, executor).createDownloader(request)
        }
        manager = DownloadManager(context, index, factory)
        manager.maxParallelDownloads = preferences.getInt("parallelism", 3).coerceIn(1, 10)
        manager.setRequirements(Requirements(Requirements.NETWORK))
        manager.addListener(object : DownloadManager.Listener {
            override fun onInitialized(downloadManager: DownloadManager) = changed()
            override fun onDownloadChanged(downloadManager: DownloadManager, download: Download, finalException: Exception?) {
                pending.remove(download.request.id)
                if (finalException != null) {
                    val error = generateSequence<Throwable>(finalException) { it.cause }
                        .filterIsInstance<OfflineFormatException>().firstOrNull()?.reason ?: "DOWNLOAD_FAILED"
                    preferences.edit().putString("error:${download.request.id}", error).apply()
                } else if (download.state != Download.STATE_FAILED) {
                    preferences.edit().remove("error:${download.request.id}").apply()
                }
                changed()
            }
            override fun onDownloadRemoved(downloadManager: DownloadManager, download: Download) {
                pending.remove(download.request.id)
                preferences.edit().remove("error:${download.request.id}").apply()
                changed()
            }
            override fun onRequirementsStateChanged(downloadManager: DownloadManager, requirements: Requirements, notMetRequirements: Int) = changed()
        })
    }

    private fun changed() = listeners.toList().forEach { it() }

    fun setParallelism(value: Int) {
        require(value in 1..10) { "并发数必须为 1～10" }
        preferences.edit().putInt("parallelism", value).apply()
        manager.maxParallelDownloads = value
        changed()
    }

    fun snapshot(): Map<String, Any> {
        val records = linkedMapOf<String, Download>()
        index.getDownloads().use { cursor -> while (cursor.moveToNext()) records[cursor.download.request.id] = cursor.download }
        manager.currentDownloads.forEach { records[it.request.id] = it }
        return mapOf("parallelism" to manager.maxParallelDownloads, "tasks" to records.values.sortedByDescending { it.startTimeMs }.map { download ->
            val metadata = JSONObject(download.request.data.toString(Charsets.UTF_8))
            val state = when (download.state) {
                Download.STATE_COMPLETED -> "completed"
                Download.STATE_DOWNLOADING -> "downloading"
                Download.STATE_STOPPED -> "paused"
                Download.STATE_FAILED -> "failed"
                Download.STATE_REMOVING -> "removing"
                else -> "queued"
            }
            mapOf("id" to download.request.id, "entry" to metadata.getJSONObject("entry").toString(),
                "episodeName" to metadata.getString("episodeName"),
                "url" to metadata.optString("url").ifBlank { download.request.uri.toString() },
                "state" to state, "bytes" to download.bytesDownloaded, "total" to download.contentLength,
                "percent" to download.percentDownloaded.toDouble(),
                "waitingForNetwork" to (manager.notMetRequirements != 0),
                "error" to preferences.getString("error:${download.request.id}", "DOWNLOAD_FAILED").orEmpty())
        })
    }

    fun add(items: List<*>) {
        val requests = items.map { item ->
            val map = item as Map<*, *>
            val url = map["url"] as String
            val uri = Uri.parse(url)
            require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo.isNullOrEmpty()) { "只支持 HTTPS 下载" }
            val downloadUri = (map["downloadUrl"] as? String)?.let { candidate ->
                Uri.parse(candidate).also { parsed ->
                    require(parsed.scheme == "https" && !parsed.host.isNullOrEmpty() && parsed.userInfo.isNullOrEmpty()) { "只支持 HTTPS 下载" }
                }
            } ?: uri
            val path = downloadUri.path.orEmpty().lowercase()
            val mime = when {
                path.endsWith(".m3u8") || path.contains("/m3u8/") -> MimeTypes.APPLICATION_M3U8
                path.endsWith(".mp4") -> MimeTypes.VIDEO_MP4
                path.endsWith(".webm") -> MimeTypes.VIDEO_WEBM
                else -> throw IllegalArgumentException("仅支持 MP4、WebM 和 HLS 点播下载")
            }
            val entry = JSONObject(map["entry"] as String)
            val name = map["episodeName"] as String
            val id = MessageDigest.getInstance("SHA-256").digest((entry.getString("id") + "\n" + url).toByteArray())
                .joinToString("") { "%02x".format(it) }
            val headers = JSONObject()
            (map["headers"] as? Map<*, *>)?.forEach { (key, value) ->
                require(key is String && value is String && !key.contains('\n') && !key.contains('\r') && !value.contains('\n') && !value.contains('\r'))
                require(!key.equals("Host", true) && !key.equals("Range", true) && !key.equals("Content-Length", true))
                headers.put(key, value)
            }
            val data = JSONObject().put("entry", entry).put("episodeName", name).put("url", url).put("headers", headers)
            DownloadRequest.Builder(id, downloadUri).setMimeType(mime).setData(data.toString().toByteArray()).build()
        }
        for (request in requests) {
            if (index.getDownload(request.id) != null || !pending.add(request.id)) continue
            try { DownloadService.sendAddDownload(context, OfflineDownloadService::class.java, request, true) }
            catch (error: Exception) { pending.remove(request.id); throw error }
        }
    }

    fun setAllStopReason(reason: Int) {
        DownloadService.sendSetStopReason(context, OfflineDownloadService::class.java, null, reason, true)
    }

    fun command(method: String, id: String) {
        val download = index.getDownload(id) ?: throw IllegalArgumentException("下载任务不存在")
        when (method) {
            "remove" -> DownloadService.sendRemoveDownload(context, OfflineDownloadService::class.java, id, true)
            "pause" -> DownloadService.sendSetStopReason(context, OfflineDownloadService::class.java, id, 1, true)
            "resume", "retry" -> if (download.state == Download.STATE_FAILED) {
                DownloadService.sendAddDownload(context, OfflineDownloadService::class.java, download.request, true)
            } else DownloadService.sendSetStopReason(context, OfflineDownloadService::class.java, id, Download.STOP_REASON_NONE, true)
        }
    }

    fun offlineSource(id: String): androidx.media3.exoplayer.source.MediaSource {
        val download = index.getDownload(id) ?: throw IllegalArgumentException("下载文件不存在")
        check(download.state == Download.STATE_COMPLETED) { "该集尚未下载完成" }
        val source = downloadCacheFactory(cache, id).setUpstreamDataSourceFactory(null).setCacheWriteDataSinkFactory(null)
        return androidx.media3.exoplayer.source.DefaultMediaSourceFactory(source).createMediaSource(download.request.toMediaItem())
    }

    companion object {
        @Volatile private var instance: OfflineStore? = null
        fun get(context: Context): OfflineStore = instance ?: synchronized(this) {
            instance ?: OfflineStore(context.applicationContext).also { instance = it }
        }
    }
}

class OfflineDownloadService : DownloadService(1001, 1000L, "youying_downloads", R.string.download_channel_name, 0) {
    override fun getDownloadManager(): DownloadManager = OfflineStore.get(this).manager
    override fun getScheduler(): Scheduler? = null
    override fun getForegroundNotification(downloads: MutableList<Download>, notMetRequirements: Int): Notification {
        val intent = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return DownloadNotificationHelper(this, "youying_downloads").buildProgressNotification(this,
            android.R.drawable.stat_sys_download, intent, "柚影 · 离线下载", downloads, notMetRequirements)
    }
}

class DownloadBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "youying/downloads/methods")
    private val events = EventChannel(messenger, "youying/downloads/events")
    private val store = OfflineStore.get(activity)
    private var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val changed: () -> Unit = { emit() }
    private val ticker = object : Runnable {
        override fun run() { if (sink != null) { emit(); handler.postDelayed(this, 500) } }
    }
    init { methods.setMethodCallHandler(this); events.setStreamHandler(this) }
    private fun emit() { sink?.success(store.snapshot()) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        store.listeners.add(changed)
        handler.post(ticker)
    }
    override fun onCancel(arguments: Any?) { sink = null; store.listeners.remove(changed); handler.removeCallbacks(ticker) }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val data = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "initialize" -> {
                    DownloadService.start(activity, OfflineDownloadService::class.java)
                    result.success(store.snapshot())
                }
                "enqueue" -> {
                    if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7002)
                    }
                    store.add(data["items"] as List<*>)
                    result.success(null)
                }
                "setParallelism" -> { store.setParallelism((data["value"] as Number).toInt()); result.success(store.snapshot()) }
                "pause", "resume", "retry", "remove" -> { store.command(call.method, data["id"] as String); result.success(null) }
                "pauseAll" -> { store.setAllStopReason(1); result.success(null) }
                "resumeAll" -> { store.setAllStopReason(Download.STOP_REASON_NONE); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("DOWNLOAD_ERROR", if (error is IllegalArgumentException) error.message else "下载任务操作失败，请检查网络或存储空间", null)
        }
    }
    fun dispose() { onCancel(null); methods.setMethodCallHandler(null); events.setStreamHandler(null) }
}
