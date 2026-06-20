// lib/screens/admin_screens.dart
// UPDATED: palette warna diubah ke soft/muted, tidak mencolok
// UPDATED: recalculate ambulance availability otomatis saat save booking
// UPDATED: [FIX 1] _AmbSheet._save() tidak lagi reset available:true saat edit
// UPDATED: [FIX 2] recalculateAmbulanceAvailability dipanggil setelah edit armada
// UPDATED: [FIX 3] Armada konflik di Edit Booking Sheet = DISABLED (tidak bisa dipilih)
// UPDATED: [FIX 4] Auto-lepas armada konflik dari selection saat sheet dibuka
// UPDATED: [FIX 5] Toggle switch available di AmbCard DISABLED (hanya indikator)
// UPDATED: [FIX 6] Hapus booking via deleteBooking (recalculate ambulans otomatis)
// UPDATED: [FIX 7] Petugas konflik di Edit Booking Sheet = DISABLED (tidak bisa dipilih)
// UPDATED: [FIX 8] Auto-lepas petugas konflik dari selection saat sheet dibuka
// UPDATED: [FIX 9] Banner & badge diselaraskan: hanya "Disetujui" yang mengunci resource
// ignore_for_file: avoid_print
 
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../service/firestore_service.dart';
import '../service/notification_service.dart';
import '../service/auth_service.dart';
import '../service/map_service.dart';
 
// ─────────────────────────── PALETTE (soft/muted) ─────────────────
const _red    = Color(0xFFC0392B);
const _green  = Color(0xFF2E7D6B);
const _blue   = Color(0xFF4A6FA5);
const _orange = Color(0xFFB7600A);
const _bg     = Color(0xFFF7F5F3);
 
const _redLight    = Color(0xFFEDD9D7);
const _greenLight  = Color(0xFFD0EAE5);
const _blueLight   = Color(0xFFD6E4F0);
const _orangeLight = Color(0xFFF5E6D3);
 
const _border      = Color(0xFFE8E4E1);
const _textPrimary = Color(0xFF2C2520);
const _textMuted   = Color(0xFF7A706A);
 
// ─────────────────────────── PHOTO MODEL ──────────────────────────────
class _Photo {
  final String name;
  final String base64Data;
  _Photo({required this.name, required this.base64Data});
 
  bool get hasData => base64Data.isNotEmpty;
 
  Uint8List? get bytes {
    if (!hasData) return null;
    try { return base64Decode(base64Data); }
    catch (_) { return null; }
  }
}
 
// ─────────────────────────── FASKES HELPERS ───────────────────────────
List<Map<String, String>> _getFaskesList() {
  final list = MapService().getPuskesmasList();
  return list.map((p) => {
    'id': 'faskes_${p.no}',
    'name': p.name,
  }).toList();
}
 
// ─────────────────────────── TIPE KENDARAAN ───────────────────────────
const List<Map<String, dynamic>> _vehicleTypes = [
  {'label': 'Ambulans Gawat Darurat', 'icon': Icons.emergency_rounded,        'color': _red},
  {'label': 'Ambulans Transport',     'icon': Icons.airport_shuttle_rounded,   'color': _blue},
];
 
const List<Map<String, dynamic>> _vehicleNames = [
  {'key': 'hyundai_starex_1', 'label': 'Hyundai Mover Starex', 'icon': Icons.airport_shuttle_rounded, 'color': _red},
  {'key': 'hyundai_starex_2', 'label': 'Hyundai Mover Starex', 'icon': Icons.airport_shuttle_rounded, 'color': _blue},
  {'key': 'toyota_hiace',     'label': 'Toyota Hiace Premio',  'icon': Icons.directions_bus_rounded,  'color': _green},
  {'key': 'suzuki_apv',       'label': 'Suzuki APV',           'icon': Icons.directions_car_rounded,  'color': _orange},
];
 
// ─────────────────────────── ASSIGN MODELS ────────────────────────────
class _AssignedPetugas {
  final String id;
  final String name;
  final String faskes;
  _AssignedPetugas({required this.id, required this.name, required this.faskes});
 
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'faskes': faskes};
 
  factory _AssignedPetugas.fromMap(Map<String, dynamic> m) => _AssignedPetugas(
        id:     m['id']     ?? '',
        name:   m['name']   ?? '',
        faskes: m['faskes'] ?? '',
      );
}
 
class _AssignedAmbulance {
  final String id;
  final String plate;
  final String type;
  final String vehicleName;
 
  _AssignedAmbulance({
    required this.id,
    required this.plate,
    required this.type,
    this.vehicleName = '',
  });
 
  Map<String, dynamic> toMap() => {
    'id': id,
    'plate': plate,
    'type': type,
    'vehicleName': vehicleName,
  };
 
  factory _AssignedAmbulance.fromMap(Map<String, dynamic> m) => _AssignedAmbulance(
        id:          m['id']          ?? '',
        plate:       m['plate']       ?? '',
        type:        m['type']        ?? '',
        vehicleName: m['vehicleName'] ?? '',
      );
}
 
// ═══════════════════════════ ADMIN KEGIATAN SCREEN ═══════════════════════
class AdminKegiatanScreen extends StatefulWidget {
  final VoidCallback onBack;
  const AdminKegiatanScreen({super.key, required this.onBack});
  @override State<AdminKegiatanScreen> createState() => _AdminKegiatanState();
}
 
class _AdminKegiatanState extends State<AdminKegiatanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late final List<Stream<QuerySnapshot>> _streams;
 
  static const _tabLabels = ['Menunggu','Disetujui','Ditolak','Selesai','Rekap'];
  static const _statuses  = [
    'Menunggu Konfirmasi','Disetujui','Ditolak','Selesai'
  ];
 
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabLabels.length, vsync: this);
    _streams = _statuses.map((s) =>
      FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: s)
        .snapshots(),
    ).toList();
  }
 
  @override
  void dispose() { _tab.dispose(); super.dispose(); }
 
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) widget.onBack(); },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Kelola Kegiatan',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: _textPrimary)),
          backgroundColor: Colors.white,
          elevation: 0, scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: _textPrimary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: widget.onBack,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: Colors.white,
              child: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: _red,
                unselectedLabelColor: _textMuted,
                indicatorColor: _red,
                indicatorWeight: 2,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
                tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            ...List.generate(_statuses.length, (i) =>
              _BookingList(
                key: PageStorageKey(_statuses[i]),
                stream: _streams[i],
                statusLabel: _tabLabels[i],
              ),
            ),
            const _RekapBulananTab(key: PageStorageKey('rekap')),
          ],
        ),
      ),
    );
  }
}
 
// ─────────────── BOOKING LIST ─────────────────────────────────────────
class _BookingList extends StatefulWidget {
  final Stream<QuerySnapshot> stream;
  final String statusLabel;
  const _BookingList({required super.key, required this.stream, required this.statusLabel});
  @override State<_BookingList> createState() => _BookingListState();
}
 
class _BookingListState extends State<_BookingList>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
 
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: widget.stream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text("Gagal memuat data.\n${snap.error}",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMuted, fontSize: 12)),
            ]),
          ));
        }
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
        }
        final rawDocs = snap.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot>.from(rawDocs)
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['createdAt'];
            final bTs = bData['createdAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
 
        if (docs.isEmpty) return _EmptyTab(label: widget.statusLabel);
 
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) => _BookingCard(
            key: ValueKey(docs[i].id),
            doc: docs[i],
          ),
        );
      },
    );
  }
}
class _EmptyTab extends StatelessWidget {
  final String label;
  const _EmptyTab({required this.label});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 12)]),
        child: Icon(Icons.inbox_outlined, size: 44, color: Colors.grey.shade300)),
      const SizedBox(height: 14),
      Text('Tidak ada booking "$label"',
          style: TextStyle(color: _textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
    ],
  ));
}
 
// ─────────────────────────── BOOKING CARD ─────────────────────────────
class _BookingCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  const _BookingCard({required super.key, required this.doc});
  @override State<_BookingCard> createState() => _BookingCardState();
}
 
class _BookingCardState extends State<_BookingCard> {
  final _fs    = FirestoreService();
  final _notif = NotificationService();
  bool _expanded = false;
  bool _loading  = false;
 
  List<_Photo> _parsePhotos(Map<String,dynamic> d) {
    final nf = d['documentFiles'];
    if (nf is List && nf.isNotEmpty) {
      return nf.map((e) {
        final m = e as Map<String,dynamic>;
        return _Photo(name: m['name'] ?? '', base64Data: m['base64Data'] ?? '');
      }).toList();
    }
    final of = d['documents'];
    if (of is List && of.isNotEmpty) {
      return of.map((e) => _Photo(name: '$e', base64Data: '')).toList();
    }
    return [];
  }
 
  List<_AssignedPetugas> _parsePetugasList(Map<String, dynamic> d) {
    final raw = d['petugasList'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => _AssignedPetugas.fromMap(Map<String,dynamic>.from(e as Map))).toList();
    }
    final id   = d['petugasId']    as String?;
    final name = d['petugasName']  as String?;
    final fsk  = d['petugasFaskes'] as String?;
    if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
      return [_AssignedPetugas(id: id, name: name, faskes: fsk ?? '')];
    }
    return [];
  }
 
  List<_AssignedAmbulance> _parseAmbulanceList(Map<String, dynamic> d) {
    final raw = d['ambulanceList'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => _AssignedAmbulance.fromMap(Map<String,dynamic>.from(e as Map))).toList();
    }
    final id    = d['ambulanceId']    as String?;
    final plate = d['ambulancePlate'] as String?;
    if (id != null && id.isNotEmpty && plate != null && plate.isNotEmpty) {
      return [_AssignedAmbulance(id: id, plate: plate, type: '', vehicleName: '')];
    }
    return [];
  }
 
  Color _sColor(String s) {
    switch(s) {
      case 'Disetujui': return _green;
      case 'Ditolak':   return _red;
      case 'Selesai':   return _blue;
      default:          return _orange;
    }
  }
 
  Color _sBgColor(String s) {
    switch(s) {
      case 'Disetujui': return _greenLight;
      case 'Ditolak':   return _redLight;
      case 'Selesai':   return _blueLight;
      default:          return _orangeLight;
    }
  }
 
  IconData _sIcon(String s) {
    switch(s) {
      case 'Disetujui': return Icons.check_circle_rounded;
      case 'Ditolak':   return Icons.cancel_rounded;
      case 'Selesai':   return Icons.verified_rounded;
      default:          return Icons.hourglass_top_rounded;
    }
  }
 
  Future<void> _updateStatus(String ns) async {
    setState(() => _loading = true);
    final d = widget.doc.data() as Map<String,dynamic>;
    await _fs.updateBookingStatus(widget.doc.id, ns);
    try {
      final ptList = _parsePetugasList(d);
      await _notif.notifyBookingStatus(
        userId: d['userId']??'', eventName: d['eventName']??'', newStatus: ns,
        petugasName: ptList.isNotEmpty ? ptList.map((p) => p.name).join(', ') : null,
      );
    } catch(e) { print('Notif: $e'); }
    if (mounted) setState(() => _loading = false);
  }
 
  void _openEdit() {
    final d = widget.doc.data() as Map<String,dynamic>;
    final pCtx = context;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _EditBookingSheet(
        docId: widget.doc.id, data: d, fs: _fs, notif: _notif,
        parentContext: pCtx,
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final d       = widget.doc.data() as Map<String,dynamic>;
    final s       = d['status'] as String? ?? '-';
    final photos  = _parsePhotos(d);
    final color   = _sColor(s);
    final bgColor = _sBgColor(s);
    final ptList  = _parsePetugasList(d);
    final ambList = _parseAmbulanceList(d);
 
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0,3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Icon(_sIcon(s), size: 13, color: color),
            const SizedBox(width: 6),
            Text(s, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(d['date']??'-', style: TextStyle(color: _textMuted, fontSize: 11)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14,12,14,0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.event_note_rounded, color: _red, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['eventName']??'-',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(d['userName']??'-',
                  style: TextStyle(color: _textMuted, fontSize: 12)),
            ])),
            GestureDetector(
              onTap: _openEdit,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit_rounded, size: 14, color: _blue),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14,10,14,0),
          child: Column(children: [
            _iRow(Icons.location_on_rounded, d['location']??'-'),
            const SizedBox(height: 4),
            _iRow(Icons.category_rounded, d['type']??'-'),
            if (ptList.isNotEmpty) ...[
              const SizedBox(height: 7),
              _multiChipRow(
                icon: Icons.medical_services_rounded, label: 'Petugas', color: _green,
                items: ptList.map((p) => p.faskes.isNotEmpty ? '${p.name} · ${p.faskes}' : p.name).toList(),
              ),
            ],
            if (ambList.isNotEmpty) ...[
              const SizedBox(height: 5),
              _multiChipRow(
                icon: Icons.local_hospital_rounded, label: 'Armada', color: _blue,
                items: ambList.map((a) {
                  if (a.vehicleName.isNotEmpty) return a.vehicleName;
                  if (a.type.isNotEmpty) return a.type;
                  return a.plate;
                }).toList(),
              ),
            ],
          ]),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(children: [
                Icon(Icons.photo_library_outlined, size: 13, color: _textMuted),
                const SizedBox(width: 4),
                Text('${photos.length} foto', style: TextStyle(fontSize: 11, color: _textMuted)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_expanded ? 'Sembunyikan' : 'Lihat Foto',
                        style: const TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.w500)),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 13, color: _blue),
                  ]),
                ),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _PhotoGrid(photos: photos),
            ),
        ],
        const SizedBox(height: 10),
        const Divider(height: 1, indent: 14, endIndent: 14, color: _border),
        if (_loading)
          const Padding(padding: EdgeInsets.all(14),
            child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _red))))
        else
          _buildActions(s),
      ]),
    );
  }
 
  Widget _iRow(IconData icon, String val, {Color? color}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: color ?? Colors.grey.shade400),
        const SizedBox(width: 6),
        Expanded(child: Text(val,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
                color: color ?? _textMuted),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);
 
  Widget _multiChipRow({
    required IconData icon, required String label,
    required Color color, required List<String> items,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Wrap(spacing: 4, runSpacing: 3, children: items.map((item) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color == _green ? _greenLight : color == _blue ? _blueLight : _redLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(item, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        )).toList()),
      ])),
    ]);
  }
 
  Widget _buildActions(String s) {
    if (s == 'Menunggu Konfirmasi') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14,9,14,12),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _updateStatus('Ditolak'),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Tolak'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _red, side: BorderSide(color: _red.withValues(alpha:0.6)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _updateStatus('Disetujui'),
            icon: const Icon(Icons.check_rounded, size: 14),
            label: const Text('Setujui'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
        ]),
      );
    }
    if (s == 'Disetujui') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14,9,14,12),
        child: SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _updateStatus('Selesai'),
            icon: const Icon(Icons.verified_rounded, size: 14),
            label: const Text('Tandai Selesai'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
      );
    }
    return const SizedBox(height: 12);
  }
}
 
// ─────────────── GRID FOTO ────────────────────────────────────────────
class _PhotoGrid extends StatelessWidget {
  final List<_Photo> photos;
  const _PhotoGrid({required this.photos});
 
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (ctx, i) => _PhotoTile(photo: photos[i], index: i, allPhotos: photos),
    );
  }
}
 
class _PhotoTile extends StatelessWidget {
  final _Photo photo;
  final int index;
  final List<_Photo> allPhotos;
  const _PhotoTile({required this.photo, required this.index, required this.allPhotos});
 
  @override
  Widget build(BuildContext context) {
    final bytes = photo.bytes;
    return GestureDetector(
      onTap: () {
        if (bytes != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _PhotoViewerScreen(photos: allPhotos, initialIndex: index),
          ));
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover)
            : Container(
                color: Colors.grey.shade100,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade300, size: 22),
                  const SizedBox(height: 3),
                  Text(photo.name,
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                      maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                ]),
              ),
      ),
    );
  }
}
 
// ─────────────── PHOTO VIEWER ─────────────────────────────────────────
class _PhotoViewerScreen extends StatefulWidget {
  final List<_Photo> photos;
  final int initialIndex;
  const _PhotoViewerScreen({required this.photos, required this.initialIndex});
  @override State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}
 
class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  late PageController _pageCtrl;
  late int _current;
 
  @override
  void initState() {
    super.initState();
    _current  = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }
 
  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }
 
  Future<void> _download(BuildContext ctx, _Photo photo) async {
    final bytes = photo.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Data foto tidak tersedia.'), backgroundColor: Colors.grey));
      return;
    }
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Menyimpan foto...'), duration: Duration(seconds: 1)));
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${photo.name}');
      await file.writeAsBytes(bytes);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Tersimpan: ${file.path}'),
          backgroundColor: _green, duration: const Duration(seconds: 3)));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'), backgroundColor: _red));
      }
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_current + 1} / ${widget.photos.length}  ·  ${widget.photos[_current].name}',
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: () => _download(context, widget.photos[_current]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) {
          final bytes = widget.photos[i].bytes;
          if (bytes == null) {
            return const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 64));
          }
          return Center(child: InteractiveViewer(
            minScale: 0.5, maxScale: 8,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ));
        },
      ),
      bottomNavigationBar: widget.photos.length > 1
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.photos.length, (i) => Container(
                  width: i == _current ? 16 : 6, height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _current ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(3)),
                )),
              ),
            )
          : null,
    );
  }
}
 
// ══════════════════════════════════════════════════════════════════════
// EDIT BOOKING SHEET
// ══════════════════════════════════════════════════════════════════════
class _EditBookingSheet extends StatefulWidget {
  final String docId;
  final Map<String,dynamic> data;
  final FirestoreService fs;
  final NotificationService notif;
  final BuildContext parentContext;
  const _EditBookingSheet({required this.docId, required this.data,
    required this.fs, required this.notif, required this.parentContext});
  @override State<_EditBookingSheet> createState() => _EditBookingSheetState();
}
 
class _EditBookingSheetState extends State<_EditBookingSheet> {
  late String _status;
  late List<_AssignedPetugas> _previousPetugas;
  List<_AssignedPetugas>   _selectedPetugas   = [];
  List<_AssignedAmbulance> _selectedAmbulance = [];
  bool _saving = false;
 
  // Konflik ambulans: ambulanceId → list info booking yang memakainya
  Map<String, List<AmbulanceConflictInfo>> _conflictDetail = {};
  // Konflik petugas: petugasId → list info booking yang sudah menugaskannya
  Map<String, List<AmbulanceConflictInfo>> _petugasConflictDetail = {};
  bool _loadingConflict = false;
 
  late final Stream<QuerySnapshot> _petugasStream;
  late final Stream<QuerySnapshot> _ambStream;
 
  String get _bookingDate => widget.data['date'] as String? ?? '';
 
  @override
  void initState() {
    super.initState();
    _status = widget.data['status'] ?? 'Menunggu Konfirmasi';
 
    // Parse petugas terpilih saat ini
    final rawPt = widget.data['petugasList'];
    if (rawPt is List && rawPt.isNotEmpty) {
      _selectedPetugas = rawPt
          .map((e) => _AssignedPetugas.fromMap(Map<String,dynamic>.from(e as Map)))
          .toList();
    } else {
      final id   = widget.data['petugasId']    as String?;
      final name = widget.data['petugasName']  as String?;
      final fsk  = widget.data['petugasFaskes'] as String?;
      if (id != null && id.isNotEmpty) {
        _selectedPetugas = [_AssignedPetugas(id: id, name: name ?? '', faskes: fsk ?? '')];
      }
    }
    _previousPetugas = List.from(_selectedPetugas);
 
    // Parse armada terpilih saat ini
    final rawAmb = widget.data['ambulanceList'];
    if (rawAmb is List && rawAmb.isNotEmpty) {
      _selectedAmbulance = rawAmb
          .map((e) => _AssignedAmbulance.fromMap(Map<String,dynamic>.from(e as Map)))
          .toList();
    } else {
      final id    = widget.data['ambulanceId']    as String?;
      final plate = widget.data['ambulancePlate'] as String?;
      if (id != null && id.isNotEmpty) {
        _selectedAmbulance = [_AssignedAmbulance(id: id, plate: plate ?? '', type: '', vehicleName: '')];
      }
    }
 
    _petugasStream = FirebaseFirestore.instance
        .collection('users').where('role', isEqualTo: 'petugas').snapshots();
    _ambStream = FirebaseFirestore.instance.collection('ambulances').snapshots();
 
    if (_bookingDate.isNotEmpty) {
      _loadConflictDetail();
    }
  }
 
  /// Load konflik ambulans DAN petugas secara paralel
  Future<void> _loadConflictDetail() async {
    setState(() => _loadingConflict = true);
    try {
      final results = await Future.wait([
        widget.fs.getAmbulanceConflictDetail(
          date: _bookingDate,
          excludeBookingId: widget.docId,
        ),
        widget.fs.getPetugasConflictDetail(
          date: _bookingDate,
          excludeBookingId: widget.docId,
        ),
      ]);
 
      if (mounted) {
        setState(() {
          _conflictDetail        = results[0];
          _petugasConflictDetail = results[1];
 
          // Auto-lepas petugas yang sebelumnya sudah terpilih di booking ini
          // tetapi ternyata bentrok dengan booking lain (Disetujui)
          // pada tanggal yang sama.
          _selectedPetugas.removeWhere(
            (p) => _petugasConflictDetail.containsKey(p.id),
          );
        });
      }
    } catch (e) {
      print('[EditBooking] loadConflictDetail error: $e');
    } finally {
      if (mounted) setState(() => _loadingConflict = false);
    }
  }
 
  int get _totalAmbConflicts     => _conflictDetail.length;
  int get _totalPetugasConflicts => _petugasConflictDetail.length;
 
  /// Toggle pilih/batal-pilih petugas — blok jika konflik
  void _togglePetugas(QueryDocumentSnapshot doc) {
    final dData  = doc.data() as Map<String, dynamic>;
    final id     = doc.id;
    final name   = dData['name']       as String? ?? '';
    final faskes = dData['faskesName'] as String? ?? '';
 
    final conflicts   = _petugasConflictDetail[id];
    final hasConflict = conflicts != null && conflicts.isNotEmpty;
    final alreadySel  = _selectedPetugas.any((p) => p.id == id);
 
    if (hasConflict && !alreadySel) {
      final namaEvent = conflicts!.first.eventName;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.lock_rounded, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Petugas ini sudah bertugas di "$namaEvent" (Disetujui)',
            style: const TextStyle(fontSize: 12),
          )),
        ]),
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
 
    setState(() {
      final idx = _selectedPetugas.indexWhere((p) => p.id == id);
      if (idx >= 0) {
        _selectedPetugas.removeAt(idx);
      } else {
        _selectedPetugas.add(_AssignedPetugas(id: id, name: name, faskes: faskes));
      }
    });
  }
 
  /// Toggle pilih/batal-pilih armada — blok jika konflik
  void _toggleAmbulance(QueryDocumentSnapshot doc) {
    final id      = doc.id;
    final dData   = doc.data() as Map<String, dynamic>;
    final plate   = dData['plate']       as String? ?? '';
    final type    = dData['type']        as String? ?? '';
    String rawVName = dData['vehicleName'] as String? ?? '';
    if (rawVName.contains('·')) rawVName = rawVName.split('·').first.trim();
    final vehicleName = (rawVName.isEmpty || rawVName == plate) ? '' : rawVName;
 
    final conflicts   = _conflictDetail[id];
    final hasConflict = conflicts != null && conflicts.isNotEmpty;
    final alreadySel  = _selectedAmbulance.any((a) => a.id == id);
 
    if (hasConflict && !alreadySel) {
      final namaEvent = conflicts!.first.eventName;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.lock_rounded, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Armada ini sudah dipakai di "$namaEvent" (Disetujui)',
            style: const TextStyle(fontSize: 12),
          )),
        ]),
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
 
    setState(() {
      final idx = _selectedAmbulance.indexWhere((a) => a.id == id);
      if (idx >= 0) {
        _selectedAmbulance.removeAt(idx);
      } else {
        _selectedAmbulance.add(_AssignedAmbulance(
          id: id, plate: plate, type: type, vehicleName: vehicleName,
        ));
      }
    });
  }
 
  Future<void> _save() async {
    setState(() => _saving = true);
 
    final uid       = widget.data['userId']    as String? ?? '';
    final eventName = widget.data['eventName'] as String? ?? '';
    final eventDate = widget.data['date']      as String? ?? '';
    final eventLoc  = widget.data['location']  as String?
                      ?? widget.data['eventLoc'] as String? ?? '';
 
    final ptMaps  = _selectedPetugas.map((p)  => p.toMap()).toList();
    final ambMaps = _selectedAmbulance.map((a) => a.toMap()).toList();
    final firstPt  = _selectedPetugas.isNotEmpty  ? _selectedPetugas.first  : null;
    final firstAmb = _selectedAmbulance.isNotEmpty ? _selectedAmbulance.first : null;
 
    // Kumpulkan ID ambulans SEBELUM diupdate
    final prevAmbulanceIds = <String>[];
    final rawPrevAmb = widget.data['ambulanceList'];
    if (rawPrevAmb is List && rawPrevAmb.isNotEmpty) {
      for (final e in rawPrevAmb) {
        final id = (e as Map<String, dynamic>)['id'] as String?;
        if (id != null && id.isNotEmpty) prevAmbulanceIds.add(id);
      }
    } else {
      final oldId = widget.data['ambulanceId'] as String?;
      if (oldId != null && oldId.isNotEmpty) prevAmbulanceIds.add(oldId);
    }
    final newAmbulanceIds = _selectedAmbulance.map((a) => a.id).toList();
 
    // Kumpulkan ID petugas SEBELUM diupdate
    final prevPetugasIds = <String>[];
    final rawPrevPt = widget.data['petugasList'];
    if (rawPrevPt is List && rawPrevPt.isNotEmpty) {
      for (final e in rawPrevPt) {
        final id = (e as Map<String, dynamic>)['id'] as String?;
        if (id != null && id.isNotEmpty) prevPetugasIds.add(id);
      }
    } else {
      final oldId = widget.data['petugasId'] as String?;
      if (oldId != null && oldId.isNotEmpty) prevPetugasIds.add(oldId);
    }
    final newPetugasIds = _selectedPetugas.map((p) => p.id).toList();
 
    // Update booking di Firestore
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.docId)
        .update({
      'status':         _status,
      'petugasList':    ptMaps,
      'ambulanceList':  ambMaps,
      'petugasId':      firstPt?.id,
      'petugasName':    firstPt?.name,
      'petugasFaskes':  firstPt?.faskes,
      'ambulanceId':    firstAmb?.id,
      'ambulancePlate': firstAmb?.plate,
    });
 
    // Recalculate ketersediaan ambulans yang terdampak
    try {
      await widget.fs.recalculateAllAffectedAmbulances(
        prevAmbulanceIds: prevAmbulanceIds,
        newAmbulanceIds:  newAmbulanceIds,
      );
    } catch (e) {
      print('Recalculate ambulance error: $e');
    }

    // Recalculate ketersediaan petugas yang terdampak
    try {
      await widget.fs.recalculateAllAffectedPetugas(
        prevPetugasIds: prevPetugasIds,
        newPetugasIds:  newPetugasIds,
      );
    } catch (e) {
      print('Recalculate petugas error: $e');
    }
 
    // Notifikasi ke user
    try {
      await widget.notif.notifyBookingStatus(
        userId:        uid,
        eventName:     eventName,
        newStatus:     _status,
        petugasName:   _selectedPetugas.isNotEmpty
            ? _selectedPetugas.map((p) => p.name).join(', ') : null,
        ambulancePlate: _selectedAmbulance.isNotEmpty
            ? _selectedAmbulance.map((a) => a.plate).join(', ') : null,
      );
    } catch(e) { print('Notif user: $e'); }
 
    // Notifikasi ke petugas (yang baru di-assign / dilepas)
    try {
      final prevIds    = _previousPetugas.map((p) => p.id).toSet();
      final currentIds = _selectedPetugas.map((p) => p.id).toSet();
      final newlyAssigned = _selectedPetugas
          .where((p) => !prevIds.contains(p.id)).map((p) => p.id).toList();
      final removed = _previousPetugas
          .where((p) => !currentIds.contains(p.id)).map((p) => p.id).toList();
 
      if (newlyAssigned.isNotEmpty || removed.isNotEmpty) {
        await widget.notif.notifyPetugasAssigned(
          petugasIds:        newlyAssigned,
          removedPetugasIds: removed,
          eventName:         eventName,
          eventDate:         eventDate,
          eventLocation:     eventLoc,
          bookingId:         widget.docId,
        );
      }
    } catch(e) { print('Notif petugas: $e'); }
 
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Booking diperbarui!'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
    }
  }
 
  Future<void> _delete() async {
    final pCtx = widget.parentContext;
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!pCtx.mounted) return;
    final ok = await _confirmDialog(pCtx, 'Hapus Booking?',
        'Booking "${widget.data['eventName']}" akan dihapus permanen.');
    if (ok == true) {
      await widget.fs.deleteBooking(widget.docId);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    const ss  = ['Menunggu Konfirmasi','Disetujui','Ditolak','Selesai'];
    final sColors = {
      'Menunggu Konfirmasi': _orange,
      'Disetujui': _green, 'Ditolak': _red, 'Selesai': _blue,
    };
    final sBgColors = {
      'Menunggu Konfirmasi': _orangeLight,
      'Disetujui': _greenLight, 'Ditolak': _redLight, 'Selesai': _blueLight,
    };
 
    return Container(
      margin: const EdgeInsets.fromLTRB(12,0,12,12),
      padding: EdgeInsets.fromLTRB(20,20,20,20+pad),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.10), blurRadius: 24)]),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
 
          // ── Header ──────────────────────────────────────────────────
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Edit Booking', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: _textPrimary)),
              const SizedBox(height: 2),
              Text(widget.data['eventName']??'-',
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            _iconBtn(Icons.delete_outline_rounded, _red, _delete),
          ]),
 
          // ── Info tanggal + badge konflik gabungan ────────────────────
          if (_bookingDate.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 13, color: _textMuted),
                const SizedBox(width: 7),
                Text('Tanggal event: $_bookingDate',
                    style: const TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (_loadingConflict)
                  const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _orange)),
                if (!_loadingConflict && (_totalAmbConflicts > 0 || _totalPetugasConflicts > 0)) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: _orangeLight, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_rounded, size: 11, color: _orange),
                      const SizedBox(width: 3),
                      Text('${_totalAmbConflicts + _totalPetugasConflicts} terkunci',
                          style: const TextStyle(fontSize: 10, color: _orange, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 22),
 
          // ── Status Booking ───────────────────────────────────────────
          _sectionTitle('Status Booking'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: ss.map((s) {
            final sel = _status == s;
            final c   = sColors[s]!;
            final bg  = sBgColors[s]!;
            return GestureDetector(
              onTap: () => setState(() => _status = s),
              child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? c : bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? c : Colors.transparent)),
                child: Text(s, style: TextStyle(
                    color: sel ? Colors.white : c, fontSize: 12, fontWeight: FontWeight.w600))),
            );
          }).toList()),
          const SizedBox(height: 24),
 
          // ══════════════════════════════════════════════════════════════
          // ASSIGN PETUGAS
          // ══════════════════════════════════════════════════════════════
          Row(children: [
            _sectionTitle('Assign Petugas'),
            const Spacer(),
            if (_selectedPetugas.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
                child: Text('${_selectedPetugas.length} dipilih',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Tap untuk memilih / batal pilih',
              style: TextStyle(fontSize: 11, color: _textMuted)),
          const SizedBox(height: 8),
 
          // ── [FIX 9] Banner petugas terkunci: teks diselaraskan dengan logika _lockingStatuses ──
          if (_totalPetugasConflicts > 0) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orangeLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lock_rounded, color: _orange, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$_totalPetugasConflicts petugas terkunci — sudah bertugas di booking yang Disetujui pada tanggal ini.',
                      style: const TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('Petugas pada booking "Menunggu Konfirmasi" masih bisa dipilih.',
                      style: TextStyle(fontSize: 10, color: _orange)),
                ])),
              ]),
            ),
            const SizedBox(height: 8),
          ],
 
          // Chip petugas yang sudah dipilih
          if (_selectedPetugas.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6,
              children: _selectedPetugas.map((p) => _SelectedChip(
                label: p.faskes.isNotEmpty ? '${p.name} · ${p.faskes}' : p.name,
                color: _green,
                onRemove: () => setState(() => _selectedPetugas.removeWhere((x) => x.id == p.id)),
              )).toList(),
            ),
            const SizedBox(height: 10),
          ],
 
          // List petugas (card style sama persis dengan armada)
          StreamBuilder<QuerySnapshot>(
            stream: _petugasStream,
            builder: (ctx, snap) {
              final list = snap.data?.docs ?? [];
              if (list.isEmpty) return _emptyHint('Belum ada petugas terdaftar');
              return Column(
                children: list.map((doc) {
                  final dd    = doc.data() as Map<String, dynamic>;
                  final name  = dd['name']       as String? ?? doc.id;
                  final fsk   = dd['faskesName'] as String? ?? '';
                  final avail = dd['available']  as bool?   ?? true;
                  final sel   = _selectedPetugas.any((p) => p.id == doc.id);

                  final ptConflicts   = _petugasConflictDetail[doc.id];
                  final hasPtConflict = ptConflicts != null && ptConflicts.isNotEmpty;

                  // ── Disabled card: petugas sudah dikunci booking Disetujui lain ──
                  if (hasPtConflict) {
                    return _buildDisabledPetugasCard(
                      name: name, faskes: fsk, conflicts: ptConflicts!,
                    );
                  }

                  // ── Card normal: bisa dipilih ──
                  return GestureDetector(
                    onTap: () => _togglePetugas(doc),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: sel ? _greenLight : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: sel ? _green : _border,
                            width: sel ? 1.5 : 1),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 5,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 11),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: _green.withValues(alpha: sel ? 0.20 : 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.medical_services_rounded,
                                color: _green, size: 20),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: sel ? _green : _textPrimary,
                                ),
                              ),
                              if (fsk.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: _bg,
                                      borderRadius: BorderRadius.circular(5)),
                                  child: Text(fsk,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: _textMuted)),
                                ),
                              ],
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (avail ? _green : Colors.grey)
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  Icon(
                                    avail
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 10,
                                    color: avail ? _green : Colors.grey,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    avail ? 'TERSEDIA' : 'SEDANG BERTUGAS',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: avail ? _green : Colors.grey,
                                    ),
                                  ),
                                ]),
                              ),
                            ]),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: sel ? _green : Colors.transparent,
                              border: Border.all(
                                  color: sel ? _green : _border, width: 1.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: sel
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 22),
 
          // ══════════════════════════════════════════════════════════════
          // ASSIGN ARMADA
          // ══════════════════════════════════════════════════════════════
          Row(children: [
            _sectionTitle('Assign Armada'),
            const Spacer(),
            if (_selectedAmbulance.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(20)),
                child: Text('${_selectedAmbulance.length} dipilih',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 4),
 
          // ── [FIX 9] Banner armada terkunci: teks diselaraskan dengan logika _lockingStatuses ──
          if (_totalAmbConflicts > 0) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orangeLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lock_rounded, color: _orange, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$_totalAmbConflicts armada dikunci — sudah terjadwal di booking yang Disetujui pada tanggal ini.',
                      style: const TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('Armada pada booking "Menunggu Konfirmasi" masih bisa dipilih.',
                      style: TextStyle(fontSize: 10, color: _orange)),
                ])),
              ]),
            ),
            const SizedBox(height: 8),
          ],
 
          Text('Tap kartu untuk memilih / batal pilih',
              style: TextStyle(fontSize: 11, color: _textMuted)),
          const SizedBox(height: 10),
 
          // Chip armada yang sudah dipilih
          if (_selectedAmbulance.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6,
              children: _selectedAmbulance.map((a) => _SelectedChip(
                label: a.vehicleName.isNotEmpty
                    ? a.vehicleName : a.type.isNotEmpty ? a.type : a.plate,
                color: _blue,
                onRemove: () => setState(() => _selectedAmbulance.removeWhere((x) => x.id == a.id)),
              )).toList(),
            ),
            const SizedBox(height: 10),
          ],
 
          // List armada
          StreamBuilder<QuerySnapshot>(
            stream: _ambStream,
            builder: (ctx, snap) {
              final list = snap.data?.docs ?? [];
              if (list.isEmpty) return _emptyHint('Belum ada armada terdaftar');
              return Column(
                children: list.map((doc) {
                  final dd    = doc.data() as Map<String, dynamic>;
                  final plate = dd['plate']       as String? ?? doc.id;
                  final type  = dd['type']        as String? ?? '';
                  final avail = dd['available']   as bool?   ?? true;
                  final pName = dd['petugasName'] as String?;
                  final sel   = _selectedAmbulance.any((a) => a.id == doc.id);
 
                  final conflicts   = _conflictDetail[doc.id];
                  final hasConflict = conflicts != null && conflicts.isNotEmpty;
 
                  String rawVName = dd['vehicleName'] as String? ?? '';
                  if (rawVName.contains('·')) rawVName = rawVName.split('·').first.trim();
                  final vName = (rawVName.isEmpty || rawVName == plate) ? '' : rawVName;
 
                  Color typeColor = _blue;
                  IconData typeIcon = Icons.local_hospital_rounded;
                  if (type.contains('Gawat Darurat')) { typeColor = _red; typeIcon = Icons.emergency_rounded; }
                  else if (type.contains('Transport')) { typeColor = _blue; typeIcon = Icons.airport_shuttle_rounded; }
 
                  // ── Disabled card: armada sudah dikunci booking Disetujui lain ──
                  if (hasConflict) {
                    return _buildDisabledAmbCard(
                      plate: plate, type: type, typeIcon: typeIcon,
                      vName: vName, pName: pName, conflicts: conflicts!,
                    );
                  }
 
                  // ── Card normal: bisa dipilih ──
                  return GestureDetector(
                    onTap: () => _toggleAmbulance(doc),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: sel ? _blueLight : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: sel ? _blue : _border, width: sel ? 1.5 : 1),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5, offset: const Offset(0, 2))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: sel ? 0.20 : 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(typeIcon, color: typeColor, size: 20),
                          ),
                          const SizedBox(width: 11),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              vName.isNotEmpty ? vName : '— Nama belum diatur —',
                              style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13,
                                color: vName.isNotEmpty ? (sel ? _blue : _textPrimary) : _textMuted,
                                fontStyle: vName.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(5)),
                              child: Text(plate, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _textMuted)),
                            ),
                            const SizedBox(height: 4),
                            if (type.isNotEmpty)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(typeIcon, size: 10, color: typeColor),
                                const SizedBox(width: 3),
                                Text(type, style: TextStyle(fontSize: 10, color: typeColor, fontWeight: FontWeight.w500)),
                              ]),
                            if (pName != null && pName.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(children: [
                                Icon(Icons.medical_services_rounded, size: 10, color: _textMuted),
                                const SizedBox(width: 3),
                                Expanded(child: Text(pName, style: const TextStyle(fontSize: 10, color: _textMuted), overflow: TextOverflow.ellipsis)),
                              ]),
                            ],
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: (avail ? _green : Colors.grey).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(avail ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                    size: 10, color: avail ? _green : Colors.grey),
                                const SizedBox(width: 3),
                                Text(avail ? 'TERSEDIA' : 'SEDANG DIPAKAI',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                                        color: avail ? _green : Colors.grey)),
                              ]),
                            ),
                          ])),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: sel ? _blue : Colors.transparent,
                              border: Border.all(color: sel ? _blue : _border, width: 1.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: sel ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
 
          const SizedBox(height: 28),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan Perubahan',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            )),
        ],
      )),
    );
  }
 
  // ── [FIX 9] Disabled card petugas — badge selalu "Disetujui" karena
  //    hanya booking Disetujui yang bisa mengunci petugas ──────────────
  Widget _buildDisabledPetugasCard({
    required String name,
    required String faskes,
    required List<AmbulanceConflictInfo> conflicts,
  }) {
    final firstConflict = conflicts.first;
    final moreCount     = conflicts.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.medical_services_rounded,
                color: Colors.grey.shade400, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                const Icon(Icons.lock_rounded, size: 12, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.grey.shade400,
                    ),
                  ),
                ),
              ]),
              if (faskes.isNotEmpty) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(faskes,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500)),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _orangeLight,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: _orange.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_busy_rounded,
                      size: 11, color: _orange),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Bertugas: "${firstConflict.eventName}"'
                      '${moreCount > 0 ? ' +$moreCount lagi' : ''}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: _orange,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 5),
                  // [FIX 9] Badge selalu "Disetujui" karena hanya status itu yang mengunci
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Disetujui',
                      style: TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.lock_rounded,
                size: 13, color: Colors.grey.shade400),
          ),
        ]),
      ),
    );
  }
 
  // ── [FIX 9] Disabled card armada — badge selalu "Disetujui" karena
  //    hanya booking Disetujui yang bisa mengunci armada ───────────────
  Widget _buildDisabledAmbCard({
    required String plate,
    required String type,
    required IconData typeIcon,
    required String vName,
    required String? pName,
    required List<AmbulanceConflictInfo> conflicts,
  }) {
    final firstConflict = conflicts.first;
    final moreCount     = conflicts.length - 1;
 
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeIcon, color: Colors.grey.shade400, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.lock_rounded, size: 12, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(child: Text(
                vName.isNotEmpty ? vName : '— Nama belum diatur —',
                style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.grey.shade400,
                ),
              )),
            ]),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(5)),
              child: Text(plate, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
            ),
            if (type.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(typeIcon, size: 10, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(type, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
              ]),
            ],
            if (pName != null && pName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.medical_services_rounded, size: 10, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Expanded(child: Text(pName, style: TextStyle(fontSize: 10, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis)),
              ]),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _orangeLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.event_busy_rounded, size: 11, color: _orange),
                const SizedBox(width: 4),
                Flexible(child: Text(
                  'Terpakai: "${firstConflict.eventName}"'
                  '${moreCount > 0 ? ' +$moreCount lagi' : ''}',
                  style: const TextStyle(fontSize: 10, color: _orange, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                )),
                const SizedBox(width: 5),
                // [FIX 9] Badge selalu "Disetujui" karena hanya status itu yang mengunci
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Disetujui',
                    style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ])),
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.lock_rounded, size: 13, color: Colors.grey.shade400),
          ),
        ]),
      ),
    );
  }
 
  Widget _emptyHint(String msg) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, size: 15, color: _textMuted),
      const SizedBox(width: 8),
      Text(msg, style: const TextStyle(color: _textMuted, fontSize: 12)),
    ]),
  );
}
 
// ── Chip terpilih ──────────────────────────────────────────────────────
class _SelectedChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _SelectedChip({required this.label, required this.color, required this.onRemove});
 
  @override
  Widget build(BuildContext context) {
    final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight : _redLight;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.close, size: 11, color: color),
          ),
        ),
      ]),
    );
  }
}
 
// ─────────────── HELPERS ──────────────────────────────────────────────
Widget _sectionTitle(String t) =>
    Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _textPrimary));
 
Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
  final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight : _redLight;
  return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
    child: Container(padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 17, color: color)));
}
 
Future<bool?> _confirmDialog(BuildContext ctx, String title, String msg) =>
    showDialog<bool>(
      context: ctx, barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(msg, style: const TextStyle(color: _textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Batal', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Hapus')),
        ],
      ),
    );
 
// ═══════════════════════════ REKAP BULANAN TAB ════════════════════════
class _RekapBulananTab extends StatefulWidget {
  const _RekapBulananTab({super.key});
  @override State<_RekapBulananTab> createState() => _RekapBulananTabState();
}
 
class _RekapBulananTabState extends State<_RekapBulananTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
 
  late int _selectedYear;
  late int _selectedMonth;
  int _subTab = 0;
 
  final Stream<QuerySnapshot> _allBookingsStream =
      FirebaseFirestore.instance.collection('bookings').snapshots();
 
  static const _months = [
    'Januari','Februari','Maret','April','Mei','Juni',
    'Juli','Agustus','September','Oktober','November','Desember',
  ];
 
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear  = now.year;
    _selectedMonth = now.month;
  }
 
  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> all) {
    return all.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final ts   = data['createdAt'];
      if (ts == null) return false;
      final dt = (ts as Timestamp).toDate();
      return dt.year == _selectedYear && dt.month == _selectedMonth;
    }).toList();
  }
 
  Map<String, dynamic> _buildStats(List<QueryDocumentSnapshot> docs) {
    int total = docs.length;
    int menunggu = 0, disetujui = 0, ditolak = 0, selesai = 0;
    final Map<String, Map<String, dynamic>> perLokasi = {};
    final Map<String, int> perPetugas = {};
    final Map<String, int> perTipe    = {};
 
    final faskesList = _getFaskesList();
    final Map<String, Map<String, dynamic>> perFaskes = {};
    for (final f in faskesList) {
      perFaskes[f['name']!] = {'total': 0, 'selesai': 0, 'ditolak': 0, 'petugas': <String>{}};
    }
    perFaskes['Tidak Ditentukan'] = {'total': 0, 'selesai': 0, 'ditolak': 0, 'petugas': <String>{}};
 
    for (final doc in docs) {
      final d      = doc.data() as Map<String, dynamic>;
      final status = d['status'] as String? ?? '-';
      final lokasi = (d['location'] ?? d['eventLoc'] ?? 'Tidak diketahui') as String;
      final tipe   = (d['type'] ?? 'Lainnya') as String;
 
      if (status == 'Menunggu Konfirmasi') menunggu++;
      else if (status == 'Disetujui') disetujui++;
      else if (status == 'Ditolak')   ditolak++;
      else if (status == 'Selesai')   selesai++;
 
      final lokasiKey = lokasi.split(',').first.trim();
      if (!perLokasi.containsKey(lokasiKey)) {
        perLokasi[lokasiKey] = {'total': 0, 'selesai': 0, 'petugas': <String>{}};
      }
      perLokasi[lokasiKey]!['total'] = (perLokasi[lokasiKey]!['total'] as int) + 1;
      if (status == 'Selesai') {
        perLokasi[lokasiKey]!['selesai'] = (perLokasi[lokasiKey]!['selesai'] as int) + 1;
      }
      perTipe[tipe] = (perTipe[tipe] ?? 0) + 1;
 
      List<_AssignedPetugas> ptList = [];
      final rawPt = d['petugasList'];
      if (rawPt is List && rawPt.isNotEmpty) {
        ptList = rawPt.map((e) => _AssignedPetugas.fromMap(Map<String,dynamic>.from(e as Map))).toList();
      } else {
        final id   = d['petugasId']    as String?;
        final name = d['petugasName']  as String?;
        final fsk  = d['petugasFaskes'] as String?;
        if (id != null && id.isNotEmpty && name != null) {
          ptList = [_AssignedPetugas(id: id, name: name, faskes: fsk ?? '')];
        }
      }
 
      for (final pt in ptList) {
        if (status == 'Selesai') perPetugas[pt.name] = (perPetugas[pt.name] ?? 0) + 1;
        (perLokasi[lokasiKey]!['petugas'] as Set<String>).add(pt.name);
        final faskesKey = pt.faskes.isNotEmpty ? pt.faskes : 'Tidak Ditentukan';
        if (perFaskes.containsKey(faskesKey)) {
          perFaskes[faskesKey]!['total'] = (perFaskes[faskesKey]!['total'] as int) + 1;
          if (status == 'Selesai') perFaskes[faskesKey]!['selesai'] = (perFaskes[faskesKey]!['selesai'] as int) + 1;
          if (status == 'Ditolak') perFaskes[faskesKey]!['ditolak'] = (perFaskes[faskesKey]!['ditolak'] as int) + 1;
          (perFaskes[faskesKey]!['petugas'] as Set<String>).add(pt.name);
        }
      }
    }
 
    final sortedLokasi = perLokasi.entries.toList()
      ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
    final sortedPetugas = perPetugas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedFaskes = perFaskes.entries.toList()
      ..sort((a, b) {
        final diff = (b.value['total'] as int).compareTo(a.value['total'] as int);
        if (diff != 0) return diff;
        return a.key.compareTo(b.key);
      });
 
    return {
      'total': total, 'menunggu': menunggu, 'disetujui': disetujui,
      'ditolak': ditolak, 'selesai': selesai,
      'perLokasi':  sortedLokasi,
      'perPetugas': sortedPetugas,
      'perTipe':    perTipe,
      'perFaskes':  sortedFaskes,
    };
  }
 
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _allBookingsStream,
      builder: (ctx, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
        }
        final filtered = _filterDocs(snap.data?.docs ?? []);
        final stats    = _buildStats(filtered);
 
        return Column(children: [
          Container(
            color: Colors.white,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border)),
                  child: Row(children: [
                    const Icon(Icons.calendar_month_rounded, color: _red, size: 17),
                    const SizedBox(width: 8),
                    const Text('Periode:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _textPrimary)),
                    const SizedBox(width: 8),
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
                      child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                        value: _selectedMonth, isExpanded: true,
                        style: const TextStyle(fontSize: 12, color: _textPrimary),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: _textMuted),
                        items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i]))),
                        onChanged: (v) { if (v != null) setState(() => _selectedMonth = v); },
                      )),
                    )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
                      child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                        value: _selectedYear,
                        style: const TextStyle(fontSize: 12, color: _textPrimary),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: _textMuted),
                        items: List.generate(5, (i) {
                          final y = DateTime.now().year - 2 + i;
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }),
                        onChanged: (v) { if (v != null) setState(() => _selectedYear = v); },
                      )),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _border)),
                  child: Row(children: [
                    _subTabBtn(0, Icons.bar_chart_rounded, 'Umum'),
                    _subTabBtn(1, Icons.local_hospital_rounded, 'Per Faskes'),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(child: _subTab == 0 ? _buildUmum(stats) : _buildPerFaskes(stats)),
        ]);
      },
    );
  }
 
  Widget _subTabBtn(int idx, IconData icon, String label) {
    final sel = _subTab == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _subTab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(color: sel ? _red : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: sel ? Colors.white : _textMuted),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : _textMuted)),
        ]),
      ),
    ));
  }
 
  Widget _buildUmum(Map<String, dynamic> stats) {
    if (stats['total'] == 0) return _emptyRekap();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(11), border: Border.all(color: _red.withValues(alpha:0.2))),
          child: Row(children: [
            const Icon(Icons.bar_chart_rounded, color: _red, size: 17),
            const SizedBox(width: 8),
            Text('Rekap ${_months[_selectedMonth - 1]} $_selectedYear',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _red)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(20)),
              child: Text('${stats['total']} kegiatan',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 13),
        Row(children: [
          _statCard('Menunggu', stats['menunggu'], _orange, Icons.hourglass_top_rounded),
          const SizedBox(width: 7),
          _statCard('Disetujui', stats['disetujui'], _green, Icons.check_circle_rounded),
          const SizedBox(width: 7),
          _statCard('Selesai', stats['selesai'], _blue, Icons.verified_rounded),
          const SizedBox(width: 7),
          _statCard('Ditolak', stats['ditolak'], _red, Icons.cancel_rounded),
        ]),
        const SizedBox(height: 15),
        if ((stats['perTipe'] as Map).isNotEmpty) ...[
          _sectionHeader(Icons.category_rounded, 'Tipe Acara', _blue),
          const SizedBox(height: 8),
          _tipeCard(stats),
          const SizedBox(height: 15),
        ],
        if ((stats['perPetugas'] as List).isNotEmpty) ...[
          _sectionHeader(Icons.medical_services_rounded, 'Rekap Petugas (Tugas Selesai)', _orange),
          const SizedBox(height: 8),
          _petugasCard(stats),
          const SizedBox(height: 15),
        ],
        if ((stats['perLokasi'] as List).isNotEmpty) ...[
          _sectionHeader(Icons.location_on_rounded, 'Rekap Lokasi Event', _red),
          const SizedBox(height: 8),
          _lokasiCard(stats),
        ],
      ],
    );
  }
 
  Widget _buildPerFaskes(Map<String, dynamic> stats) {
    final faskesList    = stats['perFaskes'] as List<MapEntry<String, Map<String, dynamic>>>;
    final totalKegiatan = stats['total'] as int;
    final aktif  = faskesList.where((e) => (e.value['total'] as int) > 0).toList();
    final kosong = faskesList.where((e) => (e.value['total'] as int) == 0).toList();
 
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(11), border: Border.all(color: _blue.withValues(alpha:0.2))),
          child: Row(children: [
            const Icon(Icons.local_hospital_rounded, color: _blue, size: 17),
            const SizedBox(width: 8),
            Expanded(child: Text('Penugasan per Faskes — ${_months[_selectedMonth - 1]} $_selectedYear',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _blue))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(20)),
              child: Text('${aktif.length} faskes aktif',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 13),
        if (totalKegiatan == 0)
          _emptyRekap()
        else ...[
          Row(children: [
            _statCard('Faskes Aktif', aktif.length, _blue, Icons.local_hospital_rounded),
            const SizedBox(width: 7),
            _statCard('Kosong', kosong.length - 1, Colors.grey, Icons.radio_button_unchecked),
            const SizedBox(width: 7),
            _statCard('Total', totalKegiatan, _red, Icons.bar_chart_rounded),
          ]),
          const SizedBox(height: 15),
          if (aktif.isNotEmpty) ...[
            _sectionHeader(Icons.check_circle_rounded, 'Faskes dengan Penugasan (${aktif.length})', _green),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _border)),
              child: Column(children: aktif.asMap().entries.map((entry) {
                final i       = entry.key;
                final name    = entry.value.key;
                final data    = entry.value.value;
                final total   = data['total'] as int;
                final selesai = data['selesai'] as int;
                final ditolak = data['ditolak'] as int;
                final petugasSet = data['petugas'] as Set<String>;
                final pct    = totalKegiatan > 0 ? total / totalKegiatan : 0.0;
                final isLast = i == aktif.length - 1;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(9)),
                          child: Icon(name.startsWith('RSUD') ? Icons.local_hospital_rounded : name.startsWith('PSC') ? Icons.emergency_rounded : Icons.medical_services_rounded, size: 15, color: _blue)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
                          const SizedBox(height: 5),
                          Row(children: [
                            _miniChip('$total tugas', _blue),
                            const SizedBox(width: 5),
                            _miniChip('$selesai selesai', _green),
                            if (ditolak > 0) ...[const SizedBox(width: 5), _miniChip('$ditolak ditolak', _red)],
                          ]),
                        ])),
                      ]),
                      const SizedBox(height: 9),
                      ClipRRect(borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: pct, backgroundColor: _bg, color: _blue, minHeight: 5)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('${(pct * 100).toStringAsFixed(0)}% dari total bulan ini', style: const TextStyle(fontSize: 10, color: _textMuted)),
                        const Spacer(),
                        if (selesai > 0 && total > 0)
                          Text('${(selesai / total * 100).toStringAsFixed(0)}% success rate', style: const TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
                      ]),
                      if (petugasSet.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.person_outline_rounded, size: 12, color: _textMuted),
                          const SizedBox(width: 5),
                          Expanded(child: Text('Petugas: ${petugasSet.join(', ')}',
                              style: const TextStyle(fontSize: 11, color: _textMuted))),
                        ]),
                      ],
                    ]),
                  ),
                  if (!isLast) Divider(height: 1, indent: 13, endIndent: 13, color: _border),
                ]);
              }).toList()),
            ),
            const SizedBox(height: 15),
          ],
          if (kosong.length > 1) ...[
            _sectionHeader(Icons.radio_button_unchecked, 'Faskes Belum Ada Penugasan (${kosong.length - 1})', Colors.grey),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
              child: Column(children: kosong.where((e) => e.key != 'Tidak Ditentukan').toList().asMap().entries.map((entry) {
                final i    = entry.key;
                final name = entry.value.key;
                final list = kosong.where((e) => e.key != 'Tidak Ditentukan').toList();
                final isLast = i == list.length - 1;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    child: Row(children: [
                      Icon(name.startsWith('RSUD') ? Icons.local_hospital_outlined : name.startsWith('PSC') ? Icons.emergency_outlined : Icons.medical_services_outlined, size: 14, color: Colors.grey.shade300),
                      const SizedBox(width: 9),
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 12, color: _textMuted))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
                        child: Text('0 tugas', style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  if (!isLast) Divider(height: 1, indent: 13, endIndent: 13, color: _border),
                ]);
              }).toList()),
            ),
          ],
        ],
      ],
    );
  }

  Widget _emptyRekap() => Center(child: Padding(padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
        child: Icon(Icons.bar_chart_rounded, size: 44, color: Colors.grey.shade300)),
      const SizedBox(height: 14),
      Text('Belum ada kegiatan di\n${_months[_selectedMonth - 1]} $_selectedYear',
          style: const TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
    ]),
  ));
 
  Widget _tipeCard(Map<String, dynamic> stats) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
    child: Column(children: (stats['perTipe'] as Map<String, int>).entries.toList().asMap().entries.map((entry) {
      final isLast = entry.key == (stats['perTipe'] as Map).length - 1;
      final tipe   = entry.value.key;
      final count  = entry.value.value;
      final total  = stats['total'] as int;
      final pct    = total > 0 ? count / total : 0.0;
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(13, 11, 13, 11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_rounded, size: 13, color: _blue),
            const SizedBox(width: 6),
            Expanded(child: Text(tipe, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textPrimary))),
            Text('$count kegiatan', style: const TextStyle(fontSize: 12, color: _textMuted)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pct, backgroundColor: _bg, color: _blue, minHeight: 5)),
        ])),
        if (!isLast) Divider(height: 1, indent: 13, endIndent: 13, color: _border),
      ]);
    }).toList()),
  );
 
  Widget _petugasCard(Map<String, dynamic> stats) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
    child: Column(children: (stats['perPetugas'] as List<MapEntry<String, int>>).asMap().entries.map((entry) {
      final rank    = entry.key + 1;
      final nama    = entry.value.key;
      final selesai = entry.value.value;
      final isLast  = entry.key == (stats['perPetugas'] as List).length - 1;
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(13, 11, 13, 11), child: Row(children: [
          Container(width: 26, height: 26,
            decoration: BoxDecoration(color: rank <= 3 ? _orangeLight : _bg, shape: BoxShape.circle),
            child: Center(child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: rank <= 3 ? _orange : _textMuted)))),
          const SizedBox(width: 9),
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _orangeLight, shape: BoxShape.circle), child: const Icon(Icons.person_rounded, size: 13, color: _orange)),
          const SizedBox(width: 8),
          Expanded(child: Text(nama, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textPrimary))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: _greenLight, borderRadius: BorderRadius.circular(20)),
            child: Text('$selesai selesai', style: const TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600))),
        ])),
        if (!isLast) Divider(height: 1, indent: 13, endIndent: 13, color: _border),
      ]);
    }).toList()),
  );
 
  Widget _lokasiCard(Map<String, dynamic> stats) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
    child: Column(children: (stats['perLokasi'] as List<MapEntry<String, Map<String, dynamic>>>).asMap().entries.map((entry) {
      final i      = entry.key;
      final lokasi = entry.value.key;
      final data   = entry.value.value;
      final total  = data['total'] as int;
      final selesai = data['selesai'] as int;
      final petugasSet = data['petugas'] as Set<String>;
      final isLast = i == (stats['perLokasi'] as List).length - 1;
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(13, 11, 13, 11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.location_on_rounded, size: 13, color: _red)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lokasi, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
              const SizedBox(height: 2),
              Row(children: [_miniChip('$total kegiatan', _blue), const SizedBox(width: 5), _miniChip('$selesai selesai', _green)]),
            ])),
          ]),
          if (petugasSet.isNotEmpty) ...[
            const SizedBox(height: 7),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 29),
              const Icon(Icons.medical_services_rounded, size: 11, color: _textMuted),
              const SizedBox(width: 5),
              Expanded(child: Text('Petugas: ${petugasSet.join(', ')}', style: const TextStyle(fontSize: 11, color: _textMuted))),
            ]),
          ],
        ])),
        if (!isLast) Divider(height: 1, indent: 13, endIndent: 13, color: _border),
      ]);
    }).toList()),
  );
 
  Widget _statCard(String label, int count, Color color, IconData icon) {
    final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight
        : color == _orange ? _orangeLight : color == _red ? _redLight : _bg;
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 7),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), child: Icon(icon, size: 16, color: color)),
        const SizedBox(height: 5),
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: _textMuted), textAlign: TextAlign.center),
      ]),
    ));
  }
 
  Widget _sectionHeader(IconData icon, String title, Color color) {
    final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight
        : color == _orange ? _orangeLight : color == _red ? _redLight : _bg;
    return Row(children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(7)), child: Icon(icon, size: 14, color: color)),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
    ]);
  }
 
  Widget _miniChip(String label, Color color) {
    final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight
        : color == _orange ? _orangeLight : _redLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
 
// ═══════════════════════════ ADMIN USER SCREEN ════════════════════════
class AdminUserScreen extends StatefulWidget {
  final VoidCallback onBack;
  const AdminUserScreen({super.key, required this.onBack});
  @override State<AdminUserScreen> createState() => _AdminUserScreenState();
}
 
class _AdminUserScreenState extends State<AdminUserScreen> {
  final _fs = FirestoreService();
  late final Stream<List<Map<String,dynamic>>> _stream;
 
  @override
  void initState() { super.initState(); _stream = _fs.getUsers(); }
 
  void _showCreateSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _CreateUserSheet(parentContext: context));
  }
 
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) widget.onBack(); },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Kelola User', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: _textPrimary)),
          backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: _textPrimary),
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: widget.onBack),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(onPressed: _showCreateSheet,
                icon: const Icon(Icons.person_add_rounded, color: _red, size: 17),
                label: const Text('Tambah', style: TextStyle(color: _red, fontWeight: FontWeight.w600)))),
          ],
        ),
        body: StreamBuilder<List<Map<String,dynamic>>>(
          stream: _stream,
          builder: (ctx, snap) {
            if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
            }
            final users = snap.data ?? [];
            if (users.isEmpty) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 12)]),
                  child: Icon(Icons.people_outline, size: 44, color: Colors.grey.shade300)),
                const SizedBox(height: 14),
                Text('Belum ada user', style: TextStyle(color: _textMuted, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _showCreateSheet,
                  icon: const Icon(Icons.person_add_rounded, size: 15),
                  label: const Text('Tambah User', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
              ]));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16,16,16,100),
              itemCount: users.length,
              itemBuilder: (_, i) => _UserCard(key: ValueKey(users[i]['id']), user: users[i], fs: _fs),
            );
          },
        ),
      ),
    );
  }
}
 
// ─────────────── CREATE USER SHEET ────────────────────────────────────
class _CreateUserSheet extends StatefulWidget {
  final BuildContext parentContext;
  const _CreateUserSheet({required this.parentContext});
  @override State<_CreateUserSheet> createState() => _CreateUserSheetState();
}
 
class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _auth     = AuthService();
  final _nameCtrl = TextEditingController();
  final _emailCtrl= TextEditingController();
  final _passCtrl = TextEditingController();
  String  _role   = 'user';
  String? _faskesId, _faskesName;
  bool    _saving  = false, _obscure = true;
  String? _errorMsg;
  final _faskesList = _getFaskesList();
 
  static const _roles      = ['user', 'petugas', 'admin'];
  static const _roleColors = {'user': _blue, 'petugas': _orange, 'admin': _red};
  static const _roleIcons  = {
    'user': Icons.person_rounded,
    'petugas': Icons.medical_services_rounded,
    'admin': Icons.shield_rounded
  };
 
  @override void dispose() { _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }
 
  Future<void> _save() async {
    setState(() => _errorMsg = null);
    final name = _nameCtrl.text.trim(), email = _emailCtrl.text.trim(), pass = _passCtrl.text;
    if (name.isEmpty)    { setState(() => _errorMsg = 'Nama lengkap wajib diisi.'); return; }
    if (email.isEmpty)   { setState(() => _errorMsg = 'Email wajib diisi.'); return; }
    if (pass.length < 6) { setState(() => _errorMsg = 'Password minimal 6 karakter.'); return; }
    if (_role == 'petugas' && _faskesId == null) { setState(() => _errorMsg = 'Pilih faskes untuk petugas.'); return; }
    setState(() => _saving = true);
    final result = await _auth.adminCreateUser(name: name, email: email, password: pass, role: _role, faskesId: _faskesId, faskesName: _faskesName);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isSuccess) {
      final pCtx = widget.parentContext;
      Navigator.pop(context);
      if (pCtx.mounted) ScaffoldMessenger.of(pCtx).showSnackBar(SnackBar(
        content: Text('User "${result.user!.name}" berhasil dibuat'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
    } else {
      setState(() => _errorMsg = result.errorMessage);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12,0,12,12),
        padding: EdgeInsets.fromLTRB(20,20,20,20+pad),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.10), blurRadius: 24)]),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Row(children: [
            Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.person_add_rounded, color: _red, size: 22)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tambah User Baru', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: _textPrimary)),
              Text('Buat akun untuk pengguna', style: TextStyle(color: _textMuted, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 20),
          if (_errorMsg != null) ...[
            Container(padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: _red.withValues(alpha:0.3))),
              child: Row(children: [const Icon(Icons.error_outline_rounded, color: _red, size: 15), const SizedBox(width: 8), Expanded(child: Text(_errorMsg!, style: const TextStyle(color: _red, fontSize: 12)))])),
            const SizedBox(height: 13),
          ],
          _sectionTitle('Nama Lengkap'), const SizedBox(height: 8),
          _TF(ctrl: _nameCtrl, label: 'Nama Lengkap', icon: Icons.person_outline_rounded),
          const SizedBox(height: 13),
          _sectionTitle('Email'), const SizedBox(height: 8),
          _TF(ctrl: _emailCtrl, label: 'Email', icon: Icons.mail_outline_rounded),
          const SizedBox(height: 13),
          _sectionTitle('Password'), const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _border)),
            child: TextField(controller: _passCtrl, obscureText: _obscure, style: const TextStyle(fontSize: 14, color: _textPrimary),
              decoration: InputDecoration(
                labelText: 'Password (min. 6 karakter)',
                labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 16, color: _textMuted),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 17, color: _textMuted), onPressed: () => setState(() => _obscure = !_obscure)),
                border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Role'), const SizedBox(height: 10),
          Row(children: _roles.map((r) {
            final sel = _role == r; final color = _roleColors[r]!; final icon = _roleIcons[r]!;
            final bgColor = color == _green ? _greenLight : color == _blue ? _blueLight
                : color == _orange ? _orangeLight : _redLight;
            return Expanded(child: Padding(
              padding: EdgeInsets.only(right: r != _roles.last ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() { _role = r; if (r != 'petugas') { _faskesId = null; _faskesName = null; } }),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: sel ? color : bgColor, borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? color : Colors.transparent)),
                  child: Column(children: [Icon(icon, size: 19, color: sel ? Colors.white : color), const SizedBox(height: 4), Text(r.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : color))])),
              )));
          }).toList()),
          if (_role == 'petugas') ...[
            const SizedBox(height: 15),
            _sectionTitle('Faskes Asal Petugas *'), const SizedBox(height: 4),
            Text('Pilih Puskesmas, RSUD, atau PSC.', style: const TextStyle(fontSize: 11, color: _textMuted)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _faskesId == null ? _orange : _border)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _faskesId, isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted),
                hint: Row(children: [const Icon(Icons.local_hospital_rounded, size: 14, color: _textMuted), const SizedBox(width: 7), Text('Pilih Faskes', style: const TextStyle(color: _textMuted, fontSize: 13))]),
                items: _faskesList.map((f) => DropdownMenuItem(value: f['id'], child: Text(f['name']!, style: const TextStyle(fontSize: 13, color: _textPrimary)))).toList(),
                onChanged: (v) => setState(() { _faskesId = v; _faskesName = _faskesList.firstWhere((f) => f['id'] == v, orElse: () => {'name': ''})['name']; }),
                style: const TextStyle(color: _textPrimary, fontSize: 13),
              )),
            ),
            if (_faskesName != null && _faskesName!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(color: _greenLight, borderRadius: BorderRadius.circular(9), border: Border.all(color: _green.withValues(alpha:0.3))),
                child: Row(children: [const Icon(Icons.check_circle_rounded, size: 13, color: _green), const SizedBox(width: 7), Expanded(child: Text(_faskesName!, style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)))])),
            ],
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Buat Akun', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          )),
        ])),
      ),
    );
  }
}
 
class _UserCard extends StatelessWidget {
  final Map<String,dynamic> user;
  final FirestoreService fs;
  const _UserCard({required super.key, required this.user, required this.fs});
 
  Color _rc(String r) { switch(r) { case 'admin': return _red; case 'petugas': return _orange; default: return _blue; } }
  Color _rbg(String r) { switch(r) { case 'admin': return _redLight; case 'petugas': return _orangeLight; default: return _blueLight; } }
  IconData _ri(String r) { switch(r) { case 'admin': return Icons.shield_rounded; case 'petugas': return Icons.medical_services_rounded; default: return Icons.person_rounded; } }
 
  @override
  Widget build(BuildContext context) {
    final role  = user['role'] as String? ?? 'user';
    final name  = user['name'] as String? ?? '-';
    final email = user['email'] as String? ?? '-';
    final faskes= user['faskesName'] as String? ?? '';
    final color = _rc(role);
    final bgColor = _rbg(role);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.03), blurRadius: 6, offset: const Offset(0,2))]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(radius: 22, backgroundColor: bgColor,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16))),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _textPrimary)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 2),
          Text(email, style: const TextStyle(color: _textMuted, fontSize: 11)),
          const SizedBox(height: 5),
          Wrap(spacing: 5, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_ri(role), size: 10, color: color), const SizedBox(width: 3), Text(role.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color))])),
            if (role == 'petugas' && faskes.isNotEmpty)
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.local_hospital_rounded, size: 9, color: _blue), const SizedBox(width: 3), Text(faskes.split(' ').take(2).join(' '), style: const TextStyle(fontSize: 9, color: _blue, fontWeight: FontWeight.w500))])),
          ]),
        ]),
        trailing: _iconBtn(Icons.edit_rounded, _blue, () {
          final pCtx = context;
          showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
            builder: (_) => _EditUserSheet(user: user, fs: fs, parentContext: pCtx));
        }),
      ),
    );
  }
}
 
// ─────────────── EDIT USER SHEET ──────────────────────────────────────
class _EditUserSheet extends StatefulWidget {
  final Map<String,dynamic> user;
  final FirestoreService fs;
  final BuildContext parentContext;
  const _EditUserSheet({required this.user, required this.fs, required this.parentContext});
  @override State<_EditUserSheet> createState() => _EditUserSheetState();
}
 
class _EditUserSheetState extends State<_EditUserSheet> {
  late String _role;
  String? _faskesId, _faskesName;
  bool _saving = false;
  final _faskesList = _getFaskesList();
 
  @override
  void initState() {
    super.initState();
    _role = widget.user['role'] ?? 'user';
    _faskesId = widget.user['faskesId'];
    _faskesName = widget.user['faskesName'];
  }
 
  Future<void> _save() async {
    if (_role == 'petugas' && _faskesId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Pilih faskes untuk petugas!'),
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
      return;
    }
    setState(() => _saving = true);
    await widget.fs.updateUser(widget.user['id'], {'role': _role, 'faskesId': _role == 'petugas' ? _faskesId : null, 'faskesName': _role == 'petugas' ? _faskesName : null});
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ${widget.user['name']} diperbarui'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
    }
  }
 
  Future<void> _delete() async {
    final pCtx = widget.parentContext;
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!pCtx.mounted) return;
    final ok = await _confirmDialog(pCtx, 'Hapus User?', 'User "${widget.user['name']}" akan dihapus permanen.');
    if (ok == true) await widget.fs.deleteUser(widget.user['id']);
  }
 
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    const roles = ['user','petugas','admin'];
    final rColors = {'user': _blue, 'petugas': _orange, 'admin': _red};
    final rBgColors = {'user': _blueLight, 'petugas': _orangeLight, 'admin': _redLight};
    final rIcons  = {'user': Icons.person_rounded, 'petugas': Icons.medical_services_rounded, 'admin': Icons.shield_rounded};
    return Container(
      margin: const EdgeInsets.fromLTRB(12,0,12,12),
      padding: EdgeInsets.fromLTRB(20,20,20,20+pad),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.10), blurRadius: 24)]),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Row(children: [
          CircleAvatar(radius: 21, backgroundColor: _redLight, child: Text((widget.user['name']??'?')[0].toUpperCase(), style: const TextStyle(color: _red, fontWeight: FontWeight.w700, fontSize: 17))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.user['name']??'-', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _textPrimary)), Text(widget.user['email']??'-', style: const TextStyle(color: _textMuted, fontSize: 12))])),
          _iconBtn(Icons.delete_outline_rounded, _red, _delete),
        ]),
        const SizedBox(height: 22),
        Align(alignment: Alignment.centerLeft, child: _sectionTitle('Ubah Role')), const SizedBox(height: 10),
        Row(children: roles.map((r) {
          final sel = _role == r; final color = rColors[r]!; final bgColor = rBgColors[r]!; final icon = rIcons[r]!;
          return Expanded(child: Padding(
            padding: EdgeInsets.only(right: r != roles.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() { _role = r; if (r != 'petugas') { _faskesId = null; _faskesName = null; } }),
              child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: sel ? color : bgColor, borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? color : Colors.transparent)),
                child: Column(children: [Icon(icon, size: 19, color: sel ? Colors.white : color), const SizedBox(height: 4), Text(r.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : color))]))),
          ));
        }).toList()),
        if (_role == 'petugas') ...[
          const SizedBox(height: 17),
          Align(alignment: Alignment.centerLeft, child: _sectionTitle('Faskes Asal Petugas')), const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _border)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _faskesId, isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted),
              hint: Row(children: [const Icon(Icons.local_hospital_rounded, size: 14, color: _textMuted), const SizedBox(width: 7), const Text('Pilih Faskes', style: TextStyle(color: _textMuted, fontSize: 13))]),
              items: _faskesList.map((f) => DropdownMenuItem(value: f['id'], child: Text(f['name']!, style: const TextStyle(fontSize: 13, color: _textPrimary)))).toList(),
              onChanged: (v) => setState(() { _faskesId = v; _faskesName = _faskesList.firstWhere((f) => f['id'] == v, orElse: () => {'name': ''})['name']; }),
              style: const TextStyle(color: _textPrimary, fontSize: 13),
            )),
          ),
          if (_faskesName != null && _faskesName!.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), decoration: BoxDecoration(color: _greenLight, borderRadius: BorderRadius.circular(9), border: Border.all(color: _green.withValues(alpha:0.3))),
              child: Row(children: [const Icon(Icons.check_circle_rounded, size: 13, color: _green), const SizedBox(width: 7), Expanded(child: Text(_faskesName!, style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)))])),
          ],
        ],
        const SizedBox(height: 22),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        )),
      ])),
    );
  }
}
 
// ═══════════════════════════ ADMIN AMBULANCE SCREEN ═══════════════════════════
class AdminAmbulanceScreen extends StatefulWidget {
  final VoidCallback onBack;
  const AdminAmbulanceScreen({super.key, required this.onBack});
  @override State<AdminAmbulanceScreen> createState() => _AdminAmbState();
}
 
class _AdminAmbState extends State<AdminAmbulanceScreen> {
  final _fs = FirestoreService();
  late final Stream<List<Map<String,dynamic>>> _stream;
 
  @override
  void initState() { super.initState(); _stream = _fs.getAmbulances(); }
 
  void _showSheet({Map<String,dynamic>? existing}) {
    final pCtx = context;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AmbSheet(existing: existing, fs: _fs, parentContext: pCtx));
  }
 
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) widget.onBack(); },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Kelola Armada', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: _textPrimary)),
          backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: _textPrimary),
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: widget.onBack),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(onPressed: () => _showSheet(),
                icon: const Icon(Icons.add_rounded, color: _red, size: 17),
                label: const Text('Tambah', style: TextStyle(color: _red, fontWeight: FontWeight.w600)))),
          ],
        ),
        body: StreamBuilder<List<Map<String,dynamic>>>(
          stream: _stream,
          builder: (ctx, snap) {
            if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2));
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 12)]), child: Icon(Icons.local_hospital_outlined, size: 44, color: Colors.grey.shade300)),
                const SizedBox(height: 14),
                Text('Belum ada armada', style: TextStyle(color: _textMuted, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: () => _showSheet(), icon: const Icon(Icons.add_rounded, size: 15), label: const Text('Tambah Armada', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
              ]));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16,16,16,100),
              itemCount: list.length,
              itemBuilder: (_, i) => _AmbCard(key: ValueKey(list[i]['id']), amb: list[i], fs: _fs, onEdit: () => _showSheet(existing: list[i])));
          },
        ),
      ),
    );
  }
}
 
// ═══════════════════════════ AMB SHEET ════════════════════════════════
class _AmbSheet extends StatefulWidget {
  final Map<String,dynamic>? existing;
  final FirestoreService fs;
  final BuildContext parentContext;
  const _AmbSheet({this.existing, required this.fs, required this.parentContext});
  @override State<_AmbSheet> createState() => _AmbSheetState();
}
 
class _AmbSheetState extends State<_AmbSheet> {
  late final TextEditingController _plateCtrl;
  String? _selectedVehicleType;
  int?    _selectedVehicleIndex;
  String? _petugasId, _petugasName;
  bool _saving = false;
  late final Stream<QuerySnapshot> _petugasStream;
  bool get _isEdit => widget.existing != null;
 
  String get _selectedVehicleName {
    if (_selectedVehicleIndex == null) return '';
    return _vehicleNames[_selectedVehicleIndex!]['label'] as String;
  }
 
  String get _selectedVehicleKey {
    if (_selectedVehicleIndex == null) return '';
    return _vehicleNames[_selectedVehicleIndex!]['key'] as String;
  }
 
  @override
  void initState() {
    super.initState();
    _plateCtrl = TextEditingController(text: widget.existing?['plate'] ?? '');
    _selectedVehicleType = widget.existing?['type'] as String?;
 
    final savedKey  = widget.existing?['vehicleKey']  as String?;
    final savedName = widget.existing?['vehicleName'] as String?;
 
    if (savedKey != null && savedKey.isNotEmpty) {
      final idx = _vehicleNames.indexWhere((v) => (v['key'] as String) == savedKey);
      _selectedVehicleIndex = idx >= 0 ? idx : null;
    } else if (savedName != null && savedName.isNotEmpty) {
      String cleanName = savedName.contains('·') ? savedName.split('·').first.trim() : savedName;
      final idx = _vehicleNames.indexWhere((v) => (v['label'] as String) == cleanName);
      _selectedVehicleIndex = idx >= 0 ? idx : null;
    } else {
      _selectedVehicleIndex = null;
    }
 
    _petugasId   = widget.existing?['petugasId'];
    _petugasName = widget.existing?['petugasName'];
    _petugasStream = FirebaseFirestore.instance
        .collection('users').where('role', isEqualTo: 'petugas').snapshots();
  }
 
  @override void dispose() { _plateCtrl.dispose(); super.dispose(); }
 
  Future<void> _save() async {
    if (_plateCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Nomor plat wajib diisi!'),
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
      return;
    }
    setState(() => _saving = true);
 
    if (_isEdit) {
      final data = {
        'plate':       _plateCtrl.text.trim(),
        'type':        _selectedVehicleType ?? '',
        'vehicleName': _selectedVehicleName,
        'vehicleKey':  _selectedVehicleKey,
        'petugasId':   _petugasId,
        'petugasName': _petugasName,
      };
      await widget.fs.updateAmbulance(widget.existing!['id'], data);
      try {
        await widget.fs.recalculateAmbulanceAvailability(widget.existing!['id']);
        print('[AmbSheet] Recalculate setelah edit: ${widget.existing!['id']}');
      } catch (e) {
        print('[AmbSheet] Recalculate error: $e');
      }
    } else {
      final data = {
        'plate':       _plateCtrl.text.trim(),
        'type':        _selectedVehicleType ?? '',
        'vehicleName': _selectedVehicleName,
        'vehicleKey':  _selectedVehicleKey,
        'petugasId':   _petugasId,
        'petugasName': _petugasName,
        'available':   true,
      };
      await widget.fs.addAmbulance(data);
    }
 
    if (mounted) Navigator.pop(context);
  }
 
  Future<void> _delete() async {
    final pCtx = widget.parentContext;
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!pCtx.mounted) return;
    final ok = await _confirmDialog(pCtx, 'Hapus Armada?', 'Armada "${widget.existing!['plate']}" akan dihapus permanen.');
    if (ok == true) await widget.fs.deleteAmbulance(widget.existing!['id']);
  }
 
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12,0,12,12),
        padding: EdgeInsets.fromLTRB(20,20,20,20+pad),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.10), blurRadius: 24)]),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Row(children: [
            Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: _redLight, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.local_hospital_rounded, color: _red, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_isEdit ? 'Edit Armada' : 'Tambah Armada', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: _textPrimary)),
              if (_isEdit) Text(widget.existing!['plate'] ?? '', style: const TextStyle(color: _textMuted, fontSize: 13)),
            ])),
            if (_isEdit) _iconBtn(Icons.delete_outline_rounded, _red, _delete),
          ]),
 
          if (_isEdit) ...[
            const SizedBox(height: 12),
            Builder(builder: (ctx) {
              final avail = widget.existing!['available'] as bool? ?? true;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: avail ? _greenLight : _redLight,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: (avail ? _green : _red).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(avail ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 14, color: avail ? _green : _red),
                  const SizedBox(width: 7),
                  Expanded(child: Text(
                    avail
                        ? 'Status: Tersedia — diperbarui otomatis dari booking aktif'
                        : 'Status: Sedang dipakai — diperbarui otomatis setelah booking selesai',
                    style: TextStyle(fontSize: 11, color: avail ? _green : _red, fontWeight: FontWeight.w500),
                  )),
                ]),
              );
            }),
          ],
          const SizedBox(height: 20),
 
          _sectionTitle('Nomor Plat *'), const SizedBox(height: 8),
          _TF(ctrl: _plateCtrl, label: 'Contoh: AG 1234 XX', icon: Icons.directions_car_rounded),
          const SizedBox(height: 17),
 
          Row(children: [
            _sectionTitle('Tipe Kendaraan'),
            const Spacer(),
            if (_selectedVehicleType != null)
              GestureDetector(onTap: () => setState(() => _selectedVehicleType = null),
                child: const Text('Reset', style: TextStyle(fontSize: 11, color: _red, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 9),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1, mainAxisSpacing: 7, childAspectRatio: 5.5),
            itemCount: _vehicleTypes.length,
            itemBuilder: (ctx, i) {
              final vt = _vehicleTypes[i];
              final label = vt['label'] as String;
              final icon  = vt['icon']  as IconData;
              final color = vt['color'] as Color;
              final sel   = _selectedVehicleType == label;
              final bgColor = color == _red ? _redLight : _blueLight;
              return GestureDetector(
                onTap: () => setState(() => _selectedVehicleType = label),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? color : bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? color : Colors.transparent)),
                  child: Row(children: [
                    Icon(icon, size: 15, color: sel ? Colors.white : color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? Colors.white : color), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              );
            },
          ),
          if (_selectedVehicleType != null) ...[
            const SizedBox(height: 7),
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(color: _greenLight, borderRadius: BorderRadius.circular(9), border: Border.all(color: _green.withValues(alpha:0.3))),
              child: Row(children: [const Icon(Icons.check_circle_rounded, size: 13, color: _green), const SizedBox(width: 7), Expanded(child: Text(_selectedVehicleType!, style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)))])),
          ],
          const SizedBox(height: 17),
 
          Row(children: [
            _sectionTitle('Nama Kendaraan'),
            const Spacer(),
            if (_selectedVehicleIndex != null)
              GestureDetector(onTap: () => setState(() => _selectedVehicleIndex = null),
                child: const Text('Reset', style: TextStyle(fontSize: 11, color: _red, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 9),
          ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: _vehicleNames.length,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (ctx, i) {
              final vn    = _vehicleNames[i];
              final label = vn['label'] as String;
              final icon  = vn['icon']  as IconData;
              final color = vn['color'] as Color;
              final sel   = _selectedVehicleIndex == i;
              final bgColor = color == _red ? _redLight : color == _blue ? _blueLight
                  : color == _green ? _greenLight : _orangeLight;
              return GestureDetector(
                onTap: () => setState(() => _selectedVehicleIndex = i),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: sel ? color : bgColor,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: sel ? color : Colors.transparent)),
                  child: Row(children: [
                    Container(padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: sel ? Colors.white.withValues(alpha:0.22) : color.withValues(alpha:0.15), shape: BoxShape.circle),
                      child: Icon(icon, size: 15, color: sel ? Colors.white : color)),
                    const SizedBox(width: 11),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? Colors.white : _textPrimary))),
                    if (sel) const Icon(Icons.check_circle_rounded, size: 17, color: Colors.white),
                  ]),
                ),
              );
            },
          ),
          if (_selectedVehicleIndex != null) ...[
            const SizedBox(height: 7),
            Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(9), border: Border.all(color: _blue.withValues(alpha:0.3))),
              child: Row(children: [const Icon(Icons.directions_car_rounded, size: 13, color: _blue), const SizedBox(width: 7), Expanded(child: Text(_selectedVehicleName, style: const TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w600)))])),
          ],
          const SizedBox(height: 17),
          _sectionTitle('Petugas'), const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: _petugasStream,
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: SizedBox(height: 34, child: CircularProgressIndicator(strokeWidth: 2, color: _red)));
              final docs = snap.data!.docs;
              if (docs.isEmpty) return Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: _orangeLight, borderRadius: BorderRadius.circular(9)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: _orange, size: 15),
                  const SizedBox(width: 7),
                  Text('Belum ada user petugas', style: const TextStyle(color: _orange, fontSize: 13))]));
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: _petugasId,
                  hint: const Text('Pilih Petugas', style: TextStyle(color: _textMuted, fontSize: 13)),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted),
                  onChanged: (val) {
                    if (val == null) return;
                    final doc  = docs.firstWhere((d) => d.id == val);
                    final data = doc.data() as Map<String,dynamic>;
                    setState(() { _petugasId = val; _petugasName = data['name'] ?? val; });
                  },
                  items: docs.map((d) {
                    final data   = d.data() as Map<String,dynamic>;
                    final faskes = data['faskesName'] ?? '';
                    return DropdownMenuItem<String>(
                      value: d.id,
                      child: Text(
                        faskes.isNotEmpty ? '${data['name']} · $faskes' : '${data['name']}',
                        style: const TextStyle(fontSize: 13, color: _textPrimary)));
                  }).toList(),
                )),
              );
            },
          ),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Armada',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          )),
        ])),
      ),
    );
  }
}
 
// ═══════════════════════════ AMB CARD ═════════════════════════════════
class _AmbCard extends StatelessWidget {
  final Map<String,dynamic> amb;
  final FirestoreService fs;
  final VoidCallback onEdit;
  const _AmbCard({required super.key, required this.amb, required this.fs, required this.onEdit});
 
  IconData _vehicleIcon(String? type) {
    if (type == null || type.isEmpty) return Icons.local_hospital_rounded;
    if (type.contains('Gawat Darurat')) return Icons.emergency_rounded;
    if (type.contains('Transport'))    return Icons.airport_shuttle_rounded;
    return Icons.local_hospital_rounded;
  }
 
  Color _vehicleColor(String? type) {
    if (type == null || type.isEmpty) return _blue;
    final match = _vehicleTypes.firstWhere((vt) => (vt['label'] as String) == type, orElse: () => {'color': _blue});
    return match['color'] as Color;
  }
 
  @override
  Widget build(BuildContext context) {
    final available   = amb['available']   as bool?   ?? true;
    final plate       = amb['plate']       as String? ?? '-';
    final type        = amb['type']        as String? ?? '';
    final vehicleName = amb['vehicleName'] as String? ?? '';
    final petugasName = amb['petugasName'] as String?;
    final availColor  = available ? _green : _red;
    final availBg     = available ? _greenLight : _redLight;
    final typeColor   = _vehicleColor(type.isNotEmpty ? type : null);
    final typeBg      = typeColor == _red ? _redLight : _blueLight;
 
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.03), blurRadius: 6, offset: const Offset(0,2))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(11)),
            child: Icon(_vehicleIcon(type.isNotEmpty ? type : null), color: typeColor, size: 22)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plate, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _textPrimary)),
            const SizedBox(height: 4),
            if (vehicleName.isNotEmpty)
              Container(margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.directions_car_rounded, size: 10, color: _blue),
                  const SizedBox(width: 3),
                  Flexible(child: Text(vehicleName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _blue), overflow: TextOverflow.ellipsis)),
                ]))
            else
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text('Nama kendaraan belum diatur', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic))),
            if (type.isNotEmpty)
              Container(margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_vehicleIcon(type), size: 10, color: typeColor),
                  const SizedBox(width: 3),
                  Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: typeColor)),
                ]))
            else
              Padding(padding: const EdgeInsets.only(bottom: 5),
                child: Text('Tipe belum diatur', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic))),
            Row(children: [
              Icon(Icons.medical_services_rounded, size: 10, color: _textMuted),
              const SizedBox(width: 3),
              Expanded(child: Text(
                petugasName ?? 'Belum ada petugas',
                style: TextStyle(fontSize: 11, color: petugasName != null ? _textMuted : Colors.grey.shade400, fontStyle: petugasName != null ? FontStyle.normal : FontStyle.italic),
                overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: availBg, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(available ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 11, color: availColor),
                  const SizedBox(width: 4),
                  Text(available ? 'TERSEDIA' : 'SEDANG DIPAKAI',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: availColor)),
                ])),
              const SizedBox(width: 6),
              Text('(otomatis)', style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ]),
          ])),
          _iconBtn(Icons.edit_rounded, _blue, onEdit),
        ]),
      ),
    );
  }
}
 
// ─────────────── REUSABLE TEXT FIELD ──────────────────────────────────
class _TF extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  const _TF({required this.ctrl, required this.label, required this.icon});
 
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _border)),
    child: TextField(controller: ctrl, style: const TextStyle(fontSize: 14, color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
        prefixIcon: Icon(icon, size: 16, color: _textMuted),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
  );
}