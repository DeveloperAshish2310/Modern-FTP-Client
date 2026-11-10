# Changelog

## [1.1.0] - 2026-11-10

### Server Management (SFTP/SSH servers)
- Server screen with live CPU, RAM and storage usage, uptime, load average and network speed
- System info: OS, kernel, CPU model
- Interactive SSH terminal with extra keys (Esc, Tab, Ctrl, Alt, arrows)
- Command triggers: save commands per server and run them with one tap, with live output and optional confirmation
- Docker: list containers with CPU/memory, start/stop/restart, live logs
- Processes: top processes by CPU or memory with search and kill
- Services: systemd services with start/stop/restart, status and logs
- Power: reboot and shut down with confirmation
- Automatic sudo using the saved password, with clear messages when Docker/systemd is missing or access is denied

### Transfers
- Fixed downloads getting stuck, failing randomly or running very slowly
- Native SFTP engine for downloads and uploads: faster and works with large files
- Interrupted downloads resume automatically after the app restarts
- Cancel works for downloads, uploads and copies
- SFTP copy runs on the server instead of through the phone
- FTP transfers use binary mode (no more corrupted files)
- Downloaded files appear in Gallery and the Files app
- Transfer screen no longer freezes at the end of a transfer

### File Browser
- Automatic reconnect when the connection drops
- Back button walks up from the default folder before disconnecting
- Show/hide hidden files
- Pick the SSH key file instead of typing its path

## [1.0.0] - 2026-03-03

### Initial Release

#### Connection Management
- Save and manage multiple server connections
- Support for FTP, SFTP, and FTPS (SSL/TLS) protocols
- Connection testing with real-time status indicators
- Quick connect via floating action button
- Swipe actions for edit and delete operations
- Staggered fade-in animations for connection cards

#### File Browser
- Full remote directory navigation with breadcrumb path
- File operations: create, rename, delete, move, copy
- Multi-file upload with file picker
- Download files to local storage
- File search and sorting (name, size, date, type)
- Long-press context menu with file actions
- File info dialog with detailed metadata

#### Transfer Manager
- Background downloads and uploads with progress tracking
- Real-time speed calculation (KB/s, MB/s)
- Transfer notifications with progress bars
- Cancel and retry functionality
- Transfer history with timestamps
- Optimized SFTP transfers with pipelined reads/writes

#### Built-in Text Editor
- Syntax highlighting for common file formats
- Line numbers and word wrap
- Search within file content
- Save changes back to server
- Configurable file extension whitelist

#### Settings & Personalization
- Dark and Light theme modes
- Customizable accent colors with palette picker
- App lock with PIN, password, or biometric authentication
- Default port and timeout configuration
- SSH key management
- Animation toggle controls

#### UI & Polish
- Animated splash screen with developer branding
- Custom page transitions (slide, fade-scale)
- Loading skeleton animations
- Smooth micro-interactions throughout
- Responsive layout for all screen sizes

#### Permissions & System
- Runtime storage permission with rationale dialog
- Notification permission for Android 13+ (API 33)
- Share files via system intent
- Foreground service for background transfers

### Developer
- **Name**: Ashish
- **Email**: DeveloperAshish2310@gmail.com
