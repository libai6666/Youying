import 'package:flutter/services.dart';

/// A DLNA MediaRenderer found on the local network via SSDP.
class CastDevice {
  const CastDevice({required this.name, required this.controlUrl});
  final String name;
  final String controlUrl;
}

/// Thin channel over the native DLNA bridge (SSDP + AVTransport SOAP).
class CastClient {
  static const _channel = MethodChannel('dev.youying.app/cast');

  /// Scans the LAN for renderers (~4 s). Empty list when none respond.
  static Future<List<CastDevice>> discover() async {
    final result = await _channel.invokeMethod<List<Object?>>('discover');
    return [
      for (final item in result ?? const <Object?>[])
        if (item is Map)
          CastDevice(
              name: '${item['name']}', controlUrl: '${item['controlUrl']}'),
    ];
  }

  /// Hands [url] to the renderer and starts playback.
  static Future<void> cast(CastDevice device,
      {required String url, required String title}) {
    return _channel.invokeMethod('cast', {
      'device': {'name': device.name, 'controlUrl': device.controlUrl},
      'url': url,
      'title': title,
    });
  }

  static Future<void> stop(CastDevice device) =>
      _channel.invokeMethod('stop', {'controlUrl': device.controlUrl});
}
