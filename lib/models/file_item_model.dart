import 'package:flutter/material.dart';

/// Model for remote file or folder
class FileItemModel {
  final String name;
  final String path;
  final int size;
  final bool isDirectory;
  final DateTime? modifiedDate;
  final String? permissions;

  FileItemModel({
    required this.name,
    required this.path,
    required this.size,
    required this.isDirectory,
    this.modifiedDate,
    this.permissions,
  });

  // Get icon based on file type
  IconData get icon {
    if (isDirectory) {
      return Icons.folder;
    }

    final extension = name.split('.').last.toLowerCase();

    switch (extension) {
      case 'txt':
      case 'log':
      case 'md':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'apk':
        return Icons.android;
      case 'exe':
        return Icons.apps;
      case 'html':
      case 'htm':
      case 'xml':
      case 'json':
      case 'css':
      case 'js':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  // Format file size
  String get formattedSize {
    if (isDirectory) return '';

    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024)
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() =>
      'FileItem: $name (${isDirectory ? "DIR" : formattedSize})';
}
