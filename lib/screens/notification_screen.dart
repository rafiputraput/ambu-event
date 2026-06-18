// lib/screens/notification_screen.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/notification_service.dart';

const _red    = Color(0xFFD94F4F);
const _green  = Color(0xFF3DBE7A);
const _blue   = Color(0xFF4A90D9);
const _orange = Color(0xFFE8943A);
const _bg     = Color(0xFFF4F6FB);

Color _typeColor(String type) {
  switch (type) {
    case 'new_booking':    return _blue;
    case 'booking_status': return _orange;
    default:               return _green;
  }
}

IconData _typeIcon(String type, String title) {
  final t = title.toLowerCase();
  if (t.contains('disetujui'))  return Icons.check_circle_rounded;
  if (t.contains('ditolak'))    return Icons.cancel_rounded;
  if (t.contains('selesai'))    return Icons.verified_rounded;
  if (type == 'new_booking')    return Icons.assignment_rounded;
  return Icons.notifications_rounded;
}

String _timeAgo(dynamic createdAtMs, Timestamp? createdAt) {
  DateTime? dt;
  if (createdAtMs != null) {
    try {
      dt = DateTime.fromMillisecondsSinceEpoch((createdAtMs as num).toInt());
    } catch (_) {}
  }
  if (dt == null && createdAt != null) dt = createdAt.toDate();
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60)  return '${diff.inSeconds} detik lalu';
  if (diff.inMinutes < 60)  return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24)    return '${diff.inHours} jam lalu';
  if (diff.inDays < 7)      return '${diff.inDays} hari lalu';
  return '${dt.day}/${dt.month}/${dt.year}';
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _notifSvc = NotificationService();
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(
          child: Text('Silakan login terlebih dahulu',
              style: TextStyle(color: Colors.black87)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Notifikasi',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: _uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (ctx, snap) {
              final count = snap.data?.docs.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () => _notifSvc.markAllAsRead(_uid!),
                icon: const Icon(Icons.done_all_rounded,
                    size: 16, color: _blue),
                label: const Text('Baca Semua',
                    style: TextStyle(
                        color: _blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onSelected: (val) {
              if (val == 'clear') {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('Hapus Semua?',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    content: const Text(
                        'Semua notifikasi akan dihapus permanen.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Batal',
                              style: TextStyle(color: Colors.grey))),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _notifSvc.clearAll(_uid!);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_sweep_rounded, size: 18, color: _red),
                  SizedBox(width: 8),
                  Text('Hapus Semua', style: TextStyle(color: _red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: _uid)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: _red, strokeWidth: 2));
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Gagal memuat notifikasi',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('${snap.error}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                      textAlign: TextAlign.center),
                ]),
              ),
            );
          }

          final docs =
              List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);
          docs.sort((a, b) {
            final aMs =
                ((a.data() as Map)['createdAtMs'] as num?)?.toInt() ?? 0;
            final bMs =
                ((b.data() as Map)['createdAtMs'] as num?)?.toInt() ?? 0;
            return bMs.compareTo(aMs);
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16)
                    ],
                  ),
                  child: Icon(Icons.notifications_none_rounded,
                      size: 56, color: Colors.grey.shade300),
                ),
                const SizedBox(height: 16),
                Text('Belum ada notifikasi',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade400)),
                const SizedBox(height: 6),
                Text('Notifikasi booking akan muncul di sini.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade400)),
              ]),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc  = docs[i];
              final data = doc.data() as Map<String, dynamic>;

              final String     type       = (data['type']    as String?) ?? 'info';
              final String     title      = (data['title']   as String?) ?? '(tanpa judul)';
              final String     body       = (data['body']    as String?) ?? '';
              final bool       isRead     = (data['isRead']  as bool?)   ?? false;
              final dynamic    createdAtMs = data['createdAtMs'];
              final Timestamp? createdAt  = data['createdAt'] as Timestamp?;
              final Color      color      = _typeColor(type);
              final IconData   icon       = _typeIcon(type, title);

              return Dismissible(
                key: ValueKey('d_${doc.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_rounded,
                      color: _red, size: 22),
                ),
                onDismissed: (_) => _notifSvc.deleteNotification(doc.id),
                child: GestureDetector(
                  onTap: () {
                    if (!isRead) _notifSvc.markAsRead(doc.id);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      // ← selalu putih, tidak bergantung isRead
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      // ← border berwarna = belum dibaca, abu = sudah dibaca
                      border: isRead
                          ? Border.all(
                              color: const Color(0xFFEEEEEE),
                              width: 1,
                            )
                          : Border.all(
                              color: color,
                              width: 1.5,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Icon ──────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, size: 20, color: color),
                          ),
                          const SizedBox(width: 12),
                          // ── Teks ──────────────────────────────
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isRead
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                          // ← paksa hitam penuh
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    // titik unread
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin:
                                            const EdgeInsets.only(left: 6),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  body,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    // ← paksa abu gelap
                                    color: Colors.black54,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _timeAgo(createdAtMs, createdAt),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BELL ICON WIDGET
// ═══════════════════════════════════════════════════════════════════════
class NotificationBell extends StatelessWidget {
  final String userId;
  final VoidCallback? onTap;
  final Color iconColor;

  const NotificationBell({
    super.key,
    required this.userId,
    this.onTap,
    this.iconColor = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        return GestureDetector(
          onTap: onTap ??
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationScreen())),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                color: iconColor,
                size: 26,
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                        minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                        color: _red, shape: BoxShape.circle),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const NotificationScreen();
}