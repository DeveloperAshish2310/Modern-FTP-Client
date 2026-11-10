/// Native SFTP - Android platform-channel bridge to JSch.
///
/// Large downloads through dartssh2 buffer data on the Dart heap and can run
/// out of memory; the native side streams straight to disk with hardware
/// crypto instead. See android/.../NativeSftp.kt.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/connection_model.dart';

class NativeSftp {
  static const MethodChannel _channel = MethodChannel(
    'com.ftpclient/native_sftp',
  );

  static final Map<int, void Function(int, int)> _progressHandlers = {};
  static int _nextId = 1;
  static bool _initialized = false;

  static bool get isSupported => Platform.isAndroid;

  static void _ensureInit() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = call.arguments as Map;
        _progressHandlers[args['id'] as int]?.call(
          args['bytes'] as int,
          args['total'] as int,
        );
      }
    });
  }

  /// Download [remotePath] to [localPath] on a dedicated native connection.
  /// With [resume], continues an existing partial file instead of
  /// overwriting it. Returns bytes transferred; throws
  /// `Exception('Cancelled')` on cancel.
  static Future<int> download({
    required ConnectionModel connection,
    required String remotePath,
    required String localPath,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
    bool resume = false,
  }) => _transfer(
    'download',
    connection: connection,
    remotePath: remotePath,
    localPath: localPath,
    onProgress: onProgress,
    isCancelled: isCancelled,
    resume: resume,
  );

  /// Upload [localPath] to [remotePath], overwriting it.
  /// Returns bytes transferred; throws `Exception('Cancelled')` on cancel.
  static Future<int> upload({
    required ConnectionModel connection,
    required String localPath,
    required String remotePath,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) => _transfer(
    'upload',
    connection: connection,
    remotePath: remotePath,
    localPath: localPath,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  static Future<int> _transfer(
    String method, {
    required ConnectionModel connection,
    required String remotePath,
    required String localPath,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
    bool resume = false,
  }) async {
    _ensureInit();
    final id = _nextId++;
    if (onProgress != null) _progressHandlers[id] = onProgress;

    Timer? cancelPoll;
    if (isCancelled != null) {
      cancelPoll = Timer.periodic(const Duration(milliseconds: 300), (t) {
        if (isCancelled()) {
          t.cancel();
          _channel.invokeMethod('cancel', {'id': id});
        }
      });
    }

    try {
      return await _channel.invokeMethod<int>(method, {
            'id': id,
            'host': connection.host,
            'port': connection.port,
            'username': connection.username,
            'password': connection.password,
            'keyPath': connection.sshKeyPath,
            'remotePath': remotePath,
            'localPath': localPath,
            'resume': resume,
          }) ??
          0;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') throw Exception('Cancelled');
      throw Exception(e.message ?? e.code);
    } finally {
      cancelPoll?.cancel();
      _progressHandlers.remove(id);
    }
  }
}
