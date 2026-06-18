// ══════════════════════════════════════════════════════════════════════
// PATCH: petugas_screen.dart
// Masalah: Stream query hanya filter dengan petugasId (format lama).
//          Format baru menyimpan array petugasList, sehingga Firestore
//          query where('petugasId') tidak bisa menangkapnya.
//
// Solusi: Gunakan StreamBuilder dengan 2 stream digabung (merge), atau
//         fetch semua booking milik user lalu filter di client-side.
//         Karena Firestore tidak support OR query lintas field dengan array,
//         solusi paling bersih adalah client-side filtering.
// ══════════════════════════════════════════════════════════════════════

// ─── GANTI di class PetugasTugasScreen ────────────────────────────────
// Cari method build() di PetugasTugasScreen
// Ganti stream dari:
//   final stream = FirebaseFirestore.instance
//       .collection('bookings')
//       .where('petugasId', isEqualTo: petugasUser.uid)
//       .snapshots();
//
// Menjadi stream yang cover kedua format, dengan StreamBuilder di bawah:

// ─── PASTE ini sebagai seluruh class PetugasTugasScreen ───────────────

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
    // Format lama: petugasId (single string)
    final oldId = data['petugasId'] as String?;
    if (oldId != null && oldId == myUid) return true;

    // Format baru: petugasList (array of map)
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
    // Gunakan stream semua booking — filter di client karena Firestore
    // tidak bisa OR query antara petugasId dan petugasList[].id
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

              // Filter di client-side: ambil hanya booking milik petugas ini
              final allDocs = snapshot.data?.docs ?? [];
              final myDocs  = allDocs.where((doc) {
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

              // Sort: Disetujui → Menunggu → lainnya, terbaru duluan
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

// ─── Di PetugasPetaScreen — juga fix stream untuk tab Peta ────────────
// Cari stream di dalam build() di _PetugasPetaScreenState:
//   stream: FirebaseFirestore.instance
//       .collection('bookings')
//       .where('petugasId', isEqualTo: widget.petugasUser.uid)
//       .where('status', isEqualTo: 'Disetujui')
//       .snapshots(),
//
// Ganti dengan stream ALL + filter client-side.
// Paste seluruh body StreamBuilder-nya di bawah:

// Di dalam body: Stack(children: [...]),
// Ganti StreamBuilder stream= menjadi:
//   stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
// Dan tambahkan filter sebelum memproses docs:
//   final docs = snap.data?.docs.where((doc) {
//     final d = doc.data() as Map<String, dynamic>;
//     if (d['status'] != 'Disetujui') return false;
//     // Format lama
//     final oldId = d['petugasId'] as String?;
//     if (oldId == widget.petugasUser.uid) return true;
//     // Format baru
//     final list = d['petugasList'];
//     if (list is List) {
//       for (final item in list) {
//         if (item is Map && item['id'] == widget.petugasUser.uid) return true;
//       }
//     }
//     return false;
//   }).toList() ?? [];

// ─── Di PetugasProfilScreen — fix stats count ─────────────────────────
// Cari stream di dalam build() di PetugasProfilScreen:
//   stream: FirebaseFirestore.instance
//       .collection('bookings')
//       .where('petugasId', isEqualTo: petugasUser.uid)
//       .snapshots(),
//
// Ganti dengan stream ALL, lalu filter:
//   final myDocs = docs.where((d) {
//     final data = d.data() as Map<String, dynamic>;
//     final oldId = data['petugasId'] as String?;
//     if (oldId == petugasUser.uid) return true;
//     final list = data['petugasList'];
//     if (list is List) {
//       for (final item in list) {
//         if (item is Map && item['id'] == petugasUser.uid) return true;
//       }
//     }
//     return false;
//   }).toList();
//   final aktif   = myDocs.where((d) => (d.data() as Map)['status'] == 'Disetujui').length;
//   final selesai = myDocs.where((d) => (d.data() as Map)['status'] == 'Selesai').length;
//   final total   = myDocs.length;