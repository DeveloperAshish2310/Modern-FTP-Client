/// SSH Service - command execution and interactive shells over SSH.
///
/// Used by the server dashboard (stats), terminal and command triggers.
/// SFTP connections share [openSshClient] so auth and retry behave the same.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/connection_model.dart';

/// Open an authenticated SSH client for [connection].
///
/// Retries when the server drops the connection during the handshake
/// (SSHAuthAbortError), which sshd does transiently under MaxStartups or
/// right after previous sessions were killed. Wrong credentials
/// (SSHAuthFailError) are not retried.
Future<SSHClient> openSshClient(ConnectionModel connection) async {
  const maxAttempts = 3;
  for (var attempt = 1; ; attempt++) {
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: const Duration(seconds: 30),
      );

      final keyPath = connection.sshKeyPath;
      if (keyPath != null && keyPath.isNotEmpty) {
        final keyFile = File(keyPath);
        if (!await keyFile.exists()) {
          socket.close();
          throw Exception('SSH key file not found');
        }
        client = SSHClient(
          socket,
          username: connection.username,
          identities: [...SSHKeyPair.fromPem(await keyFile.readAsString())],
        );
      } else {
        client = SSHClient(
          socket,
          username: connection.username,
          onPasswordRequest: () => connection.password ?? '',
        );
      }

      await client.authenticated;
      return client;
    } on SSHAuthAbortError {
      client?.close();
      if (attempt >= maxAttempts) rethrow;
      debugPrint('SSH handshake dropped (attempt $attempt), retrying...');
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
}

/// Quote [s] for a POSIX shell
String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// Result of a completed remote command
class CommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;

  CommandResult(this.stdout, this.stderr, this.exitCode);

  bool get success => exitCode == 0;

  static final _permission = RegExp(
    r'permission denied|operation not permitted|must be root|'
    r'interactive authentication required|access denied|are you root|'
    r'not in the sudoers',
    caseSensitive: false,
  );

  static final _sudoNeedsPassword = RegExp(
    r'a password is required|incorrect password|a terminal is required',
    caseSensitive: false,
  );

  /// The command failed because the user lacks privileges
  bool get permissionDenied => !success && _permission.hasMatch(stderr);

  /// The command (or a tool it calls) isn't installed
  bool get commandNotFound =>
      exitCode == 127 ||
      RegExp(r'command not found|not found$', multiLine: true).hasMatch(stderr);

  /// sudo refused: no saved password, wrong password, or no sudo rights
  bool get sudoFailed => !success && _sudoNeedsPassword.hasMatch(stderr);

  /// stderr, falling back to stdout, trimmed for display
  String get message {
    final text = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    return text.isEmpty ? 'Exit code $exitCode' : text;
  }
}

/// A single SSH connection used for running commands and opening shells
class SshService {
  final ConnectionModel connection;
  SSHClient? _client;

  SshService(this.connection);

  bool get isConnected => _client != null && !_client!.isClosed;

  bool get isRoot => connection.username == 'root';

  bool get hasPassword => connection.password?.isNotEmpty == true;

  Future<void> connect() async {
    if (isConnected) return;
    _client = await openSshClient(connection);
  }

  Future<SSHClient> _ensureClient() async {
    if (!isConnected) await connect();
    return _client!;
  }

  /// Run [command] to completion and collect its output
  Future<CommandResult> run(String command) async {
    final session = await execute(command);
    final out = session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final err = session.stderr.cast<List<int>>().transform(utf8.decoder).join();
    final results = await Future.wait([out, err, session.done]);
    return CommandResult(
      results[0] as String,
      results[1] as String,
      session.exitCode,
    );
  }

  /// Run [command]; if it fails for lack of privileges, retry it as root
  /// via sudo. [elevated] reports whether the sudo retry was used.
  Future<CommandResult> runElevated(
    String command, {
    void Function(bool elevated)? onElevated,
  }) async {
    final result = await run(command);
    if (!result.permissionDenied || isRoot) return result;
    onElevated?.call(true);
    return run('sudo sh -c ${shellQuote(command)}');
  }

  /// Start [command] and return the session so output can be streamed.
  ///
  /// `sudo` has no terminal to prompt on here, so it's rewritten: with a
  /// saved password, `sudo -S` reads it from stdin (never visible in the
  /// command line or process list); without one, `sudo -n` fails fast
  /// instead of hanging on a prompt.
  Future<SSHSession> execute(String command) async {
    final client = await _ensureClient();
    final sudo = RegExp(r'(^|[;&|(]\s*)sudo\s');
    final usesSudo = sudo.hasMatch(command);
    if (usesSudo) {
      command = command.replaceAllMapped(
        sudo,
        (m) => hasPassword ? '${m[1]}sudo -S -p "" ' : '${m[1]}sudo -n ',
      );
    }
    final session = await client.execute(command);
    if (usesSudo && hasPassword) {
      session.write(utf8.encode('${connection.password}\n'));
      // EOF so a wrong password fails instead of waiting for another try
      unawaited(session.stdin.close());
    }
    return session;
  }

  /// Open an interactive login shell with a PTY of the given size
  Future<SSHSession> shell({required int width, required int height}) async {
    final client = await _ensureClient();
    return client.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: width, height: height),
    );
  }

  void close() {
    _client?.close();
    _client = null;
  }
}

/// Human-readable explanation for a failed privileged command
String describeSudoFailure(SshService ssh, CommandResult result) {
  if (!ssh.hasPassword) {
    return 'This needs root access. Save the password for this server '
        '(Edit) so the app can use sudo, or allow passwordless sudo for '
        '${ssh.connection.username}.';
  }
  if (result.stderr.toLowerCase().contains('incorrect password')) {
    return 'sudo rejected the saved password.';
  }
  if (result.stderr.toLowerCase().contains('not in the sudoers')) {
    return '${ssh.connection.username} is not allowed to use sudo on this '
        'server.';
  }
  return result.message;
}
