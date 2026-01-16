# Google Gemini
# Revised Project Brief: Modern FTP Client (v0.0.1)

## Project Overview

Develop a high-performance, modern Android FTP/SFTP client using **Flutter**. The application must be a fully functional client capable of managing remote files with a focus on clean code (SOLID principles) and a "user-first" interface based on the provided design system.

**Design Reference:** [Stitch Design Link]

---

## Technical Specifications

* **Framework:** Flutter (Android Platform)
* **Database:** SQLite (via `sqflite`) for secure credential storage.
* **Networking:** Integration of `ftpconnect` and `ssh2` (or equivalent) for SFTP/FTPS support.
* **Version Control:** Full Git implementation with logical commit history.
* **Permissions:** Proper handling of scoped storage and notification permissions.

---

## Core Feature Set

### 1. Connection & File Management

* **Multi-Protocol:** Support for **FTP, SFTP, and FTPS**.
* **File Operations:** Create, Rename, Delete, Move, Copy, and Search files/folders.
* **Transfer Engine:** Robust background Upload/Download tasks with system notifications for progress and errors.
* **Integrated Editor:** View/Edit `.txt` files. Users can whitelist additional extensions for editing via the Settings menu.

### 2. UI/UX & Motion Design

* **Contextual Actions:** "File Actions Context Menu" triggered by a **Long Press**, as specified in the "File Actions" frame of the design.
* **Smooth Animations:** Implement high-quality, fluid transitions (Hero animations, micro-interactions, and smooth list loading).
* **Dynamic Theming:** Native Light/Dark mode support with an optional **Accent Color Picker** for user personalization.

### 3. Application Settings

The **Settings Page** must act as the control hub for:

* **Animation Control:** Toggle or adjust the speed/intensity of UI transitions.
* **Editor Config:** Manage which file extensions are opened in the internal text editor.
* **Connection Defaults:** Default port settings and timeout configurations.

---

## Delivery Standards

* **Clean Code:** Modular, easy-to-read, and well-documented Dart code.
* **Modern UI:** Adherence to the provided design while ensuring the app feels "snappy" and professional.
* **Reliability:** Error handling for network interruptions and file permission issues.

---

### Project Structure Suggestion

To help the developers get started, here is a suggested project architecture:

| Directory | Purpose |
| --- | --- |
| `lib/core` | Utilities, Constants, and Database Helpers |
| `lib/models` | Data models for FTP Credentials and File metadata |
| `lib/services` | Logic for FTP/SFTP connections and File transfers |
| `lib/ui/screens` | Main Dashboard, File Explorer, and Settings Page |
| `lib/ui/widgets` | Custom Context Menus, Notification Tiles, and Theme Pickers |




# CHAT GPT

Certainly. Here is the updated and polished specification with your additional requirement included appropriately:

---

Develop a fully functional and modern Android application using Flutter in accordance with the following specification.

UI Reference:
[https://stitch.withgoogle.com/projects/10241627306277513088](https://stitch.withgoogle.com/projects/10241627306277513088)

Functional Overview:
• Application must operate as a complete FTP client.
• Must support FTP, FTPS, and SFTP protocols.
• Must allow saving of credentials and direct-connect functionality.
• Must support standard file operations:
– Create folder
– Create file
– List files and directories
– Search files
– Download files
– Upload files
– Delete files
– Rename files
– Move files
– Copy files
• Must incorporate a long-press contextual action menu for file operations (“File Actions Context Menu” as shown in the UI reference).
• Must support viewing and editing of text files. Allow users to configure supported extensions for viewing/editing in both the settings section and the contextual menu.
• Must support dual themes (Light and Dark).
• Optional enhancement: theme accent color customization.
• Must provide system notifications for all major actions (e.g., download completion, upload completion, errors).
• Must include smooth animations throughout the application. Configuration for animation behavior must be exposed in the Settings page as indicated in the UI design.
• UI must be modern, intuitive, and user-friendly, and code must be clean, organized, and maintainable.

Technical Requirements:
• Use SQLite for data persistence (e.g., saved credentials, preferences).
• Use `ftpconnect` library for handling FTP-related functionality.
• Handle all required runtime permissions appropriately.
• Employ Git for version control throughout development.

Metadata:
• Application Name: FTP Client
• Version: 0.0.1
• Platform: Android
• Language: Flutter

Deliverable:
• Create a new Flutter project that satisfies all above requirements and functions as a fully working FTP client.

---

If you need a more formal contract-style version, a requirements matrix, or a task breakdown, just let me know.
