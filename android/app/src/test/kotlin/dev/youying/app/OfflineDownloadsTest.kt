package dev.youying.app

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.hls.offline.HlsDownloader
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.Collections
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class OfflineDownloadsTest {
    @get:Rule val folder = TemporaryFolder()
    private val uri = Uri.parse("https://fixture.test/video.m3u8")

    private fun manifest(key: String = ""): ByteArray = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        $key
        #EXTINF:4,
        segment.ts
        #EXT-X-ENDLIST
    """.trimIndent().toByteArray()

    @Test fun allowedAes128AndPlainVodParse() {
        OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest()))
        OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest("#EXT-X-KEY:METHOD=AES-128,URI=\"key\"")))
    }

    @Test fun drmAndSampleEncryptionAreDistinct() {
        val drm = assertThrows(OfflineFormatException::class.java) {
            OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest("#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"license\",KEYFORMAT=\"com.widevine\"")))
        }
        assertEquals("DRM_OFFLINE_LICENSE_REQUIRED", drm.reason)
        val sample = assertThrows(OfflineFormatException::class.java) {
            OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest("#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"")))
        }
        assertEquals("HLS_ENCRYPTION_UNSUPPORTED", sample.reason)
    }

    @Test fun malformedKeyDeclarationsFailClosed() {
        for (tag in listOf("#EXT-X-KEY:METHOD=AES-128", "#EXT-X-KEY:METHOD=AES-128,METHOD=NONE,URI=\"key\"", "#EXT-X-KEY:URI=\"key\"")) {
            val error = assertThrows(OfflineFormatException::class.java) {
                OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest(tag)))
            }
            assertEquals("MANIFEST_INVALID", error.reason)
        }
    }

    @Test fun liveAndOversizedPlaylistsAreRejected() {
        val live = assertThrows(OfflineFormatException::class.java) {
            OfflinePlaylistParser().parse(uri, ByteArrayInputStream(manifest().toString(Charsets.UTF_8).replace("#EXT-X-ENDLIST", "").toByteArray()))
        }
        assertEquals("LIVE_UNSUPPORTED", live.reason)
        val large = assertThrows(OfflineFormatException::class.java) {
            OfflinePlaylistParser().parse(uri, ByteArrayInputStream(ByteArray(2 * 1024 * 1024 + 1)))
        }
        assertEquals("MANIFEST_TOO_LARGE", large.reason)
    }

    @Test fun insecureSegmentIsRejectedBeforeTransport() {
        val source = offlineHttpFactory(uri, emptyMap()).createDataSource()
        val error = assertThrows(OfflineFormatException::class.java) {
            source.open(DataSpec(Uri.parse("http://fixture.test/segment.ts")))
        }
        assertEquals("HTTPS_REQUIRED", error.reason)
        source.close()
    }

    @Test fun aes128DownloadsManifestKeyAndSegmentThenReadsWithNoNetwork() {
        val key = ByteArray(16) { it.toByte() }
        val iv = ByteArray(16)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val segment = cipher.doFinal(ByteArray(512) { (it % 251).toByte() })
        val playlist = manifest("#EXT-X-KEY:METHOD=AES-128,URI=\"key\",IV=0x00000000000000000000000000000000")
        val files = mapOf(uri.toString() to playlist, "https://fixture.test/key" to key, "https://fixture.test/segment.ts" to segment)
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val upstream = DataSource.Factory { FixtureDataSource(files, requested) }
        val db = StandaloneDatabaseProvider(RuntimeEnvironment.getApplication())
        val directory = folder.newFolder("cache")
        val executor = Executors.newFixedThreadPool(3)
        var cache = SimpleCache(directory, NoOpCacheEvictor(), db)
        try {
            val factory = downloadCacheFactory(cache, "episode-1").setUpstreamDataSourceFactory(upstream)
            val downloader = HlsDownloader(MediaItem.fromUri(uri), OfflinePlaylistParser(), factory, executor, 0L)
            downloader.download(null)
            assertEquals(files.keys, requested.toSet())
            val second = downloadCacheFactory(cache, "episode-2").setUpstreamDataSourceFactory(upstream)
            HlsDownloader(MediaItem.fromUri(uri), OfflinePlaylistParser(), second, executor, 0L).download(null)
            downloader.remove()
            cache.release()
            cache = SimpleCache(directory, NoOpCacheEvictor(), db)
            val offline = downloadCacheFactory(cache, "episode-2").setUpstreamDataSourceFactory(null).setCacheWriteDataSinkFactory(null)
            for ((url, bytes) in files) assertArrayEquals(bytes, read(offline.createDataSource(), Uri.parse(url)))
            assertThrows(IOException::class.java) { read(offline.createDataSource(), Uri.parse("https://fixture.test/not-cached")) }
        } finally { cache.release(); executor.shutdownNow(); db.close() }
    }

    @Test fun drmDownloadNeverRequestsKeyOrLicense() {
        val playlist = manifest("#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"license\",KEYFORMAT=\"com.widevine\"")
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val db = StandaloneDatabaseProvider(RuntimeEnvironment.getApplication())
        val cache = SimpleCache(folder.newFolder("drm"), NoOpCacheEvictor(), db)
        val executor = Executors.newFixedThreadPool(1)
        try {
            val factory = CacheDataSource.Factory().setCache(cache).setUpstreamDataSourceFactory(DataSource.Factory { FixtureDataSource(mapOf(uri.toString() to playlist), requested) })
            val downloader = HlsDownloader(MediaItem.fromUri(uri), OfflinePlaylistParser(), factory, executor, 0L)
            val error = assertThrows(OfflineFormatException::class.java) { downloader.download(null) }
            assertEquals("DRM_OFFLINE_LICENSE_REQUIRED", error.reason)
            assertEquals(listOf(uri.toString()), requested)
        } finally { cache.release(); executor.shutdownNow(); db.close() }
    }

    private fun read(source: DataSource, uri: Uri): ByteArray {
        try {
            source.open(DataSpec(uri))
            val output = ByteArrayOutputStream()
            val bytes = ByteArray(4096)
            while (true) { val count = source.read(bytes, 0, bytes.size); if (count == C.RESULT_END_OF_INPUT) break; output.write(bytes, 0, count) }
            return output.toByteArray()
        } finally { source.close() }
    }
}

private class FixtureDataSource(private val files: Map<String, ByteArray>, private val requests: MutableList<String>) : DataSource {
    private var stream: ByteArrayInputStream? = null
    private var uri: Uri? = null
    override fun addTransferListener(listener: TransferListener) {}
    override fun getUri(): Uri? = uri
    override fun open(spec: DataSpec): Long {
        uri = spec.uri
        requests.add(spec.uri.toString())
        val bytes = files[spec.uri.toString()] ?: throw IOException("Unexpected fixture request")
        val position = spec.position.toInt()
        val size = if (spec.length == C.LENGTH_UNSET.toLong()) bytes.size - position else minOf(spec.length.toInt(), bytes.size - position)
        stream = ByteArrayInputStream(bytes, position, size)
        return size.toLong()
    }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = stream!!.read(buffer, offset, length)
    override fun close() { stream?.close(); stream = null }
}
