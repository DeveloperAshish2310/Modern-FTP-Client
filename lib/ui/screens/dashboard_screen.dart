import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../models/connection_model.dart';
import 'add_connection_screen.dart';
import 'file_browser_screen.dart';
import 'transfer_manager_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_vert),
            tooltip: 'Transfers',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransferManagerScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ConnectionProvider>(
        builder: (context, connectionProvider, _) {
          if (connectionProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final favorites = connectionProvider.favorites;
          final nonFavorites = connectionProvider.nonFavorites;
          final filteredFavorites = _filterConnections(favorites);
          final filteredNonFavorites = _filterConnections(nonFavorites);

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search connections...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),

              // Connection lists
              Expanded(
                child: filteredFavorites.isEmpty && filteredNonFavorites.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 80,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No connections yet'
                                  : 'No matching connections',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Tap the + button to add a connection'
                                  : 'Try a different search query',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (filteredFavorites.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'FAVORITES',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ),
                            ...filteredFavorites.map(
                              (conn) => _buildConnectionCard(context, conn),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (filteredNonFavorites.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'ALL CONNECTIONS',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            ...filteredNonFavorites.map(
                              (conn) => _buildConnectionCard(context, conn),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddConnectionScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  List<ConnectionModel> _filterConnections(List<ConnectionModel> connections) {
    if (_searchQuery.isEmpty) return connections;

    final query = _searchQuery.toLowerCase();
    return connections.where((conn) {
      return conn.name.toLowerCase().contains(query) ||
          conn.host.toLowerCase().contains(query) ||
          conn.username.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildConnectionCard(
    BuildContext context,
    ConnectionModel connection,
  ) {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _handleConnect(context, connection),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            _getProtocolIcon(connection.protocol),
            color: Colors.white,
          ),
        ),
        title: Text(
          connection.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${connection.protocol.displayName}://${connection.host}:${connection.port}',
            ),
            if (connection.lastUsed != null)
              Text(
                'Last used: ${_formatLastUsed(connection.lastUsed!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        isThreeLine: connection.lastUsed != null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Favorite toggle
            IconButton(
              icon: Icon(
                connection.isFavorite ? Icons.star : Icons.star_border,
                color: connection.isFavorite
                    ? Colors.amber
                    : Theme.of(context).iconTheme.color,
              ),
              onPressed: () {
                connectionProvider.toggleFavorite(connection);
              },
            ),
            // More options
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'connect',
                  child: Row(
                    children: [
                      Icon(Icons.link),
                      SizedBox(width: 8),
                      Text('Connect'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'connect':
                    _handleConnect(context, connection);
                    break;
                  case 'edit':
                    _handleEdit(context, connection);
                    break;
                  case 'delete':
                    _handleDelete(context, connection);
                    break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getProtocolIcon(ConnectionProtocol protocol) {
    switch (protocol) {
      case ConnectionProtocol.ftp:
        return Icons.folder_shared;
      case ConnectionProtocol.ftps:
        return Icons.folder_shared_outlined;
      case ConnectionProtocol.sftp:
        return Icons.vpn_key;
    }
  }

  String _formatLastUsed(DateTime lastUsed) {
    final now = DateTime.now();
    final difference = now.difference(lastUsed);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year${difference.inDays >= 730 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${difference.inDays >= 60 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  void _handleConnect(BuildContext context, ConnectionModel connection) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(connection: connection),
      ),
    );
  }

  void _handleEdit(BuildContext context, ConnectionModel connection) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddConnectionScreen(connection: connection),
      ),
    );
  }

  void _handleDelete(BuildContext context, ConnectionModel connection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete "${connection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<ConnectionProvider>(
                context,
                listen: false,
              ).deleteConnection(connection.id!);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
