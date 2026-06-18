// lib/service/image_service.dart
// Menggunakan Base64 untuk menyimpan foto langsung ke Firestore
// Tidak membutuhkan Cloudinary atau Firebase Storage
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

// ── Konfigurasi kompresi ──────────────────────────────────────────────
class ImageConfig {
  // Kualitas kompresi JPEG (0–100)
  static const int quality = 70;

  // Batas ukuran sebelum dikompresi (300 KB)
  static const int thresholdBytes = 300 * 1024;

  // Dimensi maksimum (lebar/tinggi) setelah kompresi
  static const int maxDimension = 1280;

  // Ukuran maksimum Base64 yang boleh disimpan per foto (1 MB byte asli)
  // Setelah kompresi dan Base64, ukuran di Firestore ≈ 1.33× ukuran asli
  static const int maxFileSizeBytes = 1 * 1024 * 1024;

  // Ekstensi yang diizinkan (HANYA FOTO)
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png'];
}

// ── Model foto yang sudah diproses ────────────────────────────────────
class ImageFile {
  final String name;
  final String base64Data; // Base64 dari bytes yang sudah dikompres
  final int originalSizeBytes;
  final int compressedSizeBytes;

  const ImageFile({
    required this.name,
    required this.base64Data,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
  });

  /// Untuk disimpan ke Firestore
  Map<String, dynamic> toMap() => {
        'name': name,
        'base64Data': base64Data,
        'originalSizeBytes': originalSizeBytes,
        'compressedSizeBytes': compressedSizeBytes,
        'mimeType': _mimeType(name),
      };

  /// Untuk membuat data URI yang bisa ditampilkan sebagai Image.memory
  String get dataUri => 'data:${_mimeType(name)};base64,$base64Data';

  /// Decode Base64 ke bytes (untuk ditampilkan atau diunduh)
  Uint8List get bytes => base64Decode(base64Data);

  static String _mimeType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpeg';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  factory ImageFile.fromMap(Map<String, dynamic> m) => ImageFile(
        name: m['name'] ?? '',
        base64Data: m['base64Data'] ?? '',
        originalSizeBytes: m['originalSizeBytes'] ?? 0,
        compressedSizeBytes: m['compressedSizeBytes'] ?? 0,
      );
}

// ── Service utama ─────────────────────────────────────────────────────
class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  // ── Kompresi gambar ───────────────────────────────────────────────
  Future<Uint8List> _compress(Uint8List bytes, String fileName) async {
    if (bytes.length <= ImageConfig.thresholdBytes) {
      print('[IMAGE] Tidak perlu kompresi: ${_fmt(bytes.length)}');
      return bytes;
    }
    try {
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : 'jpg';
      final format =
          ext == 'png' ? CompressFormat.png : CompressFormat.jpeg;

      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: ImageConfig.quality,
        minWidth: ImageConfig.maxDimension,
        minHeight: ImageConfig.maxDimension,
        format: format,
      );
      print(
          '[IMAGE] Kompresi: ${_fmt(bytes.length)} → ${_fmt(compressed.length)}');
      return compressed;
    } catch (e) {
      print('[IMAGE] Kompresi gagal ($e) — pakai bytes asli');
      return bytes;
    }
  }

  // ── Proses satu file ──────────────────────────────────────────────
  /// Mengambil bytes dari PlatformFile, mengkompresi, lalu encode ke Base64.
  /// Return null jika file tidak valid atau terlalu besar.
  Future<ImageFile?> processFile(
    PlatformFile file, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = file.bytes;
    if (bytes == null) {
      print('[IMAGE] ❌ bytes null: ${file.name}');
      return null;
    }

    // Cek ukuran awal
    if (bytes.length > ImageConfig.maxFileSizeBytes) {
      print(
          '[IMAGE] ❌ File terlalu besar: ${_fmt(bytes.length)} (maks ${_fmt(ImageConfig.maxFileSizeBytes)})');
      return null;
    }

    onProgress?.call(0.1);
    final compressed = await _compress(bytes, file.name);
    onProgress?.call(0.7);

    final b64 = base64Encode(compressed);
    onProgress?.call(1.0);

    print(
        '[IMAGE] ✅ "${file.name}" → Base64 ${_fmt(b64.length)} chars');

    return ImageFile(
      name: file.name,
      base64Data: b64,
      originalSizeBytes: bytes.length,
      compressedSizeBytes: compressed.length,
    );
  }

  // ── Proses banyak file ────────────────────────────────────────────
  Future<List<ImageFile>> processFiles({
    required List<PlatformFile> files,
    void Function(String fileName, int index, int total, double progress)?
        onFileProgress,
  }) async {
    final results = <ImageFile>[];
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

  // ── Helper: validasi ekstensi ────────────────────────────────────
  static bool isAllowed(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return ImageConfig.allowedExtensions.contains(ext);
  }

  // ── Helper format ukuran ─────────────────────────────────────────
  static String formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmt(int b) => ImageService.formatSize(b);
}