// lib/service/notification_service.dart
// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> initialize() async {
    print('[NOTIF] Service initialized');
  }

  Future<void> onUserLoggedIn(String uid) async {
    print('[NOTIF] User logged in: $uid');
  }

  // ── Kirim notifikasi ke satu user ─────────────────────────────────
  Future<void> _sendToUser({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? extra,
  }) async {
    if (userId.trim().isEmpty) {
      print('[NOTIF] userId kosong, skip');
      return;
    }
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final ref = await _db.collection('notifications').add({
        'userId':      userId.trim(),
        'title':       title,
        'body':        body,
        'type':        type,
        'isRead':      false,
        'extra':       extra ?? {},
        'createdAt':   FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,
      });
      print('[NOTIF] ✅ Terkirim ke userId=$userId docId=${ref.id} | $title');
    } catch (e) {
      print('[NOTIF] ❌ Error kirim ke $userId: $e');
    }
  }

  // ── Notify status booking → ke user pemilik booking ──────────────
  Future<void> notifyBookingStatus({
    required String userId,
    required String eventName,
    required String newStatus,
    String? petugasName,
    String? ambulancePlate,
  }) async {
    if (userId.trim().isEmpty) {
      print('[NOTIF] notifyBookingStatus: userId kosong, skip');
      return;
    }

    String title = '';
    String body  = '';

    switch (newStatus) {
      case 'Disetujui':
        title = 'Booking Disetujui';
        final parts = <String>[];
        if (petugasName != null && petugasName.isNotEmpty) parts.add('Petugas: $petugasName');
        if (ambulancePlate != null && ambulancePlate.isNotEmpty) parts.add('Armada: $ambulancePlate');
        body = 'Booking "$eventName" telah disetujui.'
            '${parts.isNotEmpty ? ' ${parts.join('. ')}.' : ''}';
        break;
      case 'Ditolak':
        title = 'Booking Ditolak';
        body  = 'Maaf, booking "$eventName" ditolak oleh admin.';
        break;
      case 'Selesai':
        title = 'Kegiatan Selesai';
        body  = 'Kegiatan "$eventName" telah selesai. Terima kasih!';
        break;
      default:
        print('[NOTIF] Status "$newStatus" tidak perlu notif');
        return;
    }

    await _sendToUser(
      userId: userId,
      title:  title,
      body:   body,
      type:   'booking_status',
      extra:  {'bookingStatus': newStatus, 'eventName': eventName},
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // NOTIF PETUGAS ASSIGNED / UNASSIGNED
  // ═══════════════════════════════════════════════════════════════════

  /// Dipanggil admin saat menyimpan assignment petugas di booking.
  ///
  /// [petugasIds]        — uid petugas yang BARU / masih di-assign
  /// [removedPetugasIds] — uid petugas yang SEBELUMNYA di-assign
  ///                       namun kini dihapus dari daftar
  Future<void> notifyPetugasAssigned({
    required List<String> petugasIds,
    required String eventName,
    required String eventDate,
    required String eventLocation,
    String? bookingId,
    List<String> removedPetugasIds = const [],
  }) async {
    // ── Petugas yang baru ditugaskan ──────────────────────────────
    for (final uid in petugasIds) {
      if (uid.trim().isEmpty) continue;
      await _sendToUser(
        userId: uid.trim(),
        title:  'Anda Ditugaskan ke Event',
        body:   'Anda ditugaskan sebagai petugas medis untuk "$eventName" '
                'pada $eventDate di $eventLocation.',
        type:   'petugas_assigned',
        extra:  {
          'eventName':     eventName,
          'eventDate':     eventDate,
          'eventLocation': eventLocation,
          if (bookingId != null) 'bookingId': bookingId,
        },
      );
    }

    // ── Petugas yang penugasannya dibatalkan ──────────────────────
    for (final uid in removedPetugasIds) {
      if (uid.trim().isEmpty) continue;
      await _sendToUser(
        userId: uid.trim(),
        title:  'Penugasan Dibatalkan',
        body:   'Penugasan Anda untuk event "$eventName" pada $eventDate '
                'telah dibatalkan oleh admin.',
        type:   'petugas_unassigned',
        extra:  {
          'eventName': eventName,
          'eventDate': eventDate,
          if (bookingId != null) 'bookingId': bookingId,
        },
      );
    }
  }

  // ── Notify admin → booking baru masuk ────────────────────────────
  Future<void> notifyAdminsNewBooking({
    required String eventName,
    required String userName,
    required String date,
  }) async {
    try {
      final snap = await _db
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      if (snap.docs.isEmpty) {
        print('[NOTIF] Tidak ada admin ditemukan di Firestore');
        return;
      }

      print('[NOTIF] Kirim notif booking baru ke ${snap.docs.length} admin');

      for (final doc in snap.docs) {
        final data     = doc.data();
        final adminUid = (data['uid'] as String?)?.trim() ?? doc.id;
        print('[NOTIF] → admin uid=$adminUid (doc.id=${doc.id})');
        await _sendToUser(
          userId: adminUid,
          title:  'Booking Baru Masuk',
          body:   '$userName mengajukan "$eventName" pada $date.',
          type:   'new_booking',
          extra:  {'eventName': eventName, 'userName': userName},
        );
      }
    } catch (e) {
      print('[NOTIF] notifyAdminsNewBooking error: $e');
    }
  }

  // ── Stream notifikasi ─────────────────────────────────────────────
  Stream<QuerySnapshot> streamNotifications(String userId) {
    print('[NOTIF] streamNotifications untuk userId=$userId');
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId.trim())
        .snapshots();
  }

  // ── Stream unread count ───────────────────────────────────────────
  Stream<int> streamUnreadCount(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId.trim())
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length)
        .handleError((e) {
          print('[NOTIF] streamUnreadCount error: $e');
          return 0;
        });
  }

  Future<void> markAsRead(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).update({'isRead': true});
    } catch (e) {
      print('[NOTIF] markAsRead error: $e');
    }
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId.trim())
          .where('isRead', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
      print('[NOTIF] ${snap.docs.length} notif ditandai dibaca');
    } catch (e) {
      print('[NOTIF] markAllAsRead error: $e');
    }
  }

  Future<void> deleteNotification(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).delete();
    } catch (e) {
      print('[NOTIF] deleteNotification error: $e');
    }
  }

  Future<void> clearAll(String userId) async {
    try {
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId.trim())
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) batch.delete(doc.reference);
      await batch.commit();
    } catch (e) {
      print('[NOTIF] clearAll error: $e');
    }
  }

  Future<void> toggleNotifications(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({'notificationsEnabled': enabled});
    } catch (e) {
      print('[NOTIF] toggleNotifications error: $e');
    }
  }
}