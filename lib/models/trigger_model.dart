/// A saved SSH command that can be run with one tap.
class TriggerModel {
  final int? id;
  final int connectionId;
  final String name;
  final String command;

  /// Ask "Run this command?" before executing (for destructive commands)
  final bool confirm;
  final DateTime createdAt;

  TriggerModel({
    this.id,
    required this.connectionId,
    required this.name,
    required this.command,
    this.confirm = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'connection_id': connectionId,
      'name': name,
      'command': command,
      'confirm': confirm ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TriggerModel.fromMap(Map<String, dynamic> map) {
    return TriggerModel(
      id: map['id'] as int?,
      connectionId: map['connection_id'] as int,
      name: map['name'] as String,
      command: map['command'] as String,
      confirm: (map['confirm'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  TriggerModel copyWith({String? name, String? command, bool? confirm}) {
    return TriggerModel(
      id: id,
      connectionId: connectionId,
      name: name ?? this.name,
      command: command ?? this.command,
      confirm: confirm ?? this.confirm,
      createdAt: createdAt,
    );
  }
}
