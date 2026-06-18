// lib/service/firestore_service.dart
// UPDATED:
//   [FIX 1] isAmbulanceConflict → cek KEDUA status "Disetujui" & "Menunggu Konfirmasi"
//   [FIX 2] recalculateAmbulanceAvailability → cek KEDUA status aktif
//   [FIX 3] updateBookingStatus → recalculate semua ambulans terdampak
//   [FIX 4] addBooking → pastikan field lengkap & konsisten
//   [FIX 5] getAmbulanceConflictDetail → return info event konflik (untuk UI warning)
// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Status yang dianggap "aktif" (ambulans tidak boleh double-assign) ──
const _activeStatuses = ['Disetujui', 'Menunggu Konfirmasi'];

// ── Status yang dianggap "selesai" (ambulans bebas kembali) ────────────
const _doneStatuses = ['Selesai', 'Ditolak', 'Dibatalkan'];

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════
  // USER CRUD
  // ══════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getUsers() {
    return _firestore.collection('users').snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  Future<bool> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
      return true;
    } catch (e) {
      print('[FS] updateUser error: $e');
      return false;
    }
  }

  Future<bool> deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
      return true;
    } catch (e) {
      print('[FS] deleteUser error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // ARMADA CRUD
  // ══════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getAmbulances() {
    return _firestore.collection('ambulances').snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  Future<bool> addAmbulance(Map<String, dynamic> data) async {
    try {
      await _firestore.collection('ambulances').add({
        ...data,
        'available': true, // armada baru selalu tersedia
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('[FS] addAmbulance error: $e');
      return false;
    }
  }

  Future<bool> updateAmbulance(String id, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('ambulances').doc(id).update(data);
      return true;
    } catch (e) {
      print('[FS] updateAmbulance error: $e');
      return false;
    }
  }

  Future<bool> deleteAmbulance(String id) async {
    try {
      await _firestore.collection('ambulances').doc(id).delete();
      return true;
    } catch (e) {
      print('[FS] deleteAmbulance error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // AMBULANCE AVAILABILITY
  // ══════════════════════════════════════════════════════════════════

  /// [FIX 1] Cek apakah ambulans konflik pada tanggal tertentu.
  ///
  /// Sebelumnya hanya cek status "Disetujui".
  /// Sekarang cek KEDUA status aktif: "Disetujui" & "Menunggu Konfirmasi"
  /// agar admin tidak bisa assign ambulans yang sama ke 2 booking sekaligus
  /// meskipun keduanya masih menunggu konfirmasi.
  ///
  /// Returns true jika ada konflik.
  Future<bool> isAmbulanceConflict({
    required String ambulanceId,
    required String date,
    String? excludeBookingId,
  }) async {
    try {
      for (final status in _activeStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;

          final data = doc.data();

          // Cek format lama (single ambulanceId)
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId == ambulanceId) return true;

          // Cek format baru (ambulanceList multi-assign)
          final list = data['ambulanceList'];
          if (list is List) {
            for (final item in list) {
              if (item is Map && item['id'] == ambulanceId) return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      print('[FS] isAmbulanceConflict error: $e');
      return false;
    }
  }

  /// [FIX 5] Ambil detail semua konflik ambulans pada tanggal tertentu.
  ///
  /// Return: Map<ambulanceId, List<ConflictInfo>>
  /// Berguna untuk UI warning di EditBookingSheet agar admin tahu
  /// ambulans mana yang sudah dipakai booking mana.
  Future<Map<String, List<AmbulanceConflictInfo>>> getAmbulanceConflictDetail({
    required String date,
    String? excludeBookingId,
  }) async {
    final result = <String, List<AmbulanceConflictInfo>>{};

    try {
      for (final status in _activeStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;

          final data    = doc.data();
          final docId   = doc.id;
          final evtName = data['eventName'] as String? ?? 'Event lain';
          final info    = AmbulanceConflictInfo(
            bookingId:  docId,
            eventName:  evtName,
            status:     status,
          );

          // Cek format lama
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId.isNotEmpty) {
            result.putIfAbsent(oldId, () => []).add(info);
          }

          // Cek format baru
          final list = data['ambulanceList'];
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final id = item['id'] as String?;
                if (id != null && id.isNotEmpty) {
                  result.putIfAbsent(id, () => []).add(info);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[FS] getAmbulanceConflictDetail error: $e');
    }

    return result;
  }

  /// [NEW] Ambil detail semua konflik PETUGAS pada tanggal tertentu.
  ///
  /// Return: Map<petugasId, List<AmbulanceConflictInfo>>
  /// Sama seperti getAmbulanceConflictDetail tetapi untuk petugas:
  /// petugas dianggap konflik jika ia sudah di-assign ke booking lain
  /// (status Disetujui ATAU Menunggu Konfirmasi) pada tanggal yang sama.
  Future<Map<String, List<AmbulanceConflictInfo>>> getPetugasConflictDetail({
    required String date,
    String? excludeBookingId,
  }) async {
    final result = <String, List<AmbulanceConflictInfo>>{};

    try {
      for (final status in _activeStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;

          final data    = doc.data();
          final evtName = data['eventName'] as String? ?? 'Event lain';
          final info    = AmbulanceConflictInfo(
            bookingId: doc.id,
            eventName: evtName,
            status:    status,
          );

          // Format lama (single petugasId)
          final oldId = data['petugasId'] as String?;
          if (oldId != null && oldId.isNotEmpty) {
            result.putIfAbsent(oldId, () => []).add(info);
          }

          // Format baru (petugasList multi-assign)
          final list = data['petugasList'];
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final id = item['id'] as String?;
                if (id != null && id.isNotEmpty) {
                  result.putIfAbsent(id, () => []).add(info);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[FS] getPetugasConflictDetail error: $e');
    }

    return result;
  }

  /// [FIX 2] Recalculate ketersediaan ambulans berdasarkan SEMUA booking
  /// aktif yang ada (bukan hanya "Disetujui").
  ///
  /// Ambulans dianggap TIDAK TERSEDIA jika ia ada dalam setidaknya satu
  /// booking yang berstatus "Disetujui" ATAU "Menunggu Konfirmasi".
  /// Ambulans kembali TERSEDIA jika semua bookingnya sudah Selesai/Ditolak.
  Future<void> recalculateAmbulanceAvailability(String ambulanceId) async {
    if (ambulanceId.trim().isEmpty) return;

    try {
      bool isBusy = false;

      for (final status in _activeStatuses) {
        if (isBusy) break; // sudah ketemu, tidak perlu lanjut

        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();

          // Cek format lama (single)
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId == ambulanceId) {
            isBusy = true;
            break;
          }

          // Cek format baru (list)
          final list = data['ambulanceList'];
          if (list is List) {
            for (final item in list) {
              if (item is Map && item['id'] == ambulanceId) {
                isBusy = true;
                break;
              }
            }
          }
          if (isBusy) break;
        }
      }

      await _firestore
          .collection('ambulances')
          .doc(ambulanceId)
          .update({'available': !isBusy});

      print('[FS] Ambulans $ambulanceId → available=${!isBusy}');
    } catch (e) {
      print('[FS] recalculateAmbulanceAvailability error ($ambulanceId): $e');
    }
  }

  /// Recalculate ketersediaan untuk semua ambulans yang terdampak
  /// perubahan assignment pada sebuah booking.
  ///
  /// [prevAmbulanceIds] — ID sebelum perubahan
  /// [newAmbulanceIds]  — ID setelah perubahan
  Future<void> recalculateAllAffectedAmbulances({
    required List<String> prevAmbulanceIds,
    required List<String> newAmbulanceIds,
  }) async {
    // Gabung semua ID yang terdampak (lama maupun baru), deduplicate
    final affected = <String>{
      ...prevAmbulanceIds.where((id) => id.isNotEmpty),
      ...newAmbulanceIds.where((id) => id.isNotEmpty),
    };

    print('[FS] Recalculate ${affected.length} ambulans terdampak: $affected');

    for (final id in affected) {
      await recalculateAmbulanceAvailability(id);
    }
  }

  /// Recalculate SEMUA ambulans sekaligus.
  /// Dipanggil sekali untuk sinkronisasi penuh (misalnya saat app pertama buka).
  Future<void> recalculateAllAmbulances() async {
    try {
      final ambSnap = await _firestore.collection('ambulances').get();
      print('[FS] Recalculate semua: ${ambSnap.docs.length} ambulans');

      for (final doc in ambSnap.docs) {
        await recalculateAmbulanceAvailability(doc.id);
      }

      print('[FS] Recalculate semua selesai.');
    } catch (e) {
      print('[FS] recalculateAllAmbulances error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // BOOKING CRUD
  // ══════════════════════════════════════════════════════════════════

  /// [FIX 4] Tambah booking baru ke Firestore dengan field lengkap & konsisten.
  Future<String?> addBooking({
    required String userId,
    required String userName,
    required String eventName,
    required String date,
    required String location,
    required String type,
    List<String> documentNames            = const [],
    List<Map<String, dynamic>> documentFiles = const [],
    double? latitude,
    double? longitude,
  }) async {
    try {
      final ref = await _firestore.collection('bookings').add({
        // ── Data event ──────────────────────────────────────────────
        'userId':    userId,
        'userName':  userName,
        'eventName': eventName,
        'date':      date,
        'location':  location,
        'type':      type,

        // ── Status awal ─────────────────────────────────────────────
        'status': 'Menunggu Konfirmasi',

        // ── Dokumen pendukung ────────────────────────────────────────
        'documents':     documentNames,
        'documentFiles': documentFiles,

        // ── Koordinat lokasi event ───────────────────────────────────
        'eventLatitude':  latitude,
        'eventLongitude': longitude,

        // ── Petugas & armada (belum di-assign) ──────────────────────
        'petugasId':      null,
        'petugasName':    null,
        'petugasFaskes':  null,
        'petugasList':    [],
        'ambulanceId':    null,
        'ambulancePlate': null,
        'ambulanceList':  [],

        // ── Timestamp ───────────────────────────────────────────────
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('[FS] Booking baru: ${ref.id} | $eventName ($date)');
      return ref.id;
    } catch (e) {
      print('[FS] addBooking error: $e');
      return null;
    }
  }

  Stream<List<Map<String, dynamic>>> getBookings() {
    return _firestore
        .collection('bookings')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Stream<List<Map<String, dynamic>>> getBookingsByUser(String userId) {
    return _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Stream<List<Map<String, dynamic>>> getBookingsByPetugas(String petugasId) {
    return _firestore
        .collection('bookings')
        .where('petugasId', isEqualTo: petugasId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// [FIX 3] Update status booking dan recalculate ketersediaan ambulans
  /// yang terdampak — mencakup semua format (lama & baru).
  Future<bool> updateBookingStatus(String docId, String newStatus) async {
    try {
      // ── 1. Ambil data booking sebelum diupdate ────────────────────
      final docSnap =
          await _firestore.collection('bookings').doc(docId).get();

      final List<String> affectedAmbulanceIds = [];

      if (docSnap.exists) {
        final data = docSnap.data()!;

        // Format lama
        final oldId = data['ambulanceId'] as String?;
        if (oldId != null && oldId.isNotEmpty) {
          affectedAmbulanceIds.add(oldId);
        }

        // Format baru
        final list = data['ambulanceList'];
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedAmbulanceIds.add(id);
            }
          }
        }
      }

      // ── 2. Update status ──────────────────────────────────────────
      await _firestore
          .collection('bookings')
          .doc(docId)
          .update({'status': newStatus});

      print('[FS] Booking $docId → status: $newStatus');

      // ── 3. Recalculate availability setelah status tersimpan ──────
      for (final ambId in affectedAmbulanceIds) {
        await recalculateAmbulanceAvailability(ambId);
      }

      return true;
    } catch (e) {
      print('[FS] updateBookingStatus error: $e');
      return false;
    }
  }

  /// Hapus booking dan recalculate ambulans yang sebelumnya di-assign.
  Future<bool> deleteBooking(String docId) async {
    try {
      // Ambil data dulu untuk tahu ambulans mana yang terdampak
      final docSnap =
          await _firestore.collection('bookings').doc(docId).get();

      final List<String> affectedIds = [];
      if (docSnap.exists) {
        final data = docSnap.data()!;

        final oldId = data['ambulanceId'] as String?;
        if (oldId != null && oldId.isNotEmpty) affectedIds.add(oldId);

        final list = data['ambulanceList'];
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedIds.add(id);
            }
          }
        }
      }

      // Hapus booking
      await _firestore.collection('bookings').doc(docId).delete();
      print('[FS] Booking $docId dihapus');

      // Recalculate ambulans terdampak
      for (final ambId in affectedIds) {
        await recalculateAmbulanceAvailability(ambId);
      }

      return true;
    } catch (e) {
      print('[FS] deleteBooking error: $e');
      return false;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// MODEL: Info konflik ambulans (dipakai UI warning di EditBookingSheet)
// ══════════════════════════════════════════════════════════════════════

/// Informasi satu konflik ambulans:
/// ambulans X sudah dipakai di booking Y dengan status Z.
class AmbulanceConflictInfo {
  final String bookingId;
  final String eventName;
  final String status;

  const AmbulanceConflictInfo({
    required this.bookingId,
    required this.eventName,
    required this.status,
  });

  /// Teks ringkas untuk ditampilkan di UI.
  String get label {
    final badge = status == 'Disetujui' ? '✅' : '⏳';
    return '$badge $eventName';
  }
}