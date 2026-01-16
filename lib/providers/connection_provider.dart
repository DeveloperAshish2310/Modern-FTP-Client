import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import '../models/connection_model.dart';

/// Provider for managing connections
class ConnectionProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ConnectionModel> _connections = [];
  ConnectionModel? _selectedConnection;
  bool _isLoading = false;

  List<ConnectionModel> get connections => _connections;
  List<ConnectionModel> get favorites =>
      _connections.where((c) => c.isFavorite).toList();
  List<ConnectionModel> get nonFavorites =>
      _connections.where((c) => !c.isFavorite).toList();
  ConnectionModel? get selectedConnection => _selectedConnection;
  bool get isLoading => _isLoading;

  /// Load connections from database
  Future<void> loadConnections() async {
    _isLoading = true;
    notifyListeners();

    try {
      final connectionMaps = await _dbHelper.getConnections();
      _connections = connectionMaps
          .map((map) => ConnectionModel.fromMap(map))
          .toList();
    } catch (e) {
      print('Error loading connections: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add new connection
  Future<bool> addConnection(ConnectionModel connection) async {
    try {
      final id = await _dbHelper.insertConnection(connection.toMap());
      if (id > 0) {
        await loadConnections();
        return true;
      }
      return false;
    } catch (e) {
      print('Error adding connection: $e');
      return false;
    }
  }

  /// Update connection
  Future<bool> updateConnection(ConnectionModel connection) async {
    if (connection.id == null) return false;

    try {
      final result = await _dbHelper.updateConnection(
        connection.id!,
        connection.toMap(),
      );
      if (result > 0) {
        await loadConnections();
        return true;
      }
      return false;
    } catch (e) {
      print('Error updating connection: $e');
      return false;
    }
  }

  /// Delete connection
  Future<bool> deleteConnection(int id) async {
    try {
      final result = await _dbHelper.deleteConnection(id);
      if (result > 0) {
        await loadConnections();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting connection: $e');
      return false;
    }
  }

  /// Toggle favorite status
  Future<bool> toggleFavorite(ConnectionModel connection) async {
    if (connection.id == null) return false;

    final updated = connection.copyWith(isFavorite: !connection.isFavorite);
    return await updateConnection(updated);
  }

  /// Update last used timestamp
  Future<void> updateLastUsed(int id) async {
    try {
      final connection = _connections.firstWhere((c) => c.id == id);
      final updated = connection.copyWith(lastUsed: DateTime.now());
      await _dbHelper.updateConnection(id, updated.toMap());
    } catch (e) {
      print('Error updating last used: $e');
    }
  }

  /// Set selected connection
  void selectConnection(ConnectionModel? connection) {
    _selectedConnection = connection;
    notifyListeners();
  }
}
