/// Model for FTP/SFTP/FTPS connection
class ConnectionModel {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final ConnectionProtocol protocol;
  final bool isFavorite;
  final String? sshKeyPath;
  final String remoteDirectory;
  final DateTime createdAt;
  final DateTime? lastUsed;

  ConnectionModel({
    this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    required this.protocol,
    this.isFavorite = false,
    this.sshKeyPath,
    this.remoteDirectory = '/',
    required this.createdAt,
    this.lastUsed,
  });

  // Convert to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'protocol': protocol.name,
      'is_favorite': isFavorite ? 1 : 0,
      'ssh_key_path': sshKeyPath,
      'remote_directory': remoteDirectory,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_used': lastUsed?.millisecondsSinceEpoch,
    };
  }

  // Create from Map (database result)
  factory ConnectionModel.fromMap(Map<String, dynamic> map) {
    return ConnectionModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      username: map['username'] as String,
      password: map['password'] as String?,
      protocol: ConnectionProtocol.values.firstWhere(
        (e) => e.name == map['protocol'],
        orElse: () => ConnectionProtocol.ftp,
      ),
      isFavorite: (map['is_favorite'] as int) == 1,
      sshKeyPath: map['ssh_key_path'] as String?,
      remoteDirectory: (map['remote_directory'] as String?) ?? '/',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastUsed: map['last_used'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_used'] as int)
          : null,
    );
  }

  // Copy with method for easy updates
  ConnectionModel copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    ConnectionProtocol? protocol,
    bool? isFavorite,
    String? sshKeyPath,
    String? remoteDirectory,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return ConnectionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      protocol: protocol ?? this.protocol,
      isFavorite: isFavorite ?? this.isFavorite,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      remoteDirectory: remoteDirectory ?? this.remoteDirectory,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  @override
  String toString() => 'Connection: $name ($protocol://$host:$port)';
}

/// Connection protocol types
enum ConnectionProtocol { ftp, ftps, sftp }

/// Extension for protocol display
extension ConnectionProtocolExtension on ConnectionProtocol {
  String get displayName {
    switch (this) {
      case ConnectionProtocol.ftp:
        return 'FTP';
      case ConnectionProtocol.ftps:
        return 'FTPS';
      case ConnectionProtocol.sftp:
        return 'SFTP';
    }
  }

  int get defaultPort {
    switch (this) {
      case ConnectionProtocol.ftp:
        return 21;
      case ConnectionProtocol.ftps:
        return 990;
      case ConnectionProtocol.sftp:
        return 22;
    }
  }
}
