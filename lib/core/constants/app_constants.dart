/// App-wide constants and configuration values
class AppConstants {
  // Database
  static const String dbName = 'ftp_client.db';
  static const int dbVersion = 1;
  
  // Default ports
  static const int ftpPort = 21;
  static const int ftpsPort = 990;
  static const int sftpPort = 22;
  
  // Timeout values (in seconds)
  static const int connectionTimeout = 30;
  static const int transferTimeout = 300;
  
  // Animation durations (in milliseconds)
  static const int shortAnimationDuration = 200;
  static const int mediumAnimationDuration = 300;
  static const int longAnimationDuration = 500;
  
  // Accent colors palette
  static const Map<String, int> accentColors = {
    'Blue': 0xFF007AFF,
    'Purple': 0xFF9C27B0,
    'Indigo': 0xFF3F51B5,
    'Green': 0xFF4CAF50,
    'Orange': 0xFFFF9800,
    'Red': 0xFFF44336,
  };
  
  // Theme
  static const int darkBackgroundColor = 0xFF121212;
  static const int darkSurfaceColor = 0xFF1E1E1E;
  static const int lightBackgroundColor = 0xFFFFFFFF;
  static const int lightSurfaceColor = 0xFFF5F5F5;
  
  // File extensions for text editor (default)
  static const List<String> defaultTextExtensions = [
    'txt', 'log', 'md', 'json', 'xml', 'html', 'css', 'js',
    'dart', 'java', 'py', 'cpp', 'c', 'h', 'php', 'sh'
  ];
  
  // Transfer settings
  static const int maxConcurrentTransfers = 3;
  static const int transferBufferSize = 8192; // 8KB
}
