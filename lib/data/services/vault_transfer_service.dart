import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class VaultTransferUnsupportedException implements Exception {
  final String message;

  const VaultTransferUnsupportedException(this.message);

  @override
  String toString() => message;
}

abstract class VaultTransferService {
  Future<bool> shareTextAsFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String subject,
    Rect? sharePositionOrigin,
  });

  Future<String?> saveTextWithPicker({
    required String content,
    required String fileName,
    required String mimeType,
    required String dialogTitle,
  });

  Future<String?> pickBackupJsonContent();
}

class PlatformVaultTransferService implements VaultTransferService {
  final Future<ShareResult> Function(ShareParams params)? shareInvoker;
  final Future<Directory> Function()? tempDirectoryProvider;
  final bool? isLinuxOverride;

  const PlatformVaultTransferService({
    this.shareInvoker,
    this.tempDirectoryProvider,
    this.isLinuxOverride,
  });

  bool get _isLinuxPlatform =>
      isLinuxOverride ?? (!kIsWeb && Platform.isLinux);

  @override
  Future<bool> shareTextAsFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    if (_isLinuxPlatform) {
      throw const VaultTransferUnsupportedException(
        'System file sharing is not supported on Linux. Use Save or Copy instead.',
      );
    }

    final tempDir = await (tempDirectoryProvider ?? getTemporaryDirectory)();
    final tempFile = File(p.join(tempDir.path, fileName));
    await tempFile.writeAsString(content);

    try {
      final shareCall =
          shareInvoker ?? (params) => SharePlus.instance.share(params);
      final result = await shareCall(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: mimeType)],
          subject: subject,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    } on UnimplementedError {
      throw const VaultTransferUnsupportedException(
        'System file sharing is unavailable on this OS version. Use Save or Copy instead.',
      );
    }
  }

  @override
  Future<String?> saveTextWithPicker({
    required String content,
    required String fileName,
    required String mimeType,
    required String dialogTitle,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final savedUri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: dialogTitle,
    );
    if (savedUri == null) return null;
    if (savedUri.scheme == 'file') {
      final path = savedUri.toFilePath();
      // Ensure content exists on desktop platforms if saveFile only selects path
      final outFile = File(path);
      if (!await outFile.exists() || await outFile.length() == 0) {
        await outFile.writeAsBytes(bytes);
      }
      return path;
    }
    return savedUri.toString();
  }

  @override
  Future<String?> pickBackupJsonContent() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select HydroChime Vault Backup (.json)',
      type: FileType.any,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    if (bytes.isNotEmpty) {
      return utf8.decode(bytes);
    }
    final path = picked.path;
    if (path != null) {
      return await File(path).readAsString();
    }
    return null;
  }
}

