# FTP Client

A modern, feature-rich FTP/SFTP/FTPS client for Android built with Flutter.

## Features

- **Multi-Protocol Support** — FTP, SFTP, and FTPS (SSL/TLS) connections
- **Remote File Browser** — Navigate, search, sort, and manage files on remote servers
- **Background Transfers** — Download/upload files with progress tracking and notifications
- **Transfer Manager** — View active transfers, history, cancel/retry operations
- **Built-in Text Editor** — View and edit text files with syntax highlighting and line numbers
- **Connection Management** — Save, organize and quick-connect to your servers
- **App Lock** — PIN, password, or biometric authentication
- **Theming** — Dark/Light modes with customizable accent colors
- **Animated UI** — Smooth page transitions, fade-in animations, and loading skeletons

## Screenshots

*Run the app to see the full UI experience with animated splash screen.*

## Getting Started

### Prerequisites

- Flutter SDK `^3.10.1`
- Android SDK (API 21+)
- A connected Android device or emulator

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd "FTP APP"

# Install dependencies
flutter pub get

# Run in debug mode
flutter run --debug

# Build release APK
flutter build apk --release
```

The release APK is generated at:
```
build/app/outputs/flutter-apk/app-release.apk
```

## Project Structure

```
lib/
├── main.dart                          # App entry point, splash, auth gate
├── core/
│   ├── constants/
│   │   └── app_constants.dart         # App-wide constants
│   ├── database/
│   │   └── database_helper.dart       # SQLite database operations
│   ├── theme/
│   │   └── app_theme.dart             # Theme configuration
│   └── utils/
│       ├── permission_helper.dart     # Storage & notification permissions
│       └── file_utils.dart            # File size formatting, extensions
├── models/
│   ├── connection_model.dart          # Server connection data model
│   ├── file_item_model.dart           # Remote file/folder model
│   └── transfer_model.dart            # Transfer record model
├── providers/
│   ├── connection_provider.dart       # Connection state management
│   └── theme_provider.dart            # Theme state management
├── services/
│   ├── connection_manager.dart        # Unified FTP/SFTP interface
│   ├── ftp_service.dart               # FTP/FTPS protocol implementation
│   ├── sftp_service.dart              # SFTP protocol implementation
│   └── transfer_service.dart          # Background transfer manager
└── ui/
    ├── screens/
    │   ├── splash_screen.dart          # Animated splash screen
    │   ├── dashboard_screen.dart       # Home screen with connections
    │   ├── add_connection_screen.dart  # Add/edit server connection
    │   ├── file_browser_screen.dart    # Remote file browser
    │   ├── text_editor_screen.dart     # Built-in text editor
    │   ├── transfer_manager_screen.dart # Transfer history & progress
    │   └── settings_screen.dart        # App settings & about
    └── widgets/
        └── shimmer_loading.dart        # Loading skeleton animations
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `sqflite` | Local SQLite database for connections & transfers |
| `ftpconnect` | FTP/FTPS protocol support |
| `dartssh2` | SSH/SFTP protocol support |
| `flutter_local_notifications` | Transfer progress & completion notifications |
| `shared_preferences` | App settings persistence |
| `path_provider` | Platform-specific file paths |
| `flutter_secure_storage` | Encrypted credential storage |
| `provider` | State management |
| `file_picker` | File selection for uploads |
| `permission_handler` | Runtime permission management |
| `open_filex` | Open files with system apps |
| `local_auth` | Biometric/PIN authentication |
| `intl` | Date & number formatting |

## Key Technical Details

### Transfer Speed Optimization
- **SFTP Download**: Uses dartssh2's pipelined `read()` stream (64 concurrent 16KB reads = 1MB in-flight)
- **SFTP Upload**: Sequential `writeBytes()` with 256KB chunks (internally pipelined as 16 × 16KB writes)
- **Periodic disk flush**: Every 1MB during downloads to prevent end-of-transfer stalls

### Architecture
- **Service Layer**: `ConnectionManager` provides a unified interface over `FTPService` and `SFTPService`
- **State Management**: Provider pattern for connections, theme, and transfers
- **Database**: SQLite via `sqflite` for connection credentials, transfer history, and settings
- **Background Transfers**: `TransferService` manages concurrent downloads/uploads with notifications

## Permissions

| Permission | Purpose |
|------------|---------|
| `INTERNET` | Server connections |
| `MANAGE_EXTERNAL_STORAGE` | File downloads/uploads |
| `POST_NOTIFICATIONS` | Transfer progress notifications (Android 13+) |
| `FOREGROUND_SERVICE` | Background transfers |
| `USE_BIOMETRIC` | App lock authentication |

## Developer

- **Name**: Ashish
- **Email**: DeveloperAshish2310@gmail.com

## Version

**1.0.0** — Initial release

## License

All rights reserved © 2026 Ashish.
