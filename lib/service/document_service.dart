// lib/service/document_service.dart
// Mendukung foto (JPG/PNG) dan dokumen (PDF) — disimpan Base64 ke Firestore
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

// ─────────────────────────── Konfigurasi ────────────────────────────────
class DocumentConfig {
  // Kualitas kompresi JPEG/PNG (0-100)
  static const int imageQuality = 70;
  // Dimensi maks gambar setelah kompresi
  static const int maxDimension = 1280;
  // Ukuran max file SEBELUM diproses (5 MB)
  static const int maxFileSizeBytes = 5 * 1024 * 1024;
  // Ukuran max PDF yang disimpan Base64 (10 MB)
  static const int maxPdfSizeBytes = 10 * 1024 * 1024;

  // Ekstensi foto yang diizinkan
  static const List<String> imageExtensions = ['jpg', 'jpeg', 'png'];
  // Ekstensi dokumen yang diizinkan
  static const List<String> documentExtensions = ['pdf'];
  // Semua yang diizinkan
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
}

// ─────────────────────────── Tipe File ────────────────────────────────────
enum DocumentType { image, pdf, unknown }

// ─────────────────────────── Model ────────────────────────────────────────
class DocumentFile {
  final String name;
  final String base64Data;
  final DocumentType type;
  final int originalSizeBytes;
  final int processedSizeBytes;

  const DocumentFile({
    required this.name,
    required this.base64Data,
    required this.type,
    required this.originalSizeBytes,
    required this.processedSizeBytes,
  });

  bool get isImage => type == DocumentType.image;
  bool get isPdf   => type == DocumentType.pdf;

  String get mimeType {
    final ext = _ext(name);
    switch (ext) {
      case 'png':  return 'image/png';
      case 'pdf':  return 'application/pdf';
      default:     return 'image/jpeg';
    }
  }

  String get dataUri => 'data:$mimeType;base64,$base64Data';

  Uint8List get bytes => base64Decode(base64Data);

  Map<String, dynamic> toMap() => {
    'name':                name,
    'base64Data':          base64Data,
    'fileType':            type == DocumentType.pdf ? 'pdf' : 'image',
    'mimeType':            mimeType,
    'originalSizeBytes':   originalSizeBytes,
    'processedSizeBytes':  processedSizeBytes,
  };

  factory DocumentFile.fromMap(Map<String, dynamic> m) {
    final raw = m['fileType'] as String? ?? 'image';
    final t   = raw == 'pdf' ? DocumentType.pdf : DocumentType.image;
    return DocumentFile(
      name:               m['name']               ?? '',
      base64Data:         m['base64Data']          ?? '',
      type:               t,
      originalSizeBytes:  m['originalSizeBytes']   ?? 0,
      processedSizeBytes: m['processedSizeBytes']  ?? 0,
    );
  }

  static String _ext(String fileName) {
    if (!fileName.contains('.')) return 'jpg';
    return fileName.split('.').last.toLowerCase();
  }
}

// ─────────────────────────── Service ──────────────────────────────────────
class DocumentService {
  static final DocumentService _instance = DocumentService._internal();
  factory DocumentService() => _instance;
  DocumentService._internal();

  // ── Tentukan tipe dari nama file ───────────────────────────────────────
  static DocumentType typeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (DocumentConfig.imageExtensions.contains(ext)) return DocumentType.image;
    if (DocumentConfig.documentExtensions.contains(ext)) return DocumentType.pdf;
    return DocumentType.unknown;
  }

  static bool isAllowed(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return DocumentConfig.allowedExtensions.contains(ext);
  }

  static bool isImageFile(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return DocumentConfig.imageExtensions.contains(ext);
  }

  static bool isPdfFile(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return DocumentConfig.documentExtensions.contains(ext);
  }

  // ── Kompresi gambar ────────────────────────────────────────────────────
  Future<Uint8List> _compressImage(Uint8List bytes, String fileName) async {
    const threshold = 300 * 1024; // 300 KB
    if (bytes.length <= threshold) return bytes;
    try {
      final ext    = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
      final format = ext == 'png' ? CompressFormat.png : CompressFormat.jpeg;
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality:   DocumentConfig.imageQuality,
        minWidth:  DocumentConfig.maxDimension,
        minHeight: DocumentConfig.maxDimension,
        format:    format,
      );
      print('[DOC] Kompresi: ${_fmt(bytes.length)} → ${_fmt(result.length)}');
      return result;
    } catch (e) {
      print('[DOC] Kompresi gagal ($e) — pakai asli');
      return bytes;
    }
  }

  // ── Proses satu file ───────────────────────────────────────────────────
  Future<DocumentFile?> processFile(
    PlatformFile file, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = file.bytes;
    if (bytes == null) {
      print('[DOC] ❌ bytes null: ${file.name}');
      return null;
    }

    final t = typeFromName(file.name);
    if (t == DocumentType.unknown) {
      print('[DOC] ❌ Tipe tidak didukung: ${file.name}');
      return null;
    }

    final maxSize = t == DocumentType.pdf
        ? DocumentConfig.maxPdfSizeBytes
        : DocumentConfig.maxFileSizeBytes;

    if (bytes.length > maxSize) {
      print('[DOC] ❌ File terlalu besar: ${_fmt(bytes.length)}');
      return null;
    }

    onProgress?.call(0.1);

    Uint8List processed;
    if (t == DocumentType.image) {
      processed = await _compressImage(bytes, file.name);
    } else {
      // PDF tidak dikompresi
      processed = bytes;
    }

    onProgress?.call(0.8);
    final b64 = base64Encode(processed);
    onProgress?.call(1.0);

    print('[DOC] ✅ "${file.name}" (${t.name}) → ${_fmt(b64.length)} chars Base64');

    return DocumentFile(
      name:               file.name,
      base64Data:         b64,
      type:               t,
      originalSizeBytes:  bytes.length,
      processedSizeBytes: processed.length,
    );
  }

  // ── Proses banyak file ─────────────────────────────────────────────────
  Future<List<DocumentFile>> processFiles({
    required List<PlatformFile> files,
    void Function(String name, int idx, int total, double progress)? onFileProgress,
  }) async {
    final results = <DocumentFile>[];
    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      final result = await processFile(
        f,
        onProgress: (p) => onFileProgress?.call(f.name, i, files.length, p),
      );
      if (result != null) results.add(result);
    }
    return results;
  }

  // ── Format ukuran ──────────────────────────────────────────────────────
  static String formatSize(int b) {
    if (b < 1024)           return '$b B';
    if (b < 1024 * 1024)   return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmt(int b) => DocumentService.formatSize(b);
}