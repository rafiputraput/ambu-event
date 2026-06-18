// lib/screens/petugas_screen.dart
// UPDATED: TugasCard — tampilkan nama mobil (fetch dari Firestore jika format lama)
// UPDATED: Rekap Per Petugas — tampilkan nama mobil + plat armada yang digunakan
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_models.dart';
import '../service/map_service.dart';
import '../service/routing_service.dart';
import '../service/notification_service.dart';

// ─────────────────────────── PALETTE ──────────────────────────────────
const _red    = Color(0xFFD94F4F);
const _green  = Color(0xFF3DBE7A);
const _blue   = Color(0xFF4A90D9);
const _orange = Color(0xFFE8943A);
const _bg     = Color(0xFFF4F6FB);

// ═══════════════════════════════════════════════════════════════════════
// WRAPPER
// ═══════════════════════════════════════════════════════════════════════
class PetugasHomeWrapper extends StatefulWidget {
  final UserModel petugasUser;
  final VoidCallback onLogout;

  const PetugasHomeWrapper({
    super.key,
    required this.petugasUser,
    required this.onLogout,
  });

  @override
  State<PetugasHomeWrapper> createState() => _PetugasHomeWrapperState();
}

class _PetugasHomeWrapperState extends State<PetugasHomeWrapper> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      PetugasTugasScreen(petugasUser: widget.petugasUser),
      PetugasPetaScreen(petugasUser: widget.petugasUser),
      PetugasProfilScreen(
          petugasUser: widget.petugasUser, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: tabs[_tabIndex],
      bottomNavigationBar: _PetugasBottomNav(
        currentIndex: _tabIndex,
        userId: widget.petugasUser.uid,
        onTap: (i) => setState(() => _tabIndex = i),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BOTTOM NAV
// ═══════════════════════════════════════════════════════════════════════
class _PetugasBottomNav extends StatelessWidget {
  final int currentIndex;
  final String userId;
  final void Function(int) onTap;

  const _PetugasBottomNav({
    required this.currentIndex,
    required this.userId,
    required this.onTap,
  });

  static const _activeColor   = _red;
  static const _inactiveColor = Color(0xFFAAAAAA);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(0, Icons.assignment_outlined, Icons.assignment, 'Tugas'),
              _item(1, Icons.map_outlined, Icons.map, 'Peta'),
              _profileItem(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int idx, IconData icon, IconData iconSel, String label) {
    final sel = currentIndex == idx;
    return GestureDetector(
      onTap: () => onTap(idx),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _activeColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(sel ? iconSel : icon, size: 22,
              color: sel ? _activeColor : _inactiveColor),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? _activeColor : _inactiveColor)),
        ]),
      ),
    );
  }

  Widget _profileItem() {
    final sel = currentIndex == 2;
    return GestureDetector(
      onTap: () => onTap(2),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _activeColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(sel ? Icons.person : Icons.person_outline, size: 22,
                color: sel ? _activeColor : _inactiveColor),
            Positioned(
              top: -4, right: -6,
              child: StreamBuilder<int>(
                stream: NotificationService().streamUnreadCount(userId),
                builder: (ctx, snap) {
                  final count = snap.data ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center),
                  );
                },
              ),
            ),
          ]),
          const SizedBox(height: 3),
          Text('Profil', style: TextStyle(
              fontSize: 11,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? _activeColor : _inactiveColor)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 1 — TUGAS
// ═══════════════════════════════════════════════════════════════════════
class PetugasTugasScreen extends StatelessWidget {
  final UserModel petugasUser;
  const PetugasTugasScreen({super.key, required this.petugasUser});

  Color _statusColor(String? s) {
    switch (s) {
      case 'Disetujui': return _green;
      case 'Selesai':   return _blue;
      case 'Ditolak':   return _red;
      default:          return _orange;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'Disetujui': return Icons.check_circle_rounded;
      case 'Selesai':   return Icons.verified_rounded;
      case 'Ditolak':   return Icons.cancel_rounded;
      default:          return Icons.hourglass_top_rounded;
    }
  }

  /// Cek apakah booking ini milik petugas yang sedang login.
  /// Support format lama (petugasId) dan format baru (petugasList).
  bool _isMyBooking(Map<String, dynamic> data, String myUid) {
    final oldId = data['petugasId'] as String?;
    if (oldId != null && oldId == myUid) return true;
    final list = data['petugasList'];
    if (list is List) {
      for (final item in list) {
        if (item is Map && item['id'] == myUid) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('bookings')
        .snapshots();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Tugas Saya',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (ctx, snap) {
              final aktif = (snap.data?.docs ?? [])
                  .where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return data['status'] == 'Disetujui' &&
                        _isMyBooking(data, petugasUser.uid);
                  })
                  .length;
              if (aktif == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.assignment_late_rounded, size: 14, color: _red),
                  const SizedBox(width: 4),
                  Text('$aktif aktif',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _red)),
                ]),
              );
            },
          ),
        ],
      ),
      body: Column(children: [
        _NewAssignmentBanner(petugasUser: petugasUser),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
              }
              if (snapshot.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center),
                ));
              }
              // Filter client-side: ambil hanya booking milik petugas ini
              final allDocs = snapshot.data?.docs ?? [];
              final myDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _isMyBooking(data, petugasUser.uid);
              }).toList();

              if (myDocs.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16)]),
                      child: Icon(Icons.assignment_outlined, size: 56, color: Colors.grey.shade300)),
                    const SizedBox(height: 16),
                    Text('Belum ada tugas',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                            color: Colors.grey.shade400)),
                    const SizedBox(height: 6),
                    Text('Tugas yang ditugaskan admin\nakan muncul di sini.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        textAlign: TextAlign.center),
                  ],
                ));
              }

              final docs = List<QueryDocumentSnapshot>.from(myDocs);
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aPri = aData['status'] == 'Disetujui' ? 0
                    : aData['status'] == 'Menunggu Konfirmasi' ? 1 : 2;
                final bPri = bData['status'] == 'Disetujui' ? 0
                    : bData['status'] == 'Menunggu Konfirmasi' ? 1 : 2;
                if (aPri != bPri) return aPri.compareTo(bPri);
                final aTs = aData['createdAt'];
                final bTs = bData['createdAt'];
                if (aTs == null) return 1;
                if (bTs == null) return -1;
                return (bTs as Timestamp).compareTo(aTs as Timestamp);
              });

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: docs.length,
                itemBuilder: (ctx, i) => _TugasCard(
                  key: ValueKey(docs[i].id),
                  doc: docs[i],
                  petugasUser: petugasUser,
                  statusColor: _statusColor((docs[i].data() as Map<String, dynamic>)['status']),
                  statusIcon: _statusIcon((docs[i].data() as Map<String, dynamic>)['status']),
                  onLihatPeta: (lat, lng, nama) {
                    Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => _PetaDetailScreen(
                        petugasUser: petugasUser,
                        eventLat: lat, eventLng: lng, eventName: nama,
                      ),
                    ));
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────── BANNER NOTIF TUGAS BARU ──────────────────────────────
class _NewAssignmentBanner extends StatelessWidget {
  final UserModel petugasUser;
  const _NewAssignmentBanner({required this.petugasUser});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: petugasUser.uid)
          .where('type', isEqualTo: 'petugas_assigned')
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            for (final doc in snap.data!.docs) {
              NotificationService().markAsRead(doc.id);
            }
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PetugasNotificationScreen(userId: petugasUser.uid)));
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orange.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active_rounded, color: _orange, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(count == 1 ? 'Ada 1 penugasan baru!' : 'Ada $count penugasan baru!',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _orange)),
                const Text('Tap untuk lihat detail notifikasi.',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: _orange, size: 20),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── TUGAS CARD ───────────────────────────────
class _TugasCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final UserModel petugasUser;
  final Color statusColor;
  final IconData statusIcon;
  final void Function(double lat, double lng, String nama) onLihatPeta;

  const _TugasCard({
    required super.key,
    required this.doc,
    required this.petugasUser,
    required this.statusColor,
    required this.statusIcon,
    required this.onLihatPeta,
  });

  @override
  State<_TugasCard> createState() => _TugasCardState();
}

class _TugasCardState extends State<_TugasCard> {
  bool _loading = false;

  // ── Cache nama kendaraan (plate → vehicleName) ───────────────────
  Map<String, String> _vehicleNameCache = {};
  bool _vehicleLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetchVehicleNames();
  }

  // ── Fetch nama kendaraan dari Firestore berdasarkan plate ────────
  Future<void> _fetchVehicleNames() async {
    final data = widget.doc.data() as Map<String, dynamic>;
    final armadaRaw = _parseArmadaListRaw(data);

    if (armadaRaw.isEmpty) {
      if (mounted) setState(() => _vehicleLoaded = true);
      return;
    }

    final Map<String, String> cache = {};

    for (final a in armadaRaw) {
      // Jika vehicleName sudah ada dari ambulanceList, pakai langsung
      if (a.vehicleName.isNotEmpty) {
        cache[a.plate] = a.vehicleName;
        continue;
      }

      // Fetch dari Firestore berdasarkan plate number
      if (a.plate.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('ambulances')
              .where('plate', isEqualTo: a.plate)
              .limit(1)
              .get();

          if (snap.docs.isNotEmpty) {
            final d = snap.docs.first.data();
            String vName = (d['vehicleName'] as String? ?? '').trim();
            final type   = (d['type']        as String? ?? '').trim();
            // Bersihkan format "Nama · info"
            if (vName.contains('·')) vName = vName.split('·').first.trim();
            // Fallback ke type jika vehicleName kosong atau sama dengan plate
            if (vName.isEmpty || vName == a.plate) vName = type;
            if (vName.isNotEmpty) cache[a.plate] = vName;
          }
        } catch (e) {
          print('[TugasCard] fetch vehicle name error: $e');
        }
      }
    }

    if (mounted) {
      setState(() {
        _vehicleNameCache = cache;
        _vehicleLoaded = true;
      });
    }
  }

  Future<void> _tandaiSelesai() async {
    setState(() => _loading = true);
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.doc.id)
        .update({'status': 'Selesai'});
    if (mounted) setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tugas ditandai selesai! 🎉'),
        backgroundColor: _green,
      ));
    }
  }

  // ── Parse TANPA cache (data mentah dari Firestore) ───────────────
  List<_ArmadaInfo> _parseArmadaListRaw(Map<String, dynamic> data) {
    final rawList = data['ambulanceList'];
    if (rawList is List && rawList.isNotEmpty) {
      return rawList.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        String vName = (m['vehicleName'] as String? ?? '').trim();
        final type   = (m['type']        as String? ?? '').trim();
        final plate  = (m['plate']       as String? ?? '').trim();
        if (vName.contains('·')) vName = vName.split('·').first.trim();
        if (vName.isEmpty || vName == plate) vName = type;
        return _ArmadaInfo(
          vehicleName: vName,
          plate:       plate,
          driverName:  (m['petugasName'] as String? ?? '').trim(),
        );
      }).toList();
    }

    // Format lama — single field
    final plate      = (data['ambulancePlate'] as String? ?? '').trim();
    final vName      = (data['vehicleName']    as String? ?? '').trim();
    final type       = (data['type']           as String? ?? '').trim();
    final driverName = (data['petugasName']    as String? ?? '').trim();
    if (plate.isEmpty) return [];

    String displayName = '';
    if (vName.isNotEmpty && vName != plate) displayName = vName;
    // vehicleName kosong → akan diisi oleh _fetchVehicleNames via cache
    return [_ArmadaInfo(vehicleName: displayName, plate: plate, driverName: driverName)];
  }

  // ── Parse DENGAN cache (dipakai di build) ────────────────────────
  List<_ArmadaInfo> _parseArmadaList(Map<String, dynamic> data) {
    final raw = _parseArmadaListRaw(data);
    return raw.map((a) {
      final cached = _vehicleNameCache[a.plate] ?? '';
      return _ArmadaInfo(
        vehicleName: cached.isNotEmpty ? cached : a.vehicleName,
        plate:       a.plate,
        driverName:  a.driverName,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final data   = widget.doc.data() as Map<String, dynamic>;
    final status = data['status'] as String? ?? '-';
    final color  = widget.statusColor;

    final double? lat = (data['eventLatitude']  as num?)?.toDouble();
    final double? lng = (data['eventLongitude'] as num?)?.toDouble();
    final hasCoord = lat != null && lng != null;

    final armadaList = _parseArmadaList(data);

    // Cek apakah ada data armada dari format lama (ambulancePlate)
    final hasLegacyPlate = armadaList.isEmpty &&
        (data['ambulancePlate'] ?? '').toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header status ──────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(widget.statusIcon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(status, style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(data['date'] ?? '-',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          ]),
        ),

        // ── Nama event ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event_note_rounded, color: _red, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['eventName'] ?? 'Event',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(data['userName'] ?? '-',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ])),
          ]),
        ),

        // ── Info detail ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _iRow(Icons.location_on_rounded, data['location'] ?? data['eventLoc'] ?? '-'),
            const SizedBox(height: 5),
            _iRow(Icons.category_rounded, data['type'] ?? '-'),

            // ── Armada dari ambulanceList (format baru) ────────────
            if (armadaList.isNotEmpty) ...[
              const SizedBox(height: 8),
              _armadaSection(armadaList),

            // ── Armada dari format lama (ambulancePlate) ───────────
            ] else if (hasLegacyPlate) ...[
              const SizedBox(height: 8),
              _armadaSection([
                _ArmadaInfo(
                  vehicleName: _vehicleNameCache[data['ambulancePlate'].toString()] ?? '',
                  plate:       data['ambulancePlate'].toString(),
                  driverName:  '',
                ),
              ]),
            ],
          ]),
        ),

        const SizedBox(height: 12),
        const Divider(height: 1, indent: 16, endIndent: 16),

        // ── Tombol aksi ────────────────────────────────────────────────
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: _red))))
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(children: [
              if (hasCoord) ...[
                Expanded(child: OutlinedButton.icon(
                  onPressed: () =>
                      widget.onLihatPeta(lat, lng, data['eventName'] ?? 'Event'),
                  icon: const Icon(Icons.map_rounded, size: 15),
                  label: const Text('Lihat Rute'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: const BorderSide(color: _blue),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                )),
                const SizedBox(width: 10),
              ],
              if (status == 'Disetujui')
                Expanded(child: ElevatedButton.icon(
                  onPressed: _tandaiSelesai,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                  label: const Text('Selesai'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                )),
              if (!hasCoord && status != 'Disetujui')
                const SizedBox(height: 0),
            ]),
          ),
      ]),
    );
  }

  // ── Widget blok armada ────────────────────────────────────────────────
  Widget _armadaSection(List<_ArmadaInfo> list) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label header
          Row(children: [
            const Icon(Icons.local_hospital_rounded, size: 12, color: _blue),
            const SizedBox(width: 5),
            Text(
              list.length > 1 ? 'Armada (${list.length})' : 'Armada',
              style: const TextStyle(
                  fontSize: 10, color: _blue, fontWeight: FontWeight.w700),
            ),
          ]),
          const SizedBox(height: 7),

          // Tiap armada
          ...list.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0) const Divider(height: 10, color: Color(0x224A90D9)),

                // ── Nama mobil ──────────────────────────────────────
                if (a.vehicleName.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.directions_car_rounded, size: 12, color: _blue),
                    const SizedBox(width: 5),
                    Expanded(child: Text(
                      a.vehicleName,
                      style: const TextStyle(
                          fontSize: 12, color: _blue, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ])
                else if (!_vehicleLoaded)
                  // Masih loading nama kendaraan
                  Row(children: [
                    const SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: _blue),
                    ),
                    const SizedBox(width: 6),
                    Text('Memuat nama kendaraan...',
                        style: TextStyle(
                            fontSize: 11,
                            color: _blue.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic)),
                  ]),

                // ── Plat nomor ──────────────────────────────────────
                if (a.plate.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.credit_card_rounded, size: 12, color: _blue),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _blue.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        a.plate,
                        style: const TextStyle(
                            fontSize: 11,
                            color: _blue,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ]),
                ],

                // ── Nama driver ─────────────────────────────────────
                if (a.driverName.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.person_rounded,
                        size: 12, color: _blue.withValues(alpha: 0.7)),
                    const SizedBox(width: 5),
                    Expanded(child: Text(
                      'Driver: ${a.driverName}',
                      style: TextStyle(
                          fontSize: 11,
                          color: _blue.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _iRow(IconData icon, String val, {Color? color}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: color ?? Colors.grey.shade400),
        const SizedBox(width: 6),
        Expanded(child: Text(val,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: color ?? Colors.grey.shade700),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);
}

// ── Model kecil info armada ───────────────────────────────────────────
class _ArmadaInfo {
  final String vehicleName;
  final String plate;
  final String driverName;
  const _ArmadaInfo({
    required this.vehicleName,
    required this.plate,
    required this.driverName,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// HALAMAN NOTIFIKASI PETUGAS
// ═══════════════════════════════════════════════════════════════════════
class PetugasNotificationScreen extends StatelessWidget {
  final String userId;
  const PetugasNotificationScreen({super.key, required this.userId});

  Color _typeColor(String type) {
    switch (type) {
      case 'petugas_assigned':   return _green;
      case 'petugas_unassigned': return _red;
      case 'booking_status':     return _orange;
      case 'new_booking':        return _blue;
      default:                   return _blue;
    }
  }

  IconData _typeIcon(String type, String title) {
    if (type == 'petugas_assigned')   return Icons.assignment_turned_in_rounded;
    if (type == 'petugas_unassigned') return Icons.assignment_late_rounded;
    final t = title.toLowerCase();
    if (t.contains('disetujui')) return Icons.check_circle_rounded;
    if (t.contains('ditolak'))   return Icons.cancel_rounded;
    if (t.contains('selesai'))   return Icons.verified_rounded;
    return Icons.notifications_rounded;
  }

  String _timeAgo(dynamic createdAtMs, Timestamp? createdAt) {
    DateTime? dt;
    if (createdAtMs != null) {
      try { dt = DateTime.fromMillisecondsSinceEpoch((createdAtMs as num).toInt()); } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final notifSvc = NotificationService();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Notifikasi',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: userId)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (ctx, snap) {
              final count = snap.data?.docs.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () => notifSvc.markAllAsRead(userId),
                icon: const Icon(Icons.done_all_rounded, size: 16, color: _blue),
                label: const Text('Baca Semua',
                    style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onSelected: (val) {
              if (val == 'clear') {
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Hapus Semua?', style: TextStyle(fontWeight: FontWeight.w700)),
                  content: const Text('Semua notifikasi akan dihapus permanen.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx),
                        child: const Text('Batal', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                      onPressed: () { Navigator.pop(ctx); notifSvc.clearAll(userId); },
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                      child: const Text('Hapus'),
                    ),
                  ],
                ));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_sweep_rounded, size: 18, color: _red),
                  SizedBox(width: 8),
                  Text('Hapus Semua', style: TextStyle(color: _red)),
                ])),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
          }
          final docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);
          docs.sort((a, b) {
            final aMs = ((a.data() as Map)['createdAtMs'] as num?)?.toInt() ?? 0;
            final bMs = ((b.data() as Map)['createdAtMs'] as num?)?.toInt() ?? 0;
            return bMs.compareTo(aMs);
          });

          if (docs.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16)]),
                child: Icon(Icons.notifications_none_rounded, size: 56, color: Colors.grey.shade300)),
              const SizedBox(height: 16),
              Text('Belum ada notifikasi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
            ]));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc    = docs[i];
              final data   = doc.data() as Map<String, dynamic>;
              final String type        = (data['type']       as String?) ?? 'info';
              final String title       = (data['title']      as String?) ?? '(tanpa judul)';
              final String body        = (data['body']       as String?) ?? '';
              final bool   isRead      = (data['isRead']     as bool?)   ?? false;
              final dynamic createdAtMs = data['createdAtMs'];
              final Timestamp? createdAt = data['createdAt'] as Timestamp?;
              final Color  color       = _typeColor(type);
              final IconData icon      = _typeIcon(type, title);

              return Dismissible(
                key: ValueKey('d_${doc.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_rounded, color: _red, size: 22),
                ),
                onDismissed: (_) => notifSvc.deleteNotification(doc.id),
                child: GestureDetector(
                  onTap: () { if (!isRead) notifSvc.markAsRead(doc.id); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isRead
                          ? Border.all(color: const Color(0xFFEEEEEE), width: 1)
                          : Border.all(color: color, width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(icon, size: 20, color: color)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(title,
                                style: TextStyle(fontSize: 13,
                                    fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                    color: Colors.black))),
                            if (!isRead)
                              Container(width: 8, height: 8,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          ]),
                          const SizedBox(height: 4),
                          Text(body, style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Text(_timeAgo(createdAtMs, createdAt),
                              style: const TextStyle(fontSize: 10, color: Colors.black38)),
                        ])),
                      ]),
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
// PETA DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════
class _PetaDetailScreen extends StatefulWidget {
  final UserModel petugasUser;
  final double eventLat;
  final double eventLng;
  final String eventName;

  const _PetaDetailScreen({
    required this.petugasUser,
    required this.eventLat,
    required this.eventLng,
    required this.eventName,
  });

  @override
  State<_PetaDetailScreen> createState() => _PetaDetailScreenState();
}

class _PetaDetailScreenState extends State<_PetaDetailScreen> {
  final MapController    _mapCtrl    = MapController();
  final MapService       _mapSvc     = MapService();
  final RoutingService   _routingSvc = RoutingService();

  LatLng? _myLocation;
  List<LatLng> _routePoints = [];
  RouteResult? _routeResult;
  bool _loadingLoc   = true;
  bool _loadingRoute = false;
  String _statusMsg  = 'Mendapatkan lokasi Anda...';

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    setState(() { _loadingLoc = true; _statusMsg = 'Mendapatkan lokasi Anda...'; });
    final loc = await _mapSvc.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() { _loadingLoc = false; _statusMsg = 'Tidak bisa mendapatkan lokasi. Pastikan GPS aktif.'; });
      return;
    }
    setState(() { _myLocation = loc; _loadingLoc = false; _loadingRoute = true; _statusMsg = 'Menghitung rute...'; });
    final eventLatLng = LatLng(widget.eventLat, widget.eventLng);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fitBounds(loc, eventLatLng);
    });
    final result = await _routingSvc.getRoute(loc, eventLatLng);
    if (!mounted) return;
    setState(() {
      _loadingRoute = false; _statusMsg = '';
      if (result != null) { _routePoints = result.points; _routeResult = result; }
      else { _statusMsg = 'Rute tidak tersedia. Gunakan navigasi eksternal.'; }
    });
  }

  void _fitBounds(LatLng a, LatLng b) {
    final minLat = a.latitude  < b.latitude  ? a.latitude  : b.latitude;
    final maxLat = a.latitude  > b.latitude  ? a.latitude  : b.latitude;
    final minLng = a.longitude < b.longitude ? a.longitude : b.longitude;
    final maxLng = a.longitude > b.longitude ? a.longitude : b.longitude;
    _mapCtrl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLat - 0.008, minLng - 0.008),
        LatLng(maxLat + 0.008, maxLng + 0.008),
      ),
      padding: const EdgeInsets.all(60),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final eventLatLng = LatLng(widget.eventLat, widget.eventLng);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Positioned.fill(child: FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(initialCenter: eventLatLng, initialZoom: 13, maxZoom: 18, minZoom: 5),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ambuevent', maxZoom: 18),
            if (_routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(points: _routePoints, color: _blue, strokeWidth: 5,
                    borderColor: Colors.white, borderStrokeWidth: 1.5),
              ]),
            MarkerLayer(markers: [
              if (_myLocation != null)
                Marker(point: _myLocation!, width: 52, height: 52,
                    alignment: Alignment.center, child: _myMarker()),
              Marker(point: eventLatLng, width: 52, height: 62,
                  alignment: Alignment.bottomCenter, child: _eventMarker()),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
          ],
        )),
        if (_loadingLoc || _loadingRoute)
          Positioned.fill(child: Container(
            color: Colors.black.withValues(alpha: 0.18),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _red)),
                const SizedBox(width: 12),
                Text(_statusMsg, style: const TextStyle(fontSize: 13)),
              ]),
            )),
          )),
        Positioned(top: 0, left: 0, right: 0,
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
                child: InkWell(customBorder: const CircleBorder(), onTap: () => Navigator.pop(context),
                  child: const Padding(padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, size: 22, color: Colors.black87)))),
              const SizedBox(width: 10),
              Expanded(child: Material(color: Colors.white, borderRadius: BorderRadius.circular(12), elevation: 4,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.event_rounded, color: _red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(widget.eventName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis)),
                  ])))),
            ]),
          ))),
        Positioned(right: 12, bottom: 220,
          child: Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
            child: InkWell(customBorder: const CircleBorder(),
              onTap: () { if (_myLocation != null) _fitBounds(_myLocation!, eventLatLng); },
              child: const Padding(padding: EdgeInsets.all(12),
                  child: Icon(Icons.fit_screen_rounded, color: _blue, size: 24))))),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomCard()),
      ]),
    );
  }

  Widget _buildBottomCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16, offset: const Offset(0, -4))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 14),
        if (_routeResult != null) ...[
          Row(children: [
            _infoChip(Icons.route_rounded, _routingSvc.formatDistance(_routeResult!.distanceMeters), _blue),
            const SizedBox(width: 10),
            _infoChip(Icons.access_time_rounded, _routingSvc.formatDuration(_routeResult!.durationSeconds), _orange),
          ]),
          const SizedBox(height: 12),
        ] else if (_statusMsg.isNotEmpty && !_loadingLoc && !_loadingRoute) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: _orange, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_statusMsg, style: const TextStyle(fontSize: 12, color: _orange))),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _red.withValues(alpha: 0.15))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_rounded, color: _red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lokasi Event', style: TextStyle(fontSize: 10, color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(widget.eventName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text('${widget.eventLat.toStringAsFixed(5)}, ${widget.eventLng.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_loadingLoc || _loadingRoute) ? null : _init,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Update Lokasi', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color), const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    ),
  );

  Widget _myMarker() => Stack(alignment: Alignment.center, children: [
    Container(width: 40, height: 40,
        decoration: BoxDecoration(color: _blue.withValues(alpha: 0.2), shape: BoxShape.circle,
            border: Border.all(color: _blue.withValues(alpha: 0.5), width: 2))),
    Container(width: 18, height: 18,
        decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
        child: const Icon(Icons.person, color: Colors.white, size: 12)),
  ]);

  Widget _eventMarker() => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: _red, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6, spreadRadius: 1)]),
        child: const Icon(Icons.location_on, color: Colors.white, size: 22)),
    CustomPaint(painter: _PinTailPainter(), size: const Size(12, 10)),
  ]);
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      ui.Path()..moveTo(0, 0)..lineTo(size.width / 2, size.height)..lineTo(size.width, 0)..close(),
      Paint()..color = _red..style = PaintingStyle.fill,
    );
  }
  @override bool shouldRepaint(_) => false;
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 2 — PETA
// ═══════════════════════════════════════════════════════════════════════
class PetugasPetaScreen extends StatefulWidget {
  final UserModel petugasUser;
  const PetugasPetaScreen({super.key, required this.petugasUser});

  @override
  State<PetugasPetaScreen> createState() => _PetugasPetaScreenState();
}

class _PetugasPetaScreenState extends State<PetugasPetaScreen> {
  final MapService _mapSvc = MapService();
  LatLng? _myLocation;
  bool _loadingLoc = true;
  bool _sharing    = false;
  Timer? _locationTimer;
  StreamSubscription<LatLng>? _locationSub;

  static const LatLng _dinkesLocation = LatLng(-7.624662988533274, 111.4947916090254);

  @override
  void initState() { super.initState(); _loadLocation(); }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _locationSub?.cancel();
    if (_sharing) _mapSvc.removePetugasLocation(widget.petugasUser.uid);
    super.dispose();
  }

  Future<void> _loadLocation() async {
    final loc = await _mapSvc.getCurrentLocation();
    if (mounted) setState(() { _myLocation = loc; _loadingLoc = false; });
  }

  Future<void> _startSharing() async {
    final loc = await _mapSvc.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak bisa mendapatkan lokasi. Pastikan GPS aktif.'),
        backgroundColor: _orange));
      return;
    }
    setState(() { _sharing = true; _myLocation = loc; });
    await _mapSvc.updatePetugasLocation(uid: widget.petugasUser.uid,
        name: widget.petugasUser.name, location: loc);
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final current = await _mapSvc.getCurrentLocation();
      if (current != null && mounted) {
        setState(() => _myLocation = current);
        await _mapSvc.updatePetugasLocation(uid: widget.petugasUser.uid,
            name: widget.petugasUser.name, location: current);
      }
    });
    _locationSub = _mapSvc.getLocationStream().listen((pos) {
      if (mounted) setState(() => _myLocation = pos);
    });
  }

  Future<void> _stopSharing() async {
    _locationTimer?.cancel(); _locationTimer = null;
    _locationSub?.cancel();   _locationSub   = null;
    await _mapSvc.removePetugasLocation(widget.petugasUser.uid);
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _toggleSharing() async {
    if (_sharing) await _stopSharing(); else await _startSharing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Peta Tugas',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: (_sharing ? _green : Colors.grey).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_sharing ? Icons.location_on_rounded : Icons.location_off_rounded,
                  size: 14, color: _sharing ? _green : Colors.grey),
              const SizedBox(width: 4),
              Text(_sharing ? 'Live' : 'Off',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _sharing ? _green : Colors.grey)),
            ]),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .snapshots(),
        builder: (ctx, snap) {
          final docs = (snap.data?.docs ?? []).where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            if (d['status'] != 'Disetujui') return false;
            final oldId = d['petugasId'] as String?;
            if (oldId == widget.petugasUser.uid) return true;
            final list = d['petugasList'];
            if (list is List) {
              for (final item in list) {
                if (item is Map && item['id'] == widget.petugasUser.uid) return true;
              }
            }
            return false;
          }).toList();
          final eventMarkers = <Marker>[];
          for (final doc in docs) {
            final d   = doc.data() as Map<String, dynamic>;
            final lat = (d['eventLatitude']  as num?)?.toDouble();
            final lng = (d['eventLongitude'] as num?)?.toDouble();
            if (lat == null || lng == null) continue;
            eventMarkers.add(Marker(
              point: LatLng(lat, lng), width: 52, height: 62,
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _PetaDetailScreen(
                    petugasUser: widget.petugasUser,
                    eventLat: lat, eventLng: lng, eventName: d['eventName'] ?? 'Event',
                  ),
                )),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: _red, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 5)]),
                      child: const Icon(Icons.event_rounded, color: Colors.white, size: 18)),
                  CustomPaint(painter: _PinTailPainter(), size: const Size(10, 8)),
                ]),
              ),
            ));
          }

          return Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: _myLocation ?? _dinkesLocation, initialZoom: 12),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.ambuevent'),
                MarkerLayer(markers: [
                  if (_myLocation != null)
                    Marker(point: _myLocation!, width: 52, height: 52, alignment: Alignment.center,
                      child: Stack(alignment: Alignment.center, children: [
                        AnimatedContainer(duration: const Duration(milliseconds: 300),
                          width: _sharing ? 44 : 38, height: _sharing ? 44 : 38,
                          decoration: BoxDecoration(
                              color: (_sharing ? _green : _blue).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: (_sharing ? _green : _blue).withValues(alpha: 0.5), width: 2))),
                        Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: _sharing ? _green : _blue, shape: BoxShape.circle),
                            child: const Icon(Icons.person, color: Colors.white, size: 13)),
                      ])),
                  ...eventMarkers,
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
              ],
            ),
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4))]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_sharing ? _green : Colors.grey.shade400).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _sharing ? _green : Colors.grey.shade300, width: 1)),
                    child: Row(children: [
                      Icon(_sharing ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                          color: _sharing ? _green : Colors.grey, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_sharing ? 'Lokasi sedang dibagikan ke admin' : 'Lokasi tidak dibagikan',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                                color: _sharing ? _green : Colors.grey.shade600)),
                        Text(_sharing ? 'Admin dapat melihat posisi Anda di peta'
                            : 'Aktifkan agar admin bisa memantau Anda',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _toggleSharing,
                      icon: Icon(_sharing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                      label: Text(_sharing ? 'Stop Berbagi Lokasi' : 'Mulai Berbagi Lokasi GPS',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _sharing ? Colors.grey.shade600 : _green,
                          foregroundColor: Colors.white, elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    )),
                  if (eventMarkers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: _red.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.touch_app_rounded, color: _red, size: 15),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${eventMarkers.length} event aktif — tap marker untuk rute',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                      ]),
                    ),
                  ],
                ]),
              )),
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 3 — PROFIL
// ═══════════════════════════════════════════════════════════════════════
class PetugasProfilScreen extends StatelessWidget {
  final UserModel petugasUser;
  final VoidCallback onLogout;

  const PetugasProfilScreen({
    super.key,
    required this.petugasUser,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Halo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                Text('Selamat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                Text('Bertugas! 🚑', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ]),
              Column(children: [
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                  child: petugasUser.photoUrl.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(8),
                          child: Image.network(petugasUser.photoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 40, color: Colors.grey)))
                      : Center(child: Text(
                          petugasUser.name.isNotEmpty ? petugasUser.name[0].toUpperCase() : 'P',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
                ),
                const SizedBox(height: 8),
                Text(petugasUser.name.split(' ').first, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(petugasUser.email, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ]),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .snapshots(),
              builder: (ctx, snap) {
                final myDocs = (snap.data?.docs ?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final oldId = data['petugasId'] as String?;
                  if (oldId == petugasUser.uid) return true;
                  final list = data['petugasList'];
                  if (list is List) {
                    for (final item in list) {
                      if (item is Map && item['id'] == petugasUser.uid) return true;
                    }
                  }
                  return false;
                }).toList();
                final aktif   = myDocs.where((d) => (d.data() as Map)['status'] == 'Disetujui').length;
                final selesai = myDocs.where((d) => (d.data() as Map)['status'] == 'Selesai').length;
                final total   = myDocs.length;

                return ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(children: [
                      Expanded(child: _MenuStatCard(icon: Icons.assignment_turned_in_rounded,
                          label: 'Tugas Aktif', value: '$aktif', color: _green)),
                      const SizedBox(width: 10),
                      Expanded(child: _MenuStatCard(icon: Icons.check_circle_outline_rounded,
                          label: 'Selesai', value: '$selesai', color: _blue)),
                      const SizedBox(width: 10),
                      Expanded(child: _MenuStatCard(icon: Icons.assignment_outlined,
                          label: 'Total', value: '$total', color: _orange)),
                    ]),
                  ),
                  const Divider(height: 24, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_outlined, color: _orange, size: 18)),
                    title: const Text('Notifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: StreamBuilder<int>(
                      stream: NotificationService().streamUnreadCount(petugasUser.uid),
                      builder: (ctx, snap) {
                        final count = snap.data ?? 0;
                        if (count == 0) return const Icon(Icons.chevron_right, color: Colors.grey);
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(20)),
                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ]);
                      },
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PetugasNotificationScreen(userId: petugasUser.uid))),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.medical_services_rounded, color: _orange, size: 18)),
                    title: const Text('Role', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Petugas Medis'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: const Text('PETUGAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _orange))),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.email_outlined, color: _blue, size: 18)),
                    title: const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(petugasUser.email, style: const TextStyle(fontSize: 12)),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.info_outline, color: Colors.purple, size: 18)),
                    title: const Text('Tentang Aplikasi', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const _PetugasAboutScreen())),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.help_outline, color: Colors.teal, size: 18)),
                    title: const Text('Bantuan & FAQ', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const _PetugasHelpScreen())),
                  ),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                        child: const Icon(Icons.logout, color: Colors.white, size: 16)),
                    title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => _confirmLogout(context),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Keluar?', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('Yakin ingin keluar dari akun ini?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); onLogout(); },
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
          child: const Text('Keluar'),
        ),
      ],
    ));
  }
}

class _MenuStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MenuStatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _PetugasAboutScreen extends StatelessWidget {
  const _PetugasAboutScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Tentang Aplikasi',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(children: [
            Container(width: 80, height: 80,
                decoration: BoxDecoration(color: _red.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: ClipOval(child: Image.asset('assets/images/logo_ambuevent.png', fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.local_hospital_rounded, color: _red, size: 40)))),
            const SizedBox(height: 14),
            const Text('AMBUEVENT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: _red)),
            const SizedBox(height: 4),
            Text('Versi 1.0.0', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Dinas Kesehatan Kabupaten Madiun',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}

class _PetugasHelpScreen extends StatelessWidget {
  const _PetugasHelpScreen();

  static const _faqs = [
    {'q': 'Bagaimana cara melihat tugas saya?',
     'a': 'Buka tab "Tugas" di bagian bawah. Semua tugas yang ditugaskan admin akan tampil di sana.'},
    {'q': 'Bagaimana cara menandai tugas selesai?',
     'a': 'Di tab Tugas, tap kartu tugas yang berstatus "Disetujui", lalu tap tombol "Selesai".'},
    {'q': 'Bagaimana cara melihat notifikasi penugasan?',
     'a': 'Buka tab Profil → tap menu "Notifikasi".'},
    {'q': 'Bagaimana cara berbagi lokasi ke admin?',
     'a': 'Buka tab "Peta", lalu tap tombol "Mulai Berbagi Lokasi GPS".'},
    {'q': 'Bagaimana melihat rute ke lokasi event?',
     'a': 'Di tab Tugas, tap tombol "Lihat Rute" pada kartu tugas.'},
    {'q': 'Apa yang harus dilakukan jika GPS tidak aktif?',
     'a': 'Aktifkan layanan lokasi (GPS) di pengaturan perangkat Anda, lalu coba lagi.'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Bantuan & FAQ',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ..._faqs.map((f) => _FaqTile(question: f['q']!, answer: f['a']!)),
      ]),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question, answer;
  const _FaqTile({required this.question, required this.answer});
  @override State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _open ? _blue.withValues(alpha: 0.3) : Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(14),
          child: Padding(padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 24, height: 24,
                  decoration: BoxDecoration(color: _open ? _blue : Colors.grey.shade100, shape: BoxShape.circle),
                  child: Icon(_open ? Icons.remove : Icons.add, size: 14,
                      color: _open ? Colors.white : Colors.grey.shade500)),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.question,
                  style: TextStyle(fontSize: 13,
                      fontWeight: _open ? FontWeight.w700 : FontWeight.w500,
                      color: _open ? _blue : Colors.black87))),
            ])),
        ),
        if (_open)
          Padding(padding: const EdgeInsets.fromLTRB(50, 0, 14, 14),
            child: Text(widget.answer,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5))),
      ]),
    );
  }
}