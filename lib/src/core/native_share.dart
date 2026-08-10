import 'package:flutter/services.dart';

class NativeShare {
  const NativeShare._();

  static const MethodChannel _channel = MethodChannel('plateq.files/share');

  static Future<bool> shareText({
    required String title,
    required String fileName,
    required String mimeType,
    required String text,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'shareText',
        <String, Object?>{
          'title': title,
          'fileName': fileName,
          'mimeType': mimeType,
          'text': text,
        },
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> pickCsv() async {
    try {
      final result = await _channel.invokeMethod<String>('pickCsv');
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
