import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeAppStorage {
  const NativeAppStorage({
    MethodChannel channel = const MethodChannel('plateq.app/storage'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String?> readJson(String key) async {
    try {
      return _channel.invokeMethod<String>('readJson', <String, Object?>{
        'key': key,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    }
  }

  Future<bool> writeJson(String key, String json) async {
    try {
      return await _channel.invokeMethod<bool>('writeJson', <String, Object?>{
            'key': key,
            'json': json,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on FlutterError {
      return false;
    }
  }

  Future<bool> clearJson(String key) async {
    try {
      return await _channel.invokeMethod<bool>('clearJson', <String, Object?>{
            'key': key,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on FlutterError {
      return false;
    }
  }
}
