import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows a permission explanation dialog and requests storage permission.
/// Returns true if permission is granted.
class PermissionHelper {
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Check if already granted
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    // Show explanation dialog FIRST
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.folder_open, size: 48, color: Colors.blue),
        title: const Text('Storage Access Required'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FTP Client needs storage access to:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.download, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Download files from servers')),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.upload, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Upload files to servers')),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.save, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Save files to your Downloads folder')),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Without this permission, file transfers will not work.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest != true) return false;

    // Now request the permission
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // If denied, try opening app settings
    if (status.isPermanentlyDenied) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Denied'),
          content: const Text(
            'Storage permission was denied. Please enable "All files access" in app settings.\n\n'
            'Settings → Apps → FTP Client → Permissions → Files and media → Allow management of all files',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await openAppSettings();
      }
    }

    // Re-check after settings
    status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }
}
