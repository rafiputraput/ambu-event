// lib/screens/map_screen.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/map_service.dart';
import '../service/routing_service.dart';

class MapScreen extends StatefulWidget {
  final String bookingState;
  final String eventName;
  final String eventDate;
  final String eventLoc;
  final VoidCallback onCancel;

  const MapScreen({
    super.key,
    required this.bookingState,
    required this.eventName,
    required this.eventDate,
    required this.eventLoc,
    required this.onCancel,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// Model sederhana untuk event yang disetujui
class _ApprovedEvent {
  final String id;
  final String eventName;
  final String userName;
  final String date;
  final String location;
  final String type;
  final String status;
  final LatLng latLng;

  const _ApprovedEvent({
    required this.id,
    required this.eventName,
    required this.userName,
    required this.date,
    required this.location,
    required this.type,
    required this.status,
    required this.latLng,
  });
}

class _MapScreenState extends State<MapScreen> {
  final MapController  _mapController  = MapController();
  final MapService     _mapService     = MapService();
  final RoutingService _routingService = RoutingService();

  static const LatLng _defaultCenter = LatLng(-7.6298, 111.5239);

  LatLng? _userLocation;
  List<PetugasLiveLocation> _petugasLive = [];
  List<_ApprovedEvent> _approvedEvents   = [];

  List<LatLng>  _routePoints = [];
  RouteResult?  _routeResult;

  bool _isLoadingLocation = true;
  bool _isLoadingRoute    = false;
  bool _showPuskesmas     = true;
  bool _mapReady          = false;

  StreamSubscription<LatLng>?                    _locationSubscription;
  StreamSubscription<List<PetugasLiveLocation>>? _petugasSubscription;
  StreamSubscription<QuerySnapshot>?             _bookingSubscription;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _listenPetugasLive();
    _listenApprovedBookings();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _petugasSubscription?.cancel();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    setState(() => _isLoadingLocation = true);
    final location = await _mapService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _userLocation      = location ?? _defaultCenter;
        _isLoadingLocation = false;
      });
      if (location != null) _moveWhenReady(location, 13);
    }
    _locationSubscription = _mapService.getLocationStream().listen((latLng) {
      if (mounted) setState(() => _userLocation = latLng);
    });
  }

  void _moveWhenReady(LatLng target, double zoom) {
    if (_mapReady) {
      try { _mapController.move(target, zoom); } catch (_) {}
      return;
    }
    int tries = 0;
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      tries++;
      if (!mounted) { timer.cancel(); return; }
      if (_mapReady || tries > 20) {
        timer.cancel();
        try { _mapController.move(target, zoom); } catch (_) {}
      }
    });
  }

  void _listenPetugasLive() {
    _petugasSubscription =
        _mapService.getPetugasLiveLocations().listen((list) {
      if (mounted) setState(() => _petugasLive = list);
    });
  }

  // ── Hanya tampilkan event berstatus "Disetujui" ──────────────────────
  void _listenApprovedBookings() {
    _bookingSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: 'Disetujui')
        .snapshots()
        .listen((snap) {
      final events = <_ApprovedEvent>[];
      for (final doc in snap.docs) {
        final d   = doc.data();
        final lat = (d['eventLatitude']  as num?)?.toDouble();
        final lng = (d['eventLongitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        events.add(_ApprovedEvent(
          id:        doc.id,
          eventName: d['eventName'] ?? 'Event',
          userName:  d['userName']  ?? '-',
          date:      d['date']      ?? '-',
          location:  d['location']  ?? d['eventLoc'] ?? '-',
          type:      d['type']      ?? '-',
          status:    d['status']    ?? '-',
          latLng:    LatLng(lat, lng),
        ));
      }
      if (mounted) setState(() => _approvedEvents = events);
    });
  }

  Future<void> _loadRoute(LatLng from, LatLng to) async {
    setState(() {
      _isLoadingRoute = true;
      _routePoints    = [];
      _routeResult    = null;
    });
    final result = await _routingService.getRoute(from, to);
    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
        if (result != null) {
          _routePoints = result.points;
          _routeResult = result;
        }
      });
      if (result != null && result.points.isNotEmpty) {
        _fitRouteBounds(result.points);
      }
    }
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLat - 0.005, minLng - 0.005),
        LatLng(maxLat + 0.005, maxLng + 0.005),
      ),
      padding: const EdgeInsets.all(60),
    ));
  }

  void _showSheet(Widget content) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final safePad = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: safePad),
          child: content,
        );
      },
    );
  }

  // ── Sheet: Lokasi Saya ───────────────────────────────────────────────
  void _showMyLocationSheet() {
    if (_userLocation == null) return;
    _showSheet(Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        Row(children: [
          _iconBox(Icons.person_pin_circle, Colors.blue),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Lokasi Saya',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Row(children: [
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle)),
              const Text('GPS Aktif',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ])),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.location_on, color: Colors.blue, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Lat: ${_userLocation!.latitude.toStringAsFixed(6)}\n'
                'Lng: ${_userLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
          ]),
        ),
        if (_approvedEvents.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.event_available_rounded,
                  color: Colors.green, size: 15),
              const SizedBox(width: 8),
              Text(
                '${_approvedEvents.length} event aktif di sekitar area',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ]),
          ),
        ],
      ]),
    ));
  }

  // ── Sheet: Detail Petugas ────────────────────────────────────────────
  void _showPetugasSheet(PetugasLiveLocation p) {
    String timeAgo = 'Tidak diketahui';
    if (p.lastUpdated != null) {
      final diff = DateTime.now().difference(p.lastUpdated!);
      if (diff.inSeconds < 60)      timeAgo = '${diff.inSeconds} detik lalu';
      else if (diff.inMinutes < 60) timeAgo = '${diff.inMinutes} menit lalu';
      else                          timeAgo = '${diff.inHours} jam lalu';
    }
    _showSheet(Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        Row(children: [
          _iconBox(Icons.medical_services_rounded, Colors.orange),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Row(children: [
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle)),
              const Text('Sedang Aktif',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ])),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.access_time, color: Colors.orange, size: 15),
            const SizedBox(width: 8),
            Text('Lokasi diperbarui: $timeAgo',
                style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.location_on, color: Colors.grey, size: 15),
            const SizedBox(width: 8),
            Text(
              '${p.latLng.latitude.toStringAsFixed(5)}, '
              '${p.latLng.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ]),
        ),
        if (_userLocation != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.straighten, color: Colors.blue, size: 15),
              const SizedBox(width: 8),
              Text(
                'Jarak dari Anda: ${_mapService.formatDistance(_mapService.calculateDistance(_userLocation!, p.latLng))}',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ]),
          ),
        ],
      ]),
    ));
  }

  // ── Sheet: Detail Puskesmas ──────────────────────────────────────────
  void _showPuskesmasSheet(PuskesmasLocation puskesmas) {
    _showSheet(Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _handle(),
        Row(children: [
          _iconBox(Icons.local_hospital, Colors.green),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(puskesmas.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text('No. ${puskesmas.no}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(puskesmas.address,
              style: const TextStyle(fontSize: 13, color: Colors.grey))),
        ]),
        if (_userLocation != null) ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(children: [
            _infoChip(Icons.straighten,
                _mapService.formatDistance(_mapService.calculateDistance(
                    _userLocation!, puskesmas.latLng)),
                Colors.blue),
            const SizedBox(width: 12),
            _infoChip(Icons.access_time,
                _mapService.estimateTime(_mapService.calculateDistance(
                    _userLocation!, puskesmas.latLng)),
                Colors.orange),
          ]),
        ],
      ]),
    ));
  }

  // ── Sheet: Detail Event Disetujui ────────────────────────────────────
  void _showApprovedEventSheet(_ApprovedEvent event) {
    _showSheet(Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        _handle(),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, size: 13, color: Colors.red),
              const SizedBox(width: 5),
              const Text('Disetujui',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.red)),
            ]),
          ),
          const Spacer(),
          Text(event.date,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_note_rounded,
                color: Colors.red, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.eventName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(event.userName,
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
        _detailRow(Icons.location_on_rounded, event.location),
        const SizedBox(height: 6),
        _detailRow(Icons.category_rounded, event.type),
        if (_userLocation != null) ...[
          const SizedBox(height: 6),
          _detailRow(
            Icons.straighten,
            'Jarak: ${_mapService.formatDistance(_mapService.calculateDistance(_userLocation!, event.latLng))}',
            color: Colors.blue,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingRoute
                  ? null
                  : () {
                      Navigator.pop(context);
                      _loadRoute(_userLocation!, event.latLng);
                      _mapController.move(event.latLng, 14);
                    },
              icon: _isLoadingRoute
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.route_rounded, size: 16),
              label: Text(
                  _isLoadingRoute ? 'Menghitung...' : 'Tampilkan Rute ke Event'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
        if (_routeResult != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.route, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_routingService.formatDistance(_routeResult!.distanceMeters)} • '
                '${_routingService.formatDuration(_routeResult!.durationSeconds)}',
                style: const TextStyle(
                    color: Colors.blue, fontWeight: FontWeight.w500),
              )),
            ]),
          ),
        ],
      ]),
    ));
  }

  Widget _detailRow(IconData icon, String val, {Color? color}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: color ?? Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(child: Text(val,
            style: TextStyle(
                fontSize: 12, color: color ?? Colors.grey.shade700),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);

  Widget _handle() => Center(child: Container(
    width: 40, height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
        color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
  ));

  Widget _iconBox(IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, color: color, size: 28),
  );

  Widget _infoChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    ]),
  );

  // ════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq   = MediaQuery.of(context);
    final navH = 70.0 + mq.viewPadding.bottom;

    return Scaffold(
      extendBody: false,
      body: Stack(children: [

        // ── PETA ──────────────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          bottom: navH,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 13,
              maxZoom: 18,
              minZoom: 5,
              onMapReady: () {
                _mapReady = true;
                if (_userLocation != null &&
                    _userLocation != _defaultCenter) {
                  _mapController.move(_userLocation!, 13);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ambuevent',
                maxZoom: 18,
              ),

              // Garis rute
              if (_routePoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 4),
                ]),

              MarkerLayer(markers: [

                // ── Lokasi saya (bisa diklik) ──────────────────────
                if (_userLocation != null)
                  Marker(
                    point: _userLocation!,
                    width: 60,
                    height: 60,
                    child: GestureDetector(
                      onTap: _showMyLocationSheet,
                      child: _userMarker(),
                    ),
                  ),

                // ── Puskesmas ──────────────────────────────────────
                if (_showPuskesmas)
                  ..._mapService.getPuskesmasList().map((p) => Marker(
                        point: p.latLng,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showPuskesmasSheet(p),
                          child: _puskesmasMarker(),
                        ),
                      )),

                // ── Event Disetujui dari Firestore ─────────────────
                ..._approvedEvents.map((e) => Marker(
                      point: e.latLng,
                      width: 52,
                      height: 62,
                      child: GestureDetector(
                        onTap: () => _showApprovedEventSheet(e),
                        child: _eventMarker(),
                      ),
                    )),

                // ── Petugas live ───────────────────────────────────
                ..._petugasLive.map((p) => Marker(
                      point: p.latLng,
                      width: 56,
                      height: 66,
                      child: GestureDetector(
                        onTap: () => _showPetugasSheet(p),
                        child: _petugasMarker(),
                      ),
                    )),
              ]),

              const RichAttributionWidget(attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ]),
            ],
          ),
        ),

        // ── Loading overlay ────────────────────────────────────────
        if (_isLoadingLocation)
          Container(
            color: Colors.black38,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: Colors.red),
                    SizedBox(height: 12),
                    Text('Mendapatkan lokasi...'),
                  ]),
                ),
              ),
            ),
          ),

        // ── Top bar ────────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onCancel,
                    child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.arrow_back, size: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.event, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        widget.eventName.isEmpty
                            ? 'Peta Event'
                            : widget.eventName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ),
                )),
              ]),
            ),
          ),
        ),

        // ── Legend ────────────────────────────────────────────────
        Positioned(
          right: 12, top: 100,
          child: Column(children: [

            // Lokasi saya
            _legendItem(Colors.blue, Icons.person_pin_circle, 'Lokasi Saya'),
            const SizedBox(height: 6),

            // Event aktif (hanya Disetujui)
            if (_approvedEvents.isNotEmpty) ...[
              _legendItem(Colors.red, Icons.location_on,
                  'Event Aktif (${_approvedEvents.length})'),
              const SizedBox(height: 6),
            ],

            // Petugas live
            if (_petugasLive.isNotEmpty) ...[
              _legendItem(Colors.orange, Icons.medical_services_rounded,
                  'Petugas (${_petugasLive.length})'),
              const SizedBox(height: 6),
            ],

            // Toggle faskes
            GestureDetector(
              onTap: () => setState(() => _showPuskesmas = !_showPuskesmas),
              child: Material(
                color: _showPuskesmas ? Colors.green : Colors.white,
                borderRadius: BorderRadius.circular(8),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_hospital,
                        color: _showPuskesmas ? Colors.white : Colors.green,
                        size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Faskes (${_mapService.getPuskesmasList().length})',
                      style: TextStyle(
                          fontSize: 10,
                          color: _showPuskesmas
                              ? Colors.white
                              : Colors.black),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),

        // ── Tombol recenter ────────────────────────────────────────
        Positioned(
          right: 12,
          bottom: navH + _cardHeight() + 12,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                if (_userLocation != null) {
                  _mapController.move(_userLocation!, 13);
                }
              },
              child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.my_location,
                      color: Colors.blue, size: 24)),
            ),
          ),
        ),

        // ── Bottom card ────────────────────────────────────────────
        Positioned(
          left: 16, right: 16,
          bottom: navH,
          child: _buildBottomCard(),
        ),
      ]),
    );
  }

  double _cardHeight() {
    switch (widget.bookingState) {
      case 'searching': return 160;
      case 'booked':    return 210;
      default:          return 80;
    }
  }

  // ── Marker: Lokasi saya ──────────────────────────────────────────────
  Widget _userMarker() => Stack(alignment: Alignment.center, children: [
    // Lingkaran luar (pulse effect)
    Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blue.withOpacity(0.5), width: 2),
      ),
    ),
    // Dot tengah
    Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 12),
    ),
    // Hint "tap" kecil di sudut
    Positioned(
      top: 2, right: 2,
      child: Container(
        width: 14, height: 14,
        decoration: const BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: const Icon(Icons.info_outline, size: 10, color: Colors.blue),
      ),
    ),
  ]);

  // ── Marker: Event Disetujui ──────────────────────────────────────────
  Widget _eventMarker() => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
            color: Colors.red.withOpacity(0.5),
            blurRadius: 6, spreadRadius: 1)],
      ),
      child: const Icon(Icons.location_on, color: Colors.white, size: 18),
    ),
    const Icon(Icons.arrow_drop_down, color: Colors.red, size: 20),
  ]);

  // ── Marker: Puskesmas ────────────────────────────────────────────────
  Widget _puskesmasMarker() => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.green, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: const Icon(Icons.local_hospital, color: Colors.green, size: 16),
  );

  // ── Marker: Petugas Live ─────────────────────────────────────────────
  Widget _petugasMarker() => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
            color: Colors.orange.withOpacity(0.5),
            blurRadius: 8, spreadRadius: 1)],
      ),
      child: const Icon(Icons.medical_services_rounded,
          color: Colors.white, size: 18),
    ),
    const Icon(Icons.arrow_drop_down, color: Colors.orange, size: 20),
  ]);

  Widget _legendItem(Color color, IconData icon, String label) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    elevation: 3,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ]),
    ),
  );

  // ── Bottom card ──────────────────────────────────────────────────────
  Widget _buildBottomCard() {
    switch (widget.bookingState) {
      case 'searching':
        return Card(
          elevation: 10,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: Colors.red),
              const SizedBox(height: 10),
              const Text('Memverifikasi Ketersediaan...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Harap tunggu sebentar',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, color: Colors.red, size: 16),
                label: const Text('Batalkan',
                    style: TextStyle(color: Colors.red)),
              ),
            ]),
          ),
        );

      case 'booked':
        return Card(
          elevation: 10,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle,
                        size: 12, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text('BOOKING TERKIRIM',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
                const Spacer(),
                Text('${_approvedEvents.length} event aktif di peta',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_hospital,
                      color: Colors.red, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    widget.eventName.isEmpty
                        ? 'Event Baru'
                        : widget.eventName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.eventDate} • ${widget.eventLoc}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ])),
              ]),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              const Row(children: [
                Icon(Icons.touch_app, size: 13, color: Colors.blue),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Tap marker merah untuk detail event aktif',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                )),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Kembali ke Menu Utama'),
                ),
              ),
            ]),
          ),
        );

      default:
        return Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(
                _approvedEvents.isEmpty
                    ? 'Belum ada event aktif'
                    : '${_approvedEvents.length} event aktif • Tap marker untuk detail',
                style: const TextStyle(fontSize: 12),
              )),
            ]),
          ),
        );
    }
  }
}