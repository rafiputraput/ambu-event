// lib/screens/home_screen.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../service/map_service.dart';
import '../service/firestore_service.dart';
import '../service/notification_service.dart';
import '../service/image_service.dart';

class HomeScreen extends StatefulWidget {
  final String role;
  final String bookingState;
  final VoidCallback onStartBooking;
  final VoidCallback onCancelForm;
  final VoidCallback onConfirmBooking;
  final String eventType;
  final Function(String) onEventTypeChanged;
  final TextEditingController nameCtrl;
  final TextEditingController dateCtrl;
  final TextEditingController locCtrl;
  final VoidCallback onGoToAdminUser;
  final VoidCallback onGoToAdminAmb;
  final VoidCallback onGoToMap;
  final VoidCallback onGoToAdminKegiatan;
  final List<String> uploadedDocNames;
  final Function(List<String>)? onDocumentsChanged;

  const HomeScreen({
    super.key,
    required this.role,
    required this.bookingState,
    required this.onStartBooking,
    required this.onCancelForm,
    required this.onConfirmBooking,
    required this.eventType,
    required this.onEventTypeChanged,
    required this.nameCtrl,
    required this.dateCtrl,
    required this.locCtrl,
    required this.onGoToAdminUser,
    required this.onGoToAdminAmb,
    required this.onGoToMap,
    required this.onGoToAdminKegiatan,
    this.uploadedDocNames = const [],
    this.onDocumentsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapService _mapService             = MapService();
  final MapController _homeMapCtrl         = MapController();
  final MapController _bookingMapCtrl      = MapController();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notifService  = NotificationService();
  final ImageService _imageService         = ImageService();

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  List<_NominatimResult> _searchResults = [];
  bool _isSearching    = false;
  bool _showResults    = false;

  static const LatLng _dinkesLocation =
      LatLng(-7.624662988533274, 111.4947916090254);
  static const LatLng _defaultCenter = LatLng(-7.6298, 111.5239);

  LatLng? _userLocation;
  bool _locationLoaded     = false;
  bool _pickingFile        = false;
  bool _isSubmitting       = false;
  bool _isReverseGeocoding = false;

  DateTime? _selectedDate;
  LatLng?   _pickedLatLng;

  // State foto
  List<PlatformFile> _pickedPhotos = [];
  String  _processStatus   = '';
  double  _processProgress = 0.0;
  bool    _isProcessing    = false;

  // Tipe acara
  final List<Map<String, dynamic>> _eventTypes = [
    {'label': 'Konser',       'icon': Icons.music_note},
    {'label': 'Olahraga',     'icon': Icons.emoji_events},
    {'label': 'Pengajian',    'icon': Icons.mosque},
    {'label': 'Pencak Silat', 'icon': Icons.sports_martial_arts},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) setState(() => _showResults = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─── Location ───────────────────────────────────────────────────────
  Future<void> _loadUserLocation() async {
    final loc = await _mapService.getCurrentLocation();
    if (mounted) setState(() { _userLocation = loc; _locationLoaded = true; });
  }

  // ─── Search ─────────────────────────────────────────────────────────
  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.length < 3) {
      setState(() { _searchResults = []; _showResults = false; });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchPlace(q));
  }

  Future<void> _searchPlace(String query) async {
    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=id',
      );
      final resp = await http
          .get(uri, headers: {'Accept-Language': 'id', 'User-Agent': 'ambuevent'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final List data = json.decode(resp.body);
        setState(() {
          _searchResults = data.map((e) => _NominatimResult.fromJson(e)).toList();
          _showResults   = _searchResults.isNotEmpty;
        });
      }
    } catch (e) { print('Search error: $e'); }
    finally { if (mounted) setState(() => _isSearching = false); }
  }

  Future<void> _reverseGeocode(LatLng ll) async {
    setState(() => _isReverseGeocoding = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${ll.latitude}&lon=${ll.longitude}&format=json',
      );
      final resp = await http
          .get(uri, headers: {'Accept-Language': 'id', 'User-Agent': 'ambuevent'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body);
        final name = _short(data['display_name'] ?? '');
        setState(() { widget.locCtrl.text = name; _searchCtrl.text = name; });
      }
    } catch (e) {
      if (mounted) {
        widget.locCtrl.text =
            '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
      }
    } finally {
      if (mounted) setState(() => _isReverseGeocoding = false);
    }
  }

  String _short(String full) => full.split(', ').take(4).join(', ');

  void _selectResult(_NominatimResult r) {
    final ll   = LatLng(r.lat, r.lon);
    final name = _short(r.displayName);
    _searchFocus.unfocus();
    setState(() {
      _pickedLatLng  = ll;
      widget.locCtrl.text = name;
      _searchCtrl.text    = name;
      _searchResults = [];
      _showResults   = false;
    });
    Future.delayed(const Duration(milliseconds: 150),
        () { if (mounted) _bookingMapCtrl.move(ll, 16); });
  }

  void _onMapTap(TapPosition _, LatLng ll) {
    _searchFocus.unfocus();
    setState(() {
      _pickedLatLng = ll;
      _showResults  = false;
      widget.locCtrl.text = 'Mengambil alamat...';
      _searchCtrl.text    = '';
    });
    _reverseGeocode(ll);
  }

  Future<void> _goToMyLocation() async {
    final loc = _userLocation ?? await _mapService.getCurrentLocation();
    if (loc != null && mounted) {
      setState(() {
        _pickedLatLng = loc;
        widget.locCtrl.text = 'Mengambil alamat...';
        _searchCtrl.text    = '';
      });
      _bookingMapCtrl.move(loc, 16);
      _reverseGeocode(loc);
    }
  }

  // ─── File Picker (hanya foto) ────────────────────────────────────────
  Future<void> _pickPhotos() async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final newFiles = result.files.where((f) {
          if (!ImageService.isAllowed(f.name)) {
            _snack('File "${f.name}" tidak didukung. Hanya JPG/PNG.');
            return false;
          }
          if (_pickedPhotos.any((p) => p.name == f.name)) return false;
          if (f.size > ImageConfig.maxFileSizeBytes) {
            _snack('File "${f.name}" terlalu besar (maks 5 MB).');
            return false;
          }
          return true;
        }).toList();

        if (newFiles.isNotEmpty) {
          setState(() => _pickedPhotos = [..._pickedPhotos, ...newFiles]);
          widget.onDocumentsChanged?.call(
              _pickedPhotos.map((p) => p.name).toList());
        }
      }
    } catch (e) { _snack('Gagal memilih foto: $e'); }
    finally { if (mounted) setState(() => _pickingFile = false); }
  }

  void _removePhoto(int index) {
    setState(() => _pickedPhotos.removeAt(index));
    widget.onDocumentsChanged?.call(
        _pickedPhotos.map((p) => p.name).toList());
  }

  // ─── Date Picker ──────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFD94F4F))),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        widget.dateCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  // ─── Submit ───────────────────────────────────────────────────────────
  void _handleKirim() {
    if (widget.nameCtrl.text.trim().isEmpty) { _snack('Nama event harus diisi!'); return; }
    if (widget.dateCtrl.text.trim().isEmpty) { _snack('Tanggal harus diisi!'); return; }
    if (_pickedLatLng == null)               { _snack('Pilih lokasi di peta terlebih dahulu!'); return; }
    _showKonfirmasi();
  }

  void _showKonfirmasi() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFFFFF0F0), shape: BoxShape.circle),
                child: const Icon(Icons.assignment_turned_in, color: Color(0xFFD94F4F), size: 24)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Konfirmasi Booking',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _kRow(Icons.event,          'Nama Event', widget.nameCtrl.text.trim()),
            const SizedBox(height: 8),
            _kRow(Icons.calendar_today, 'Tanggal',    widget.dateCtrl.text.trim()),
            const SizedBox(height: 8),
            _kRow(Icons.location_on,    'Lokasi',     widget.locCtrl.text.trim()),
            const SizedBox(height: 8),
            _kRow(Icons.category,       'Tipe Acara', widget.eventType),
            if (_pickedPhotos.isNotEmpty) ...[
              const SizedBox(height: 8),
              _kRow(Icons.photo_library, 'Foto',
                  '${_pickedPhotos.length} foto · ${_totalSizeLabel()}'),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: const Color(0xFFFFF8F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD59A))),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 15, color: Color(0xFFB87333)),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Foto akan dikompres dan disimpan di server.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFD4843A)))),
              ]),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Periksa Lagi', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _submit(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD94F4F), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Ya, Kirim!', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  String _totalSizeLabel() {
    final total = _pickedPhotos.fold<int>(0, (s, f) => s + f.size);
    return ImageService.formatSize(total);
  }

  Widget _kRow(IconData icon, String label, String value) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: const Color(0xFFD94F4F)),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
      ]);

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _isProcessing = false;
      _processProgress = 0;
      _processStatus = '';
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { _snack('Silakan login!'); return; }

      String userName = user.displayName ?? 'Pengguna';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        if (doc.exists) userName = doc.data()?['name'] ?? userName;
      } catch (_) {}

      List<Map<String, dynamic>> docMaps = [];

      if (_pickedPhotos.isNotEmpty) {
        setState(() { _isProcessing = true; _processStatus = 'Mempersiapkan foto...'; });

        final results = await _imageService.processFiles(
          files: _pickedPhotos,
          onFileProgress: (fileName, index, total, progress) {
            if (mounted) {
              setState(() {
                _processProgress = (index + progress) / total;
                _processStatus   =
                    'Memproses foto ${index + 1}/$total: ${(progress * 100).toInt()}%\n$fileName';
              });
            }
          },
        );

        docMaps = results.map((d) => d.toMap()).toList();

        if (docMaps.length < _pickedPhotos.length) {
          final gagal = _pickedPhotos.length - docMaps.length;
          _snack('⚠️ $gagal foto gagal diproses. Booking tetap dikirim.');
        }
      }

      setState(() { _isProcessing = false; _processStatus = 'Menyimpan booking...'; });

      final id = await _firestoreService.addBooking(
        userId: user.uid,
        userName: userName,
        eventName: widget.nameCtrl.text.trim(),
        date: widget.dateCtrl.text.trim(),
        location: widget.locCtrl.text.trim(),
        type: widget.eventType,
        documentNames: docMaps.map((d) => d['name'] as String).toList(),
        documentFiles: docMaps,
        latitude:  _pickedLatLng?.latitude,
        longitude: _pickedLatLng?.longitude,
      );

      if (id != null) {
        await _notifService.notifyAdminsNewBooking(
          eventName: widget.nameCtrl.text.trim(),
          userName:  userName,
          date:      widget.dateCtrl.text.trim(),
        );
        setState(() => _pickedPhotos = []);
        widget.onConfirmBooking();
        if (mounted) _snack('Booking berhasil dikirim! 🎉', ok: true);
      } else {
        _snack('Gagal menyimpan booking. Coba lagi.');
      }
    } catch (e) {
      print('[HOME] submit error: $e');
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() {
        _isSubmitting = false;
        _isProcessing = false;
        _processStatus = '';
        _processProgress = 0;
      });
    }
  }

  void _snack(String msg, {bool ok = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? const Color(0xFF4CAF7D) : const Color(0xFFD94F4F),
      ));

  // ═══════════════════════════ BUILD ══════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (widget.bookingState != 'idle') return _buildForm();
    return _buildIdle();
  }

  // ─── Idle ────────────────────────────────────────────────────────────
  Widget _buildIdle() {
    return Column(children: [
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.45,
        child: Stack(children: [
          FlutterMap(
            mapController: _homeMapCtrl,
            options: const MapOptions(
              initialCenter: _dinkesLocation, initialZoom: 15,
              maxZoom: 18, minZoom: 5,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.ambuevent', maxZoom: 18),
              MarkerLayer(markers: [
                Marker(point: _dinkesLocation, width: 60, height: 70,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFD94F4F), shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFD94F4F).withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)]),
                      child: const Icon(Icons.local_hospital, color: Colors.white, size: 20)),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFFD94F4F), size: 20),
                  ])),
                if (_userLocation != null)
                  Marker(point: _userLocation!, width: 40, height: 40,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(width: 30, height: 30,
                        decoration: BoxDecoration(color: const Color(0xFF5B8DB8).withValues(alpha: 0.2), shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF5B8DB8).withValues(alpha: 0.5), width: 2))),
                      Container(width: 12, height: 12,
                        decoration: const BoxDecoration(color: Color(0xFF5B8DB8), shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 3)])),
                    ])),
              ]),
            ],
          ),
          Positioned(top: 40, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
              child: const Row(children: [
                Icon(Icons.local_hospital, color: Color(0xFFD94F4F), size: 16),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dinkes Kab. Madiun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('Jl. Raya Solo No. 32, Jiwan', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ])),
              ]))),
          Positioned(bottom: 14, right: 14,
            child: Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
              child: InkWell(customBorder: const CircleBorder(), onTap: widget.onGoToMap,
                child: const Padding(padding: EdgeInsets.all(10),
                    child: Icon(Icons.fullscreen, color: Color(0xFFD94F4F), size: 22))))),
        ]),
      ),
      Expanded(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]),
          child: widget.role == 'user' ? _buildUserIdle() : _buildAdminIdle(),
        ),
      ),
    ]);
  }

  Widget _buildUserIdle() {
    final bot = MediaQuery.of(context).padding.bottom + 70;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bot),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Color(0xFFFFF0F0), shape: BoxShape.circle),
          child: const Icon(Icons.medical_services_outlined, size: 56, color: Color(0xFFD94F4F))),
        const SizedBox(height: 12),
        const Text('Booking Event', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Sediakan layanan medis standby untuk kelancaran event Anda.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: widget.onStartBooking,
            icon: const Icon(Icons.add_circle_outline, size: 22),
            label: const Text('BUAT BOOKING BARU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD94F4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 3))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 46,
          child: OutlinedButton.icon(
            onPressed: widget.onGoToMap,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Lihat Peta Lokasi'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD94F4F),
              side: const BorderSide(color: Color(0xFFD94F4F)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildAdminIdle() {
    final bot = MediaQuery.of(context).padding.bottom + 70;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bot),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.medical_services_outlined, color: Color(0xFFD94F4F), size: 28)),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dashboard Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Kelola booking & armada', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('bookings')
              .where('status', isEqualTo: 'Menunggu Konfirmasi').snapshots(),
          builder: (ctx, snap) {
            final count = snap.data?.docs.length ?? 0;
            if (count == 0) return const SizedBox.shrink();
            return GestureDetector(
              onTap: widget.onGoToAdminKegiatan,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF0F5FA), borderRadius: BorderRadius.circular(10),
                  border: const Border(left: BorderSide(color: Color(0xFF5B8DB8), width: 4))),
                child: Row(children: [
                  const Icon(Icons.notifications_active, size: 18, color: Color(0xFF5B8DB8)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$count booking baru menunggu konfirmasi.',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const Icon(Icons.chevron_right, color: Color(0xFF7AADD4), size: 18),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text('Menu Utama', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _adminCard('Kelola User',   Icons.people_alt,    const Color(0xFF5B8DB8), widget.onGoToAdminUser)),
          const SizedBox(width: 10),
          Expanded(child: _adminCard('Kelola Armada', Icons.local_hospital, const Color(0xFFD94F4F), widget.onGoToAdminAmb)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _adminCard('Kegiatan',  Icons.event_note,    const Color(0xFFD4843A), widget.onGoToAdminKegiatan)),
          const SizedBox(width: 10),
          Expanded(child: _adminCard('Peta Event', Icons.map_outlined, Colors.teal,             widget.onGoToMap)),
        ]),
      ]),
    );
  }

  Widget _adminCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    );
  }

  // ─── FORM ─────────────────────────────────────────────────────────────
  Widget _buildForm() {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).viewPadding.bottom;

    return Column(children: [
      // App Bar
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(4, topPad + 4, 4, 0),
        child: Row(children: [
          IconButton(onPressed: widget.onCancelForm,
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20)),
          const Expanded(child: Text('Form Booking Event',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(onPressed: widget.onCancelForm,
              icon: const Icon(Icons.close, color: Colors.grey)),
        ]),
      ),
      const Divider(height: 1),

      // Body
      Expanded(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              // Nama event & tanggal
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('Nama Event *'),
                  const SizedBox(height: 6),
                  _field('Contoh: Konser Rakyat Madiun', widget.nameCtrl, icon: Icons.event),
                  const SizedBox(height: 14),
                  _lbl('Tanggal Event *'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: AbsorbPointer(child: _field('Pilih tanggal...', widget.dateCtrl, icon: Icons.calendar_today)),
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // Lokasi
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  _lbl('Lokasi Event *'),
                  const Spacer(),
                  if (_pickedLatLng != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Text('Dipilih', style: TextStyle(fontSize: 10,
                            color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    decoration: BoxDecoration(color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: TextField(
                      controller: _searchCtrl, focusNode: _searchFocus,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Cari nama tempat atau ketuk peta...',
                        hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFD94F4F), size: 20),
                        suffixIcon: _isSearching
                            ? const Padding(padding: EdgeInsets.all(12),
                                child: SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD94F4F))))
                            : _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                    onPressed: () { _searchCtrl.clear(); setState(() { _searchResults = []; _showResults = false; }); })
                                : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (v) { if (v.trim().isNotEmpty) _searchPlace(v.trim()); },
                    ),
                  ),
                  if (_showResults && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ListView.separated(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero, itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _searchResults[i];
                            return InkWell(
                              onTap: () => _selectResult(r),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(children: [
                                  const Icon(Icons.location_on, size: 16, color: Color(0xFFD94F4F)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_short(r.displayName),
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Icon(Icons.touch_app, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('Tap di peta untuk menandai lokasi event',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ),
              const SizedBox(height: 6),

              // Peta
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(height: 260,
                    child: Stack(children: [
                      FlutterMap(
                        mapController: _bookingMapCtrl,
                        options: MapOptions(
                          initialCenter: _pickedLatLng ?? _userLocation ?? _defaultCenter,
                          initialZoom: 14, maxZoom: 18, minZoom: 5, onTap: _onMapTap,
                        ),
                        children: [
                          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.ambuevent', maxZoom: 18),
                          if (_pickedLatLng != null)
                            MarkerLayer(markers: [Marker(point: _pickedLatLng!, width: 48, height: 58, child: _pin())]),
                          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
                        ],
                      ),
                      if (_pickedLatLng == null)
                        Center(child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.touch_app, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Tap peta untuk pilih lokasi', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ]),
                        )),
                      Positioned(right: 10, top: 10,
                        child: Column(children: [
                          _zBtn(Icons.add, () {
                            final z = _bookingMapCtrl.camera.zoom;
                            _bookingMapCtrl.move(_bookingMapCtrl.camera.center, (z + 1).clamp(5, 18));
                          }),
                          const SizedBox(height: 4),
                          _zBtn(Icons.remove, () {
                            final z = _bookingMapCtrl.camera.zoom;
                            _bookingMapCtrl.move(_bookingMapCtrl.camera.center, (z - 1).clamp(5, 18));
                          }),
                        ])),
                      Positioned(right: 10, bottom: 10,
                        child: Material(color: Colors.white, shape: const CircleBorder(), elevation: 4,
                          child: InkWell(customBorder: const CircleBorder(), onTap: _goToMyLocation,
                            child: const Padding(padding: EdgeInsets.all(10),
                                child: Icon(Icons.my_location, color: Color(0xFF5B8DB8), size: 20))))),
                      if (_isReverseGeocoding)
                        Positioned(bottom: 10, left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(width: 12, height: 12,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                              SizedBox(width: 6),
                              Text('Mengambil alamat...', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ]),
                          )),
                    ]),
                  ),
                ),
              ),
              if (_pickedLatLng != null && widget.locCtrl.text.isNotEmpty &&
                  widget.locCtrl.text != 'Mengambil alamat...')
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF0FFF4),
                      borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.location_on, color: Color(0xFFD94F4F), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.locCtrl.text,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 3, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),

              // Tipe Acara
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('Tipe Acara'),
                  const SizedBox(height: 10),
                  Column(children: [
                    Row(children: [
                      Expanded(child: _typeBtn(_eventTypes[0]['label'] as String, _eventTypes[0]['icon'] as IconData)),
                      const SizedBox(width: 8),
                      Expanded(child: _typeBtn(_eventTypes[1]['label'] as String, _eventTypes[1]['icon'] as IconData)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _typeBtn(_eventTypes[2]['label'] as String, _eventTypes[2]['icon'] as IconData)),
                      const SizedBox(width: 8),
                      Expanded(child: _typeBtn(_eventTypes[3]['label'] as String, _eventTypes[3]['icon'] as IconData)),
                    ]),
                  ]),
                ]),
              ),

              // ════════════════════════════════════════════════════
              // BERKAS PENDUKUNG (hanya foto)
              // ════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Header
                  Row(children: [
                    _lbl('Berkas Pendukung'),
                    const Spacer(),
                    GestureDetector(
                      onTap: _pickingFile ? null : _pickPhotos,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F0),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD94F4F).withValues(alpha: 0.4))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _pickingFile
                              ? const SizedBox(width: 13, height: 13,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD94F4F)))
                              : const Icon(Icons.add_photo_alternate_outlined, size: 15, color: Color(0xFFD94F4F)),
                          const SizedBox(width: 5),
                          const Text('Tambah Foto',
                              style: TextStyle(color: Color(0xFFD94F4F), fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),

                  // Subtitle
                  Text('Foto: JPG/PNG maks 5 MB per berkas.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 10),

                  // Slot kosong atau grid foto
                  if (_pickedPhotos.isEmpty)
                    GestureDetector(
                      onTap: _pickingFile ? null : _pickPhotos,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: const Color(0xFFD94F4F), size: 32),
                          const SizedBox(height: 8),
                          const Text('Tap untuk memilih foto',
                              style: TextStyle(color: Color(0xFFD94F4F),
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('Opsional — foto pendukung event',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                        ]),
                      ),
                    )
                  else ...[
                    // Grid foto
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1),
                      itemCount: _pickedPhotos.length,
                      itemBuilder: (_, i) {
                        final photo = _pickedPhotos[i];
                        return Stack(fit: StackFit.expand, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: photo.bytes != null
                                ? Image.memory(photo.bytes!, fit: BoxFit.cover)
                                : Container(color: Colors.grey.shade200,
                                    child: const Icon(Icons.image, color: Colors.grey)),
                          ),
                          Positioned(bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                              child: Text(ImageService.formatSize(photo.size),
                                  style: const TextStyle(fontSize: 9, color: Colors.white),
                                  textAlign: TextAlign.center),
                            )),
                          Positioned(top: 4, right: 4,
                            child: GestureDetector(
                              onTap: () => _removePhoto(i),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(color: Color(0xFFD94F4F), shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 12, color: Colors.white)),
                            )),
                        ]);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Tambah foto lagi
                    GestureDetector(
                      onTap: _pickingFile ? null : _pickPhotos,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Text('Tambah foto lagi (${_pickedPhotos.length} dipilih · ${_totalSizeLabel()})',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                      ),
                    ),
                  ],

                  // Loading proses
                  if (_isProcessing) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB8D4F0))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [
                          SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5B8DB8))),
                          SizedBox(width: 10),
                          Text('Memproses foto...',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B8DB8))),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _processProgress,
                            backgroundColor: Colors.grey.shade200,
                            color: const Color(0xFF5B8DB8), minHeight: 8),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(_processProgress * 100).toInt()}%  ·  ${_processStatus.split('\n').first}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                  ],
                ]),
              ),

              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFD59A))),
                  child: const Row(children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFFB87333)),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Tim medis hadir 1 jam sebelum acara. Booking dikonfirmasi oleh admin.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFD4843A)))),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),

      // Bottom Button
      Container(
        decoration: BoxDecoration(color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -4))]),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + botPad),
        child: SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _handleKirim,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD94F4F), foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFBBBB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            child: _isSubmitting
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(
                      _isProcessing
                          ? 'Memproses... ${(_processProgress * 100).toInt()}%'
                          : 'Menyimpan...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ])
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.send_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('KIRIM BOOKING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
          ),
        ),
      ),
    ]);
  }

  // ── Shared widgets ───────────────────────────────────────────────────
  Widget _pin() => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 38, height: 38,
      decoration: BoxDecoration(color: const Color(0xFFD94F4F), shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: const Color(0xFFD94F4F).withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]),
      child: const Icon(Icons.location_on, color: Colors.white, size: 20)),
    CustomPaint(painter: _PinTail(), size: const Size(12, 10)),
  ]);

  Widget _zBtn(IconData icon, VoidCallback onTap) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(6), elevation: 3,
    child: InkWell(borderRadius: BorderRadius.circular(6), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 18, color: Colors.black54))));

  Widget _lbl(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));

  Widget _field(String hint, TextEditingController ctrl, {IconData? icon}) => TextField(
    controller: ctrl,
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
      prefixIcon: icon != null ? Icon(icon, size: 18, color: Colors.grey) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD94F4F), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true, fillColor: Colors.grey.shade50),
  );

  Widget _typeBtn(String label, IconData icon) {
    final sel = widget.eventType == label;
    return GestureDetector(
      onTap: () => widget.onEventTypeChanged(label),
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), height: 44,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFFF0F0) : Colors.white,
          border: Border.all(color: sel ? const Color(0xFFD94F4F) : const Color(0xFF9E9E9E), width: sel ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: sel ? const Color(0xFFD94F4F) : const Color(0xFF9E9E9E)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
              color: sel ? const Color(0xFFD94F4F) : const Color(0xFF9E9E9E))),
        ])),
    );
  }
}

class _PinTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      ui.Path()..moveTo(0, 0)..lineTo(size.width / 2, size.height)..lineTo(size.width, 0)..close(),
      Paint()..color = const Color(0xFFD94F4F)..style = PaintingStyle.fill,
    );
  }
  @override bool shouldRepaint(_) => false;
}

class _NominatimResult {
  final double lat, lon;
  final String displayName;
  const _NominatimResult({required this.lat, required this.lon, required this.displayName});
  factory _NominatimResult.fromJson(Map<String, dynamic> j) => _NominatimResult(
    lat: double.tryParse(j['lat'].toString()) ?? 0,
    lon: double.tryParse(j['lon'].toString()) ?? 0,
    displayName: j['display_name'] ?? '');
}