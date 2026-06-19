// lib/service/firestore_service.dart
// UPDATED:
//   [FIX 1] isAmbulanceConflict → cek KEDUA status "Disetujui" & "Menunggu Konfirmasi"
//   [FIX 2] recalculateAmbulanceAvailability → cek KEDUA status aktif
//   [FIX 3] updateBookingStatus → recalculate semua ambulans terdampak
//   [FIX 4] addBooking → pastikan field lengkap & konsisten
//   [FIX 5] getAmbulanceConflictDetail → return info event konflik (untuk UI warning)
//   [FIX 6] recalculatePetugasAvailability → tulis ke collection 'users' (bukan 'petugas')
//   [FIX 7] updateBookingStatus → recalculate petugas terdampak juga
//   [FIX 8] deleteBooking → recalculate petugas terdampak juga
//   [FIX 9] getAmbulanceConflictDetail & getPetugasConflictDetail → HANYA kunci yang
//           sudah "Disetujui". Booking "Menunggu Konfirmasi" TIDAK mengunci resource
//           supaya admin bisa assign petugas/armada yang sama ke booking lain di
//           tanggal yang sama selama belum ada yang disetujui.
// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Status yang dianggap "aktif" untuk recalculate availability ───────────────
// (dipakai di recalculate: KEDUA status ini membuat ambulans/petugas "sibuk")
const _activeStatuses = ['Disetujui', 'Menunggu Konfirmasi'];

// ── Status yang MENGUNCI sumber daya di UI assign (hanya yang sudah pasti) ────
// Booking "Menunggu Konfirmasi" TIDAK mengunci, agar admin bebas assign ke booking
// lain. Baru setelah disetujui, resource terkunci.
const _lockingStatuses = ['Disetujui'];

// ── Status yang dianggap "selesai" (ambulans/petugas bebas kembali) ────────────
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
        'available': true,
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

  Future<bool> isAmbulanceConflict({
    required String ambulanceId,
    required String date,
    String? excludeBookingId,
  }) async {
    try {
      // [FIX 9] Hanya cek _lockingStatuses (Disetujui)
      for (final status in _lockingStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;
          final data = doc.data();
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId == ambulanceId) return true;
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

  Future<Map<String, List<AmbulanceConflictInfo>>> getAmbulanceConflictDetail({
    required String date,
    String? excludeBookingId,
  }) async {
    final result = <String, List<AmbulanceConflictInfo>>{};
    try {
      // [FIX 9] Hanya status "Disetujui" yang mengunci armada.
      // Booking "Menunggu Konfirmasi" TIDAK mengunci, agar admin bisa
      // assign armada yang sama ke booking lain yang juga belum disetujui
      // pada tanggal yang sama.
      for (final status in _lockingStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;
          final data = doc.data();
          final evtName = data['eventName'] as String? ?? 'Event lain';
          final info = AmbulanceConflictInfo(
            bookingId: doc.id,
            eventName: evtName,
            status: status,
          );
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId.isNotEmpty) {
            result.putIfAbsent(oldId, () => []).add(info);
          }
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

  Future<Map<String, List<AmbulanceConflictInfo>>> getPetugasConflictDetail({
    required String date,
    String? excludeBookingId,
  }) async {
    final result = <String, List<AmbulanceConflictInfo>>{};
    try {
      // [FIX 9] Hanya status "Disetujui" yang mengunci petugas.
      // Booking "Menunggu Konfirmasi" TIDAK mengunci, agar admin bisa
      // assign petugas yang sama ke booking lain yang juga belum disetujui
      // pada tanggal yang sama.
      for (final status in _lockingStatuses) {
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .where('date', isEqualTo: date)
            .get();

        for (final doc in snap.docs) {
          if (excludeBookingId != null && doc.id == excludeBookingId) continue;
          final data = doc.data();
          final evtName = data['eventName'] as String? ?? 'Event lain';
          final info = AmbulanceConflictInfo(
            bookingId: doc.id,
            eventName: evtName,
            status: status,
          );
          final oldId = data['petugasId'] as String?;
          if (oldId != null && oldId.isNotEmpty) {
            result.putIfAbsent(oldId, () => []).add(info);
          }
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

  // ══════════════════════════════════════════════════════════════════
  // RECALCULATE AMBULANCE
  // ══════════════════════════════════════════════════════════════════

  Future<void> recalculateAmbulanceAvailability(String ambulanceId) async {
    if (ambulanceId.trim().isEmpty) return;
    try {
      bool isBusy = false;
      // [FIX 9] Hanya cek _lockingStatuses (Disetujui), bukan _activeStatuses
      // Booking "Menunggu Konfirmasi" tidak membuat ambulans tidak tersedia
      for (final status in _lockingStatuses) {
        if (isBusy) break;
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final oldId = data['ambulanceId'] as String?;
          if (oldId != null && oldId == ambulanceId) {
            isBusy = true;
            break;
          }
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

  Future<void> recalculateAllAffectedAmbulances({
    required List<String> prevAmbulanceIds,
    required List<String> newAmbulanceIds,
  }) async {
    final affected = <String>{
      ...prevAmbulanceIds.where((id) => id.isNotEmpty),
      ...newAmbulanceIds.where((id) => id.isNotEmpty),
    };
    print('[FS] Recalculate ${affected.length} ambulans terdampak: $affected');
    for (final id in affected) {
      await recalculateAmbulanceAvailability(id);
    }
  }

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
  // RECALCULATE PETUGAS — [FIX 6] tulis ke 'users', bukan 'petugas'
  // ══════════════════════════════════════════════════════════════════

  /// Recalculate field 'available' pada dokumen user petugas di collection 'users'.
  /// Petugas dianggap TIDAK TERSEDIA hanya jika ia ada dalam booking yang sudah
  /// DISETUJUI. Booking "Menunggu Konfirmasi" TIDAK membuat petugas tidak tersedia,
  /// agar admin masih bisa assign petugas yang sama ke booking lain yang belum
  /// disetujui pada tanggal yang sama.
  Future<void> recalculatePetugasAvailability(String petugasId) async {
    if (petugasId.trim().isEmpty) return;
    try {
      bool isBusy = false;
      // [FIX 9] Hanya cek _lockingStatuses (Disetujui), bukan _activeStatuses
      for (final status in _lockingStatuses) {
        if (isBusy) break;
        final snap = await _firestore
            .collection('bookings')
            .where('status', isEqualTo: status)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          // Format lama
          final oldId = data['petugasId'] as String?;
          if (oldId != null && oldId == petugasId) {
            isBusy = true;
            break;
          }
          // Format baru
          final list = data['petugasList'];
          if (list is List) {
            for (final item in list) {
              if (item is Map && item['id'] == petugasId) {
                isBusy = true;
                break;
              }
            }
          }
          if (isBusy) break;
        }
      }

      // [FIX 6] Tulis ke collection 'users', bukan 'petugas'
      await _firestore
          .collection('users')
          .doc(petugasId)
          .update({'available': !isBusy});

      print('[FS] Petugas $petugasId → available=${!isBusy}');
    } catch (e) {
      print('[FS] recalculatePetugasAvailability error ($petugasId): $e');
    }
  }

  Future<void> recalculateAllAffectedPetugas({
    required List<String> prevPetugasIds,
    required List<String> newPetugasIds,
  }) async {
    final affected = <String>{
      ...prevPetugasIds.where((id) => id.isNotEmpty),
      ...newPetugasIds.where((id) => id.isNotEmpty),
    };
    print('[FS] Recalculate ${affected.length} petugas terdampak: $affected');
    for (final id in affected) {
      await recalculatePetugasAvailability(id);
    }
  }

  Future<void> recalculateAllPetugas() async {
    try {
      final ptSnap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'petugas')
          .get();
      print('[FS] Recalculate semua: ${ptSnap.docs.length} petugas');
      for (final doc in ptSnap.docs) {
        await recalculatePetugasAvailability(doc.id);
      }
      print('[FS] Recalculate semua petugas selesai.');
    } catch (e) {
      print('[FS] recalculateAllPetugas error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // BOOKING CRUD
  // ══════════════════════════════════════════════════════════════════

  Future<String?> addBooking({
    required String userId,
    required String userName,
    required String eventName,
    required String date,
    required String location,
    required String type,
    List<String> documentNames = const [],
    List<Map<String, dynamic>> documentFiles = const [],
    double? latitude,
    double? longitude,
  }) async {
    try {
      final ref = await _firestore.collection('bookings').add({
        'userId': userId,
        'userName': userName,
        'eventName': eventName,
        'date': date,
        'location': location,
        'type': type,
        'status': 'Menunggu Konfirmasi',
        'documents': documentNames,
        'documentFiles': documentFiles,
        'eventLatitude': latitude,
        'eventLongitude': longitude,
        'petugasId': null,
        'petugasName': null,
        'petugasFaskes': null,
        'petugasList': [],
        'ambulanceId': null,
        'ambulancePlate': null,
        'ambulanceList': [],
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

  /// [FIX 3 + FIX 7] Update status booking dan recalculate ambulans + petugas terdampak.
  Future<bool> updateBookingStatus(String docId, String newStatus) async {
    try {
      // 1. Ambil data booking sebelum diupdate
      final docSnap =
          await _firestore.collection('bookings').doc(docId).get();

      final List<String> affectedAmbulanceIds = [];
      final List<String> affectedPetugasIds = [];

      if (docSnap.exists) {
        final data = docSnap.data()!;

        // Ambulans format lama
        final oldAmbId = data['ambulanceId'] as String?;
        if (oldAmbId != null && oldAmbId.isNotEmpty) {
          affectedAmbulanceIds.add(oldAmbId);
        }
        // Ambulans format baru
        final ambList = data['ambulanceList'];
        if (ambList is List) {
          for (final item in ambList) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedAmbulanceIds.add(id);
            }
          }
        }

        // Petugas format lama
        final oldPtId = data['petugasId'] as String?;
        if (oldPtId != null && oldPtId.isNotEmpty) {
          affectedPetugasIds.add(oldPtId);
        }
        // Petugas format baru
        final ptList = data['petugasList'];
        if (ptList is List) {
          for (final item in ptList) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedPetugasIds.add(id);
            }
          }
        }
      }

      // 2. Update status
      await _firestore
          .collection('bookings')
          .doc(docId)
          .update({'status': newStatus});
      print('[FS] Booking $docId → status: $newStatus');

      // 3. Recalculate ambulans terdampak
      for (final ambId in affectedAmbulanceIds) {
        await recalculateAmbulanceAvailability(ambId);
      }

      // 4. Recalculate petugas terdampak
      for (final ptId in affectedPetugasIds) {
        await recalculatePetugasAvailability(ptId);
      }

      return true;
    } catch (e) {
      print('[FS] updateBookingStatus error: $e');
      return false;
    }
  }

  /// [FIX 8] Hapus booking dan recalculate ambulans + petugas yang sebelumnya di-assign.
  Future<bool> deleteBooking(String docId) async {
    try {
      final docSnap =
          await _firestore.collection('bookings').doc(docId).get();

      final List<String> affectedAmbIds = [];
      final List<String> affectedPtIds = [];

      if (docSnap.exists) {
        final data = docSnap.data()!;

        final oldAmbId = data['ambulanceId'] as String?;
        if (oldAmbId != null && oldAmbId.isNotEmpty) affectedAmbIds.add(oldAmbId);
        final ambList = data['ambulanceList'];
        if (ambList is List) {
          for (final item in ambList) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedAmbIds.add(id);
            }
          }
        }

        final oldPtId = data['petugasId'] as String?;
        if (oldPtId != null && oldPtId.isNotEmpty) affectedPtIds.add(oldPtId);
        final ptList = data['petugasList'];
        if (ptList is List) {
          for (final item in ptList) {
            if (item is Map) {
              final id = item['id'] as String?;
              if (id != null && id.isNotEmpty) affectedPtIds.add(id);
            }
          }
        }
      }

      await _firestore.collection('bookings').doc(docId).delete();
      print('[FS] Booking $docId dihapus');

      for (final ambId in affectedAmbIds) {
        await recalculateAmbulanceAvailability(ambId);
      }
      for (final ptId in affectedPtIds) {
        await recalculatePetugasAvailability(ptId);
      }

      return true;
    } catch (e) {
      print('[FS] deleteBooking error: $e');
      return false;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// MODEL: Info konflik
// ══════════════════════════════════════════════════════════════════════

class AmbulanceConflictInfo {
  final String bookingId;
  final String eventName;
  final String status;

  const AmbulanceConflictInfo({
    required this.bookingId,
    required this.eventName,
    required this.status,
  });

  String get label {
    final badge = status == 'Disetujui' ? '✅' : '⏳';
    return '$badge $eventName';
  }
}