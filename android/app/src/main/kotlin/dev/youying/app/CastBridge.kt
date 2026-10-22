package dev.youying.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.Executors

/**
 * Minimal DLNA/UPnP casting bridge: SSDP discovery of MediaRenderer devices
 * plus AVTransport SetAVTransportURI / Play / Stop. Implemented without the
 * jUPnP dependency — the protocol surface we need is small and
 * deterministic.
 */
class CastBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "dev.youying.app/cast")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "discover" -> executor.execute {
                    try {
                        val devices = discover()
                        post(result) { success(devices) }
                    } catch (error: Throwable) {
                        post(result) { this.error("discover", error.message, null) }
                    }
                }
                "cast" -> executor.execute {
                    try {
                        val device = call.argument<Map<String, String>>("device")
                            ?: throw IllegalArgumentException("device required")
                        soap(
                            device["controlUrl"]!!,
                            "SetAVTransportURI",
                            "<CurrentURI>${xml(call.argument<String>("url")!!)}</CurrentURI>" +
                                "<CurrentURIMetaData>${xml(didl(call.argument<String>("title") ?: ""))}</CurrentURIMetaData>"
                        )
                        soap(device["controlUrl"]!!, "Play", "<Speed>1</Speed>")
                        post(result) { success(true) }
                    } catch (error: Throwable) {
                        post(result) { this.error("cast", error.message, null) }
                    }
                }
                "stop" -> executor.execute {
                    try {
                        val control = call.argument<String>("controlUrl")
                            ?: throw IllegalArgumentException("controlUrl required")
                        soap(control, "Stop", "")
                        post(result) { success(true) }
                    } catch (error: Throwable) {
                        post(result) { this.error("stop", error.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun post(result: MethodChannel.Result, block: MethodChannel.Result.() -> Unit) =
        mainHandler.post { result.block() }

    /** M-SEARCH for AVTransport renderers; returns [{name, controlUrl}]. */
    private fun discover(): List<Map<String, String>> {
        val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("youying-cast").apply {
            setReferenceCounted(true)
            acquire()
        }
        try {
            val query = "M-SEARCH * HTTP/1.1\r\n" +
                "HOST: 239.255.255.250:1900\r\n" +
                "MAN: \"ssdp:discover\"\r\n" +
                "MX: 3\r\n" +
                "ST: urn:schemas-upnp-org:service:AVTransport:1\r\n\r\n"
            val locations = linkedSetOf<String>()
            DatagramSocket().use { socket ->
                socket.soTimeout = 600
                val target = InetSocketAddress(InetAddress.getByName("239.255.255.250"), 1900)
                repeat(3) {
                    socket.send(DatagramPacket(query.toByteArray(), query.length, target))
                }
                val deadline = System.currentTimeMillis() + 4000
                val buffer = ByteArray(4096)
                while (System.currentTimeMillis() < deadline) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        val text = String(packet.data, packet.offset, packet.length)
                        Regex("LOCATION:\\s*(\\S+)", RegexOption.IGNORE_CASE)
                            .find(text)?.groupValues?.get(1)?.let(locations::add)
                    } catch (_: SocketTimeoutException) {
                    }
                }
            }
            return locations.mapNotNull(::describe)
        } finally {
            if (lock.isHeld) lock.release()
        }
    }

    /** Fetches the device description and extracts friendlyName + controlURL. */
    private fun describe(location: String): Map<String, String>? {
        return try {
            val body = URL(location).openStream().use { it.readBytes().toString(Charsets.UTF_8) }
            val name = Regex("<friendlyName>(.*?)</friendlyName>", RegexOption.DOT_MATCHES_ALL)
                .find(body)?.groupValues?.get(1)?.trim() ?: return null
            val service = Regex(
                "<service>\\s*<serviceType>urn:schemas-upnp-org:service:AVTransport:\\d" +
                    "</serviceType>.*?<controlURL>(.*?)</controlURL>",
                RegexOption.DOT_MATCHES_ALL
            ).find(body)?.groupValues?.get(1)?.trim() ?: return null
            mapOf(
                "name" to name,
                "controlUrl" to URL(URL(location), service).toString()
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun soap(controlUrl: String, action: String, inner: String) {
        val envelope = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" " +
            "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            "<s:Body><u:$action xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">" +
            "<InstanceID>0</InstanceID>$inner</u:$action></s:Body></s:Envelope>"
        val connection = URL(controlUrl).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("Content-Type", "text/xml; charset=\"utf-8\"")
            connection.setRequestProperty(
                "SOAPACTION", "\"urn:schemas-upnp-org:service:AVTransport:1#$action\"")
            connection.outputStream.use { it.write(envelope.toByteArray(Charsets.UTF_8)) }
            if (connection.responseCode !in 200..299) {
                throw java.io.IOException("SOAP $action -> ${connection.responseCode}")
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun xml(value: String) = value
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\"", "&quot;").replace("'", "&apos;")

    private fun didl(title: String) =
        "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" " +
            "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" " +
            "xmlns:dc=\"http://purl.org/dc/elements/1.1/\">" +
            "<item id=\"0\" parentID=\"-1\" restricted=\"1\">" +
            "<dc:title>$title</dc:title>" +
            "<upnp:class>object.item.videoItem</upnp:class>" +
            "<res protocolInfo=\"*:*:*:*\"></res></item></DIDL-Lite>"
}
