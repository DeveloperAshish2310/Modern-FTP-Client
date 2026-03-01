import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

/// Database helper for managing SQLite database
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), AppConstants.dbName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Connections table
    await db.execute('''
      CREATE TABLE connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        password TEXT,
        protocol TEXT NOT NULL,
        is_favorite INTEGER DEFAULT 0,
        ssh_key_path TEXT,
        remote_directory TEXT DEFAULT '/',
        created_at INTEGER NOT NULL,
        last_used INTEGER
      )
    ''');

    // Transfer history table
    await db.execute('''
      CREATE TABLE transfer_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        connection_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        transfer_type TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        error_message TEXT,
        FOREIGN KEY (connection_id) REFERENCES connections (id) ON DELETE CASCADE
      )
    ''');

    // Settings table
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Editor extensions table
    await db.execute('''
      CREATE TABLE editor_extensions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        extension TEXT UNIQUE NOT NULL
      )
    ''');

    // Insert default text extensions
    for (String ext in AppConstants.defaultTextExtensions) {
      await db.insert('editor_extensions', {'extension': ext});
    }

    // Insert default settings
    await db.insert('settings', {'key': 'theme_mode', 'value': 'dark'});
    await db.insert('settings', {'key': 'accent_color', 'value': 'Blue'});
    await db.insert('settings', {'key': 'animations_enabled', 'value': 'true'});
    await db.insert('settings', {'key': 'app_lock_enabled', 'value': 'false'});
    await db.insert('settings', {'key': 'biometric_enabled', 'value': 'false'});
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE connections ADD COLUMN remote_directory TEXT DEFAULT "/"',
      );
    }
  }

  // Connection CRUD operations
  Future<int> insertConnection(Map<String, dynamic> connection) async {
    final db = await database;
    return await db.insert('connections', connection);
  }

  Future<List<Map<String, dynamic>>> getConnections() async {
    final db = await database;
    return await db.query('connections', orderBy: 'is_favorite DESC, name ASC');
  }

  Future<Map<String, dynamic>?> getConnection(int id) async {
    final db = await database;
    final results = await db.query(
      'connections',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateConnection(int id, Map<String, dynamic> connection) async {
    final db = await database;
    return await db.update(
      'connections',
      connection,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteConnection(int id) async {
    final db = await database;
    return await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  // Transfer history CRUD operations
  Future<int> insertTransfer(Map<String, dynamic> transfer) async {
    final db = await database;
    return await db.insert('transfer_history', transfer);
  }

  Future<List<Map<String, dynamic>>> getTransferHistory({
    int? connectionId,
    int limit = 50,
  }) async {
    final db = await database;
    if (connectionId != null) {
      return await db.query(
        'transfer_history',
        where: 'connection_id = ?',
        whereArgs: [connectionId],
        orderBy: 'started_at DESC',
        limit: limit,
      );
    }
    return await db.query(
      'transfer_history',
      orderBy: 'started_at DESC',
      limit: limit,
    );
  }

  Future<int> updateTransfer(int id, Map<String, dynamic> transfer) async {
    final db = await database;
    return await db.update(
      'transfer_history',
      transfer,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Settings operations
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  Future<int> setSetting(String key, String value) async {
    final db = await database;
    return await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Editor extensions operations
  Future<List<String>> getEditorExtensions() async {
    final db = await database;
    final results = await db.query('editor_extensions');
    return results.map((e) => e['extension'] as String).toList();
  }

  Future<int> addEditorExtension(String extension) async {
    final db = await database;
    return await db.insert('editor_extensions', {
      'extension': extension.toLowerCase(),
    });
  }

  Future<int> removeEditorExtension(String extension) async {
    final db = await database;
    return await db.delete(
      'editor_extensions',
      where: 'extension = ?',
      whereArgs: [extension.toLowerCase()],
    );
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
