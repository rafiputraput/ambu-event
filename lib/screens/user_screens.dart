// lib/screens/user_screens.dart
// UPDATED:
//   1. Tampilkan semua petugas (petugasList) & armada (ambulanceList) di history
//   2. Indikator status real-time yang lebih informatif
//   3. Detail booking lebih lengkap
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'notification_screen.dart';
import '../service/notification_service.dart';

// ─────────────────────────── PALETTE ──────────────────────────────────
const _red    = Color(0xFFD94F4F);
const _green  = Color(0xFF3DBE7A);
const _blue   = Color(0xFF4A90D9);
const _orange = Color(0xFFE8943A);

// ══════════════════════════════════════════════════════════════════════
// HISTORY SCREEN
// ══════════════════════════════════════════════════════════════════════
class HistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const HistoryScreen({super.key, required this.history});

  Color _statusColor(String? s) {
    switch (s) {
      case 'Disetujui':  return _green;
      case 'Selesai':    return _blue;
      case 'Ditolak':
      case 'Dibatalkan': return _red;
      default:           return _orange;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'Disetujui':  return Icons.check_circle_rounded;
      case 'Selesai':    return Icons.verified_rounded;
      case 'Ditolak':
      case 'Dibatalkan': return Icons.cancel_rounded;
      default:           return Icons.hourglass_top_rounded;
    }
  }

  IconData _eventIcon(String? type) {
    switch (type) {
      case 'Konser':       return Icons.music_note;
      case 'Olahraga':     return Icons.emoji_events;
      case 'Pengajian':    return Icons.mosque;
      case 'Pencak Silat': return Icons.sports_martial_arts;
      default:             return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Booking'),
        centerTitle: true,
        backgroundColor: _red,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: uid == null
          ? _emptyState(Icons.lock_outline, 'Belum Login',
              'Silakan login untuk melihat riwayat booking.')
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _red));
                }
                if (snapshot.hasError) {
                  return _emptyState(Icons.error_outline,
                      'Gagal memuat riwayat',
                      'Coba lagi beberapa saat.\n${snapshot.error}');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyState(Icons.history,
                      'Belum ada riwayat booking',
                      'Booking yang kamu buat akan muncul di sini.');
                }

                final docs = List<QueryDocumentSnapshot>.from(
                    snapshot.data!.docs);
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['createdAt'];
                  final bTime = bData['createdAt'];
                  if (aTime == null) return -1;
                  if (bTime == null) return 1;
                  return (bTime as Timestamp).compareTo(aTime as Timestamp);
                });

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return _BookingCard(
                      data: data,
                      docId: docs[i].id,
                      statusColor: _statusColor(data['status']),
                      statusIcon: _statusIcon(data['status']),
                      eventIcon: _eventIcon(data['type']),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) =>
      Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                  color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center),
        ]),
      ));
}

// ══════════════════════════════════════════════════════════════════════
// BOOKING CARD — dengan multi-assign petugas & ambulance
// ══════════════════════════════════════════════════════════════════════
class _BookingCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final Color statusColor;
  final IconData statusIcon;
  final IconData eventIcon;

  const _BookingCard({
    required this.data,
    required this.docId,
    required this.statusColor,
    required this.statusIcon,
    required this.eventIcon,
  });

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _expanded = false;

  // ── Parse multi-assign petugas ──────────────────────────────────
  List<_PetugasInfo> _parsePetugas() {
    final raw = widget.data['petugasList'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return _PetugasInfo(
          name:   m['name']   as String? ?? '-',
          faskes: m['faskes'] as String? ?? '',
        );
      }).toList();
    }
    // Fallback format lama
    final name = widget.data['petugasName'] as String?;
    final fsk  = widget.data['petugasFaskes'] as String? ?? '';
    if (name != null && name.isNotEmpty) {
      return [_PetugasInfo(name: name, faskes: fsk)];
    }
    return [];
  }

  // ── Parse multi-assign ambulance ────────────────────────────────
  List<_AmbulanceInfo> _parseAmbulance() {
    final raw = widget.data['ambulanceList'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return _AmbulanceInfo(
          plate: m['plate'] as String? ?? '-',
          type:  m['type']  as String? ?? '',
        );
      }).toList();
    }
    // Fallback format lama
    final plate = widget.data['ambulancePlate'] as String?;
    if (plate != null && plate.isNotEmpty) {
      return [_AmbulanceInfo(plate: plate, type: '')];
    }
    return [];
  }

  // ── Parse foto (untuk count) ────────────────────────────────────
  int _photoCount() {
    final nf = widget.data['documentFiles'];
    if (nf is List) return nf.length;
    final of = widget.data['documents'];
    if (of is List) return of.length;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final status    = widget.data['status'] as String? ?? 'Menunggu Konfirmasi';
    final petugasList = _parsePetugas();
    final ambList     = _parseAmbulance();
    final photoCount  = _photoCount();
    final color       = widget.statusColor;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Status header ─────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(widget.statusIcon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(status, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            const Spacer(),
            Text(widget.data['date'] ?? '-',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Event name & type ───────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(widget.eventIcon, color: _red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.data['eventName'] ?? 'Event',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(widget.data['type'] ?? '-',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
            ]),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Lokasi ─────────────────────────────────────────
            _infoRow(Icons.location_on_rounded,
                widget.data['location'] ?? widget.data['eventLoc'] ?? '-'),
            const SizedBox(height: 6),

            // ── Petugas (multi) ─────────────────────────────────
            if (petugasList.isNotEmpty) ...[
              _multiAssignRow(
                icon:  Icons.medical_services_rounded,
                label: 'Petugas Medis',
                color: _green,
                items: petugasList.map((p) =>
                    p.faskes.isNotEmpty ? '${p.name} · ${p.faskes}' : p.name
                ).toList(),
              ),
              const SizedBox(height: 6),
            ],

            // ── Ambulance (multi) ───────────────────────────────
            if (ambList.isNotEmpty) ...[
              _multiAssignRow(
                icon:  Icons.local_hospital_rounded,
                label: 'Armada',
                color: _blue,
                items: ambList.map((a) =>
                    a.type.isNotEmpty ? '${a.plate} · ${a.type}' : a.plate
                ).toList(),
              ),
              const SizedBox(height: 6),
            ],

            // ── Belum ada petugas/armada (hanya saat disetujui) ─
            if (status == 'Disetujui' && petugasList.isEmpty && ambList.isEmpty)
              _infoChip(
                Icons.schedule_rounded,
                'Petugas & armada sedang disiapkan…',
                _orange,
              ),

            // ── Foto pendukung ──────────────────────────────────
            if (photoCount > 0) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.photo_library_outlined,
                  '$photoCount foto pendukung diunggah',
                  color: Colors.grey.shade500),
            ],

            const SizedBox(height: 10),
          ]),
        ),

        // ── Tombol batalkan (hanya saat menunggu) ───────────────
        if (status == 'Menunggu Konfirmasi') ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancel(context),
                icon: const Icon(Icons.cancel_outlined, size: 16, color: _red),
                label: const Text('Batalkan Booking',
                    style: TextStyle(color: _red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 4),
      ]),
    );
  }

  // ── Info row biasa ──────────────────────────────────────────────
  Widget _infoRow(IconData icon, String text, {Color? color}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: color ?? Colors.grey.shade400),
        const SizedBox(width: 6),
        Expanded(child: Text(text,
            style: TextStyle(
                fontSize: 12, color: color ?? Colors.grey.shade700))),
      ]);

  // ── Row multi-assign dengan chip ────────────────────────────────
  Widget _multiAssignRow({
    required IconData icon,
    required String label,
    required Color color,
    required List<String> items,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(spacing: 5, runSpacing: 4,
          children: items.map((item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(item, style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ]),
          )).toList(),
        ),
      ])),
    ]);
  }

  // ── Info chip (pesan pending) ───────────────────────────────────
  Widget _infoChip(IconData icon, String msg, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(msg, style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ]),
      );

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batalkan Booking',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
            'Yakin ingin membatalkan booking '
            '"${widget.data['eventName']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Tidak', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance
                  .collection('bookings').doc(widget.docId)
                  .update({'status': 'Dibatalkan'});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Booking berhasil dibatalkan.'),
                      backgroundColor: _orange));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
  }
}

// ── Model kecil internal ──────────────────────────────────────────────
class _PetugasInfo {
  final String name;
  final String faskes;
  const _PetugasInfo({required this.name, required this.faskes});
}

class _AmbulanceInfo {
  final String plate;
  final String type;
  const _AmbulanceInfo({required this.plate, required this.type});
}

// ══════════════════════════════════════════════════════════════════════
// MENU SCREEN
// ══════════════════════════════════════════════════════════════════════
class MenuScreen extends StatelessWidget {
  final VoidCallback onLogout;
  final String userName;
  final String userEmail;
  final String userPhoto;
  final String userId;
  final VoidCallback? onGoToNotifSettings;

  const MenuScreen({
    super.key,
    required this.onLogout,
    this.userName             = 'Pengguna',
    this.userEmail            = '',
    this.userPhoto            = '',
    this.userId               = '',
    this.onGoToNotifSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Halo',
                          style: TextStyle(fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      Text('Selamat',
                          style: TextStyle(fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      Text('Siang! 👋',
                          style: TextStyle(fontSize: 28,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(children: [
                    Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: userPhoto.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                userPhoto,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.person,
                                        size: 40, color: Colors.grey)))
                          : const Icon(Icons.person,
                                size: 40, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(userName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(userEmail,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ]),
                ],
              ),
            ),

            const Divider(),

            // ── LIST MENU ──────────────────────────────────────────
            Expanded(
              child: ListView(children: [

                // Notifikasi dengan badge
                _menuItem(
                  context,
                  Icons.notifications_outlined,
                  'Notifikasi',
                  iconColor: _orange,
                  badge: userId.isNotEmpty
                      ? _NotifBadge(userId: userId) : null,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationScreen())),
                ),

                const Divider(height: 1, indent: 20, endIndent: 20),

                _menuItem(
                  context,
                  Icons.info_outline,
                  'Tentang Aplikasi',
                  iconColor: Colors.purple,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                      builder: (_) => const AboutAppScreen())),
                ),

                const Divider(height: 1, indent: 20, endIndent: 20),

                _menuItem(
                  context,
                  Icons.help_outline,
                  'Bantuan & FAQ',
                  iconColor: Colors.teal,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                      builder: (_) => const HelpScreen())),
                ),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.grey, shape: BoxShape.circle),
                    child: const Icon(Icons.logout,
                        color: Colors.white, size: 16),
                  ),
                  title: const Text('Logout',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => _confirmLogout(context),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String title, {
    Widget? badge,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: (iconColor ?? Colors.grey).withValues(alpha: 0.15),
            shape: BoxShape.circle),
        child: Icon(icon, color: iconColor ?? Colors.black, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: badge,
      onTap: onTap,
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal',
                style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); onLogout(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

// Badge notif stream-based
class _NotifBadge extends StatelessWidget {
  final String userId;
  const _NotifBadge({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService().streamUnreadCount(userId),
      builder: (ctx, snap) {
        final count = snap.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
              color: _red, shape: BoxShape.circle),
          child: Text('$count',
              style: const TextStyle(
                  color: Colors.white, fontSize: 10,
                  fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ABOUT APP SCREEN
// ══════════════════════════════════════════════════════════════════════
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Tentang Aplikasi',
            style: TextStyle(fontWeight: FontWeight.w700,
                fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.10),
                    shape: BoxShape.circle),
                child: ClipOval(child: Image.asset(
                  'assets/images/logo_ambuevent.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.local_hospital_rounded,
                      color: _red, size: 40))),
              ),
              const SizedBox(height: 14),
              const Text('AMBUEVENT',
                  style: TextStyle(fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3, color: _red)),
              const SizedBox(height: 4),
              Text('Versi 1.0.0',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Dinas Kesehatan Kabupaten Madiun',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 16),
          _infoCard(Icons.info_outline_rounded, _blue,
              'Tentang Aplikasi',
              'AMBUEVENT adalah platform digital layanan medis standby '
              'untuk event. Memudahkan pemohon mengajukan permohonan tim '
              'medis kepada Dinas Kesehatan Kabupaten Madiun via PSC 119.'),
          const SizedBox(height: 12),
          _infoCard(Icons.star_outline_rounded, _orange,
              'Fitur Utama', null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _feat(Icons.event_note_rounded,
                    'Pengajuan booking event medis'),
                _feat(Icons.map_rounded, 'Peta lokasi event & faskes'),
                _feat(Icons.medical_services_rounded,
                    'Penugasan petugas & armada'),
                _feat(Icons.notifications_rounded,
                    'Notifikasi status booking'),
                _feat(Icons.bar_chart_rounded,
                    'Rekap laporan bulanan'),
              ])),
          const SizedBox(height: 12),
          _infoCard(Icons.contact_support_outlined, _green,
              'Kontak & Dukungan', null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _contact(Icons.business_rounded,
                    'Dinas Kesehatan Kab. Madiun'),
                _contact(Icons.location_on_rounded,
                    'Jl. Raya Solo No. 32, Jiwan, Madiun'),
                _contact(Icons.phone_rounded, '(0351) 123456'),
                _contact(Icons.email_rounded,
                    'psc119@dinkes.madiunkab.go.id'),
              ])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              Text('© 2024 Dinas Kesehatan Kabupaten Madiun',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Hak Cipta Dilindungi Undang-Undang',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400),
                  textAlign: TextAlign.center),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, Color color, String title,
      String? content, {Widget? child}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (content != null)
            Text(content, style: TextStyle(
                fontSize: 13, color: Colors.grey.shade600,
                height: 1.5)),
          if (child != null) child,
        ]),
      );

  Widget _feat(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 14, color: _orange),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(
          fontSize: 13, color: Colors.grey.shade700)),
    ]),
  );

  Widget _contact(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Icon(icon, size: 14, color: _green),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
          fontSize: 13, color: Colors.grey.shade700))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════
// HELP / FAQ SCREEN
// ══════════════════════════════════════════════════════════════════════
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    {
      'q': 'Bagaimana cara mengajukan booking event?',
      'a': 'Buka menu Home → tap "Buat Booking Baru" → isi form lengkap '
          '(nama event, tanggal, lokasi, tipe) → konfirmasi dan kirim. '
          'Admin akan memproses permohonan Anda.',
    },
    {
      'q': 'Berapa lama proses persetujuan booking?',
      'a': 'Biasanya 1–3 hari kerja. Anda mendapat notifikasi '
          'saat status booking berubah.',
    },
    {
      'q': 'Apakah bisa membatalkan booking yang sudah diajukan?',
      'a': 'Hanya bisa dibatalkan saat masih "Menunggu Konfirmasi". '
          'Buka History → tap booking → tap Batalkan.',
    },
    {
      'q': 'Bagaimana cara melihat petugas yang ditugaskan?',
      'a': 'Di History, pilih booking yang disetujui. '
          'Nama semua petugas dan armada yang ditugaskan tampil sebagai chip berwarna di kartu booking.',
    },
    {
      'q': 'Foto pendukung apa saja yang bisa diunggah?',
      'a': 'Format JPG, JPEG, PNG. Maks 5 MB per foto. '
          'Foto dikompresi otomatis sebelum dikirim.',
    },
    {
      'q': 'Kenapa notifikasi saya tidak muncul?',
      'a': 'Buka Menu → Notifikasi untuk melihat semua notifikasi. '
          'Pastikan ada koneksi internet.',
    },
    {
      'q': 'Apakah armada bisa dipakai untuk dua event sekaligus?',
      'a': 'Tidak. Armada yang sedang dipakai akan ditandai "Sedang dipakai" '
          'dan tidak bisa dipilih untuk booking lain hingga booking selesai atau ditolak.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Bantuan & FAQ',
            style: TextStyle(fontWeight: FontWeight.w700,
                fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _blue.withValues(alpha: 0.2))),
            child: Row(children: [
              const Icon(Icons.help_outline_rounded,
                  color: _blue, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Pusat Bantuan',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14, color: _blue)),
                Text(
                  'Temukan jawaban pertanyaan umum di bawah.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          ..._faqs.map((f) =>
              _FaqTile(question: f['q']!, answer: f['a']!)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Row(children: [
                Icon(Icons.support_agent_rounded,
                    color: _orange, size: 18),
                SizedBox(width: 8),
                Text('Masih butuh bantuan?',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ]),
              const SizedBox(height: 10),
              Text(
                'Hubungi PSC 119 Dinkes Kabupaten Madiun:\n'
                'Telp: (0351) 123456\n'
                'Email: psc119@dinkes.madiunkab.go.id',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.6)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question, answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _open
                ? _blue.withValues(alpha: 0.3)
                : Colors.grey.shade100),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: _open ? _blue : Colors.grey.shade100,
                    shape: BoxShape.circle),
                child: Icon(
                    _open ? Icons.remove : Icons.add,
                    size: 14,
                    color: _open
                        ? Colors.white
                        : Colors.grey.shade500)),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.question,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: _open
                          ? FontWeight.w700 : FontWeight.w500,
                      color: _open ? _blue : Colors.black87))),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(50, 0, 14, 14),
            child: Text(widget.answer,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.5)),
          ),
      ]),
    );
  }
}