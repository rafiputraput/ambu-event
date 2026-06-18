// lib/service/map_service.dart
// ignore_for_file: avoid_print
//
// Koordinat bersumber dari:
// - Buku Data Dasar Puskesmas Jawa Timur, Kemenkes RI 2019
// - dilokasi.com (Google Places API)
// - PSC 119: data resmi Dinkes Kab. Madiun

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ─────────────────────────── MODELS ───────────────────────────────────
class AmbulanceLocation {
  final String  id;
  final String  plate;
  final String? petugasName;
  final String? petugasId;
  final String  status;
  final LatLng  latLng;
  final DateTime? lastUpdated;

  AmbulanceLocation({
    required this.id,
    required this.plate,
    this.petugasName,
    this.petugasId,
    required this.status,
    required this.latLng,
    this.lastUpdated,
  });
}

class PuskesmasLocation {
  final int    no;
  final String name;
  final String address;
  final LatLng latLng;

  PuskesmasLocation({
    required this.no,
    required this.name,
    required this.address,
    required this.latLng,
  });
}

// Model untuk live tracking petugas (dilihat admin di peta)
class PetugasLiveLocation {
  final String  uid;
  final String  name;
  final LatLng  latLng;
  final DateTime? lastUpdated;

  PetugasLiveLocation({
    required this.uid,
    required this.name,
    required this.latLng,
    this.lastUpdated,
  });
}

// ═══════════════════════════════════════════════════════════════════════
class MapService {
  final Distance          _distance  = const Distance();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── 29 Fasilitas Kesehatan Kabupaten Madiun ───────────────────────────
  // Sumber: Buku Data Dasar Puskesmas Jatim Kemenkes RI 2019 (kode 1032928-1032956)
  // Kolom: Lintang (latitude), Bujur (longitude)
  // ── 29 Fasilitas Kesehatan Kabupaten Madiun ───────────────────────────
  // Koordinat VERIFIED langsung dari Google Maps oleh pemilik aplikasi
  static final List<PuskesmasLocation> _puskesmasList = [
    PuskesmasLocation(no: 1,  name: 'Puskesmas Gantrung',      address: 'Jalan P. Diponegoro No.311, Pikatan, Mojorejo, Kec. Kb. Sari, Kabupaten Madiun, Jawa Timur 63173',         latLng: LatLng( -7.737991854562192, 111.461118266533)),
    PuskesmasLocation(no: 2,  name: 'Puskesmas Kebonsari',     address: 'Jl. Husni Thamrin, Singghan I, Balerejo, Kec. Kb. Sari, Kabupaten Madiun, Jawa Timur 63173',            latLng: LatLng(-7.720132592297857, 111.50484649536854)),
    PuskesmasLocation(no: 3,  name: 'Puskesmas Geger',         address: 'Jl. Raya Ponorogo - Madiun No.48, Ngrobyong, Purworejo, Kec. Geger, Kabupaten Madiun, Jawa Timur 63491',                        latLng: LatLng(-7.715413755720996, 111.53536830886108)),
    PuskesmasLocation(no: 4,  name: 'Puskesmas Kaibon',        address: 'Jl. Ponco Taruno No.407, Krajan, Kaibon, Kec. Geger, Kabupaten Madiun, Jawa Timur 63171',                        latLng: LatLng(-7.666781824062851, 111.52568426653217)),
    PuskesmasLocation(no: 5,  name: 'Puskesmas Mlilir',        address: '6G58+FW9, Durunan, Mlilir, Kec. Dolopo, Kabupaten Madiun, Jawa Timur 63174',                latLng: LatLng(-7.791304432645538, 111.51732678002598)),
    PuskesmasLocation(no: 6,  name: 'Puskesmas Bangunsari',    address: 'Jl. Panjang Punjung, Krajan, Bangunsari, Kec. Dolopo, Kabupaten Madiun, Jawa Timur 63174',                       latLng: LatLng(-7.752094869130292, 111.52672222420483)),
    PuskesmasLocation(no: 7,  name: 'Puskesmas Dagangan',      address: 'Jl. Raya Pagotan, Dagangan, Kec. Dagangan, Kabupaten Madiun, Jawa Timur 63172',                       latLng: LatLng(-7.707598464690753, 111.55073119536846)),
    PuskesmasLocation(no: 8,  name: 'Puskesmas Jetis',         address: 'Pandansari, Jetis, Kec. Dagangan, Kabupaten Madiun, Jawa Timur 63172',                                      latLng: LatLng(-7.7024777641815705, 111.57273816653262)),
    PuskesmasLocation(no: 9,  name: 'Puskesmas Wungu',         address: 'Jl. Raya Dungus, Magersari, Wungu, Kec. Wungu, Kabupaten Madiun, Jawa Timur 63181',                           latLng: LatLng(-7.686626224761985, 111.61400029536829)),
    PuskesmasLocation(no: 10, name: 'Puskesmas Mojopurno',     address: 'Jl. Raya Dungus, Krajan II, Mojopurno, Kec. Wungu, Kabupaten Madiun, Jawa Timur 63181',                            latLng: LatLng(-7.6494165393239495, 111.55225211122081)),
    PuskesmasLocation(no: 11, name: 'Puskesmas Kare',          address: 'Jl. Raya Randualas, Gondosuli, Kare, Kec. Kare, Kabupaten Madiun, Jawa Timur 63182',                              latLng: LatLng(-7.7177709290012855, 111.68802396653273)),
    PuskesmasLocation(no: 12, name: 'Puskesmas Gemarang',      address: 'Jl. Tgp No.17, Dusun Mundu, Gemarang, Kec. Gemarang, Kabupaten Madiun, Jawa Timur 63156',                               latLng: LatLng(-7.643828894375187, 111.73241217497647)),
    PuskesmasLocation(no: 13, name: 'Puskesmas Saradan',       address: 'Jalan Raya Saradan Madiun No.1, Jl. Raya Saradan Madiun No.1, Kedungrejo, Sugihwaras, Kec. Saradan, Kabupaten Madiun, Jawa Timur 63155',                          latLng: LatLng(-7.549216864149575, 111.73244749536674)),
    PuskesmasLocation(no: 14, name: 'Puskesmas Sumbersari',    address: 'Jl. Raya Tulung No.5, Sumber Sari, Sumbersari, Kec. Saradan, Kabupaten Madiun, Jawa Timur 63155',                     latLng: LatLng(-7.523589936652142, 111.69166061121169)),
    PuskesmasLocation(no: 15, name: 'Puskesmas Pilangkenceng', address: 'Jl. Raya Pilangkenceng, Kenongo, Kenongorejo, Kec. Pilangkenceng, Kabupaten Madiun, Jawa Timur 63154',            latLng: LatLng(-7.488392655191181, 111.66216279536617)),
    PuskesmasLocation(no: 16, name: 'Puskesmas Krebet',        address: 'Jl. Gawang Utara No.55, Dusun 2, Krebet, Kec. Pilangkenceng, Kabupaten Madiun, Jawa Timur 62193',                              latLng: LatLng(-7.47551834195205, 111.62764606653023)),
    PuskesmasLocation(no: 17, name: 'Puskesmas Klecorejo',     address: 'Jl. Caruban-Gemarang No.10, Klecorejo, Kec. Mejayan, Kabupaten Madiun, Jawa Timur 63153',                             latLng: LatLng(-7.572349072953643, 111.67044204005103)),
    PuskesmasLocation(no: 18, name: 'Puskesmas Mejayan',       address: 'Jl. Panglima Sudirman No.52, Kronggahan, Mejayan, Kec. Mejayan, Kabupaten Madiun, Jawa Timur 63153',                  latLng: LatLng(-7.5486550848976695, 111.6698438665309)),
    PuskesmasLocation(no: 19, name: 'Puskesmas Wonoasri',      address: 'Wonoasri 1, Wonoasri, Kec. Wonoasri, Kabupaten Madiun, Jawa Timur 63157',                           latLng: LatLng(-7.56843749244564, 111.62442676653113)),
    PuskesmasLocation(no: 20, name: 'Puskesmas Balerejo',      address: 'Jl. Raya Madiun - Surabaya No.82, Kasreman, Balerejo, Kec. Balerejo, Kabupaten Madiun, Jawa Timur 63152',              latLng: LatLng(-7.556497892457287, 111.58462499536681)),
    PuskesmasLocation(no: 21, name: 'Puskesmas Simo',          address: 'Jl. Raya Balerejo-Muneng No.96, Muneng III, Simo, Kec. Balerejo, Kabupaten Madiun, Jawa Timur 63152',                  latLng: LatLng(-7.492312992519911, 111.6025461953662)),
    PuskesmasLocation(no: 22, name: 'Puskesmas Madiun',        address: 'Jl. Puskesmas, Tiron, Kec. Madiun, Kabupaten Madiun, Jawa Timur 63151',                        latLng: LatLng(-7.58978057529557, 111.54063496480444)),
    PuskesmasLocation(no: 23, name: 'Puskesmas Dimong',        address: 'JL, Dimong, Kec. Madiun, Kabupaten Madiun, Jawa Timur 63151',                               latLng: LatLng(-7.59046005759936, 111.58875952235208)),
    PuskesmasLocation(no: 24, name: 'Puskesmas Sawahan',       address: 'Jl. Barat, RT.10/RW.05, Sumuragung, Pucangrejo, Kec. Sawahan, Kabupaten Madiun, Jawa Timur 63162',                        latLng: LatLng(-7.577157202629924, 111.52546334005143)),
    PuskesmasLocation(no: 25, name: 'Puskesmas Klagenserut',   address: 'Jl. Raya Klagenserut, Krajan, Klagenserut, Kec. Jiwan, Kabupaten Madiun, Jawa Timur 63161',                           latLng: LatLng(-7.60111298873119, 111.49565783769566)),
    PuskesmasLocation(no: 26, name: 'Puskesmas Jiwan',         address: 'Jl. Marsma TNI Anumerta R. Iswahjudi No.85, Bragak, Jiwan, Kec. Jiwan, Kabupaten Madiun, Jawa Timur 63161',                            latLng: LatLng(-7.624836126363625, 111.49374356653172)),
    PuskesmasLocation(no: 27, name: 'RSUD Caruban',            address: 'Jl. Ahmad Yani No.KM 2, Caruban, Ngampel, Kec. Mejayan, Kabupaten Madiun, Jawa Timur 63153',                 latLng: LatLng(-7.538846731514861, 111.65552549536659)),
    PuskesmasLocation(no: 28, name: 'RSUD Dolopo',             address: 'Jalan Raya Dolopo No.117, Krajan, Dolopo, Kec. Dolopo, Kabupaten Madiun, Jawa Timur 63174',                  latLng: LatLng(-7.743195513202423, 111.5294381088614)),
    PuskesmasLocation(no: 29, name: 'PSC 119 Kabupaten Madiun', address: 'Jl. Raya Surabaya-Madiun, Kel. Nglames, Kec. Madiun', latLng: LatLng(-7.594873835493414, 111.53740150468347)),
  ];

  // ═══════════════════════════════════════════════════════════════════════
  // LOKASI USER
  // ═══════════════════════════════════════════════════════════════════════
  Future<LatLng?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { print('Location services disabled'); return null; }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  Stream<LatLng> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).map((pos) => LatLng(pos.latitude, pos.longitude));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AMBULANCE — realtime dari Firestore
  // ═══════════════════════════════════════════════════════════════════════
  Stream<List<AmbulanceLocation>> getAmbulancesLocation() {
    return _firestore
        .collection('ambulances')
        .where('available', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();

              double lat = (data['latitude']  as num?)?.toDouble() ?? -7.6298;
              double lng = (data['longitude'] as num?)?.toDouble() ?? 111.5239;

              if (data['latitude'] == null) {
                lat = -7.6298 + (doc.id.hashCode % 100 - 50) / 5000;
                lng = 111.5239 + (doc.id.hashCode % 100 - 50) / 5000;
              }

              return AmbulanceLocation(
                id:          doc.id,
                plate:       data['plate'] ?? 'N/A',
                petugasName: data['petugasName'],
                petugasId:   data['petugasId'],
                status:      data['available'] == true ? 'Tersedia' : 'Tidak Tersedia',
                latLng:      LatLng(lat, lng),
                lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
              );
            }).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PETUGAS LIVE — admin melihat posisi semua petugas aktif
  // ═══════════════════════════════════════════════════════════════════════
  Stream<List<PetugasLiveLocation>> getPetugasLiveLocations() {
    return _firestore
        .collection('petugas_locations')
        .snapshots()
        .map((snap) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
      return snap.docs
          .where((doc) {
            final ts = doc.data()['updatedAt'];
            if (ts == null) return false;
            return (ts as Timestamp).toDate().isAfter(cutoff);
          })
          .map((doc) {
            final data = doc.data();
            return PetugasLiveLocation(
              uid:  doc.id,
              name: data['name'] ?? 'Petugas',
              latLng: LatLng(
                (data['latitude']  as num).toDouble(),
                (data['longitude'] as num).toDouble(),
              ),
              lastUpdated: (data['updatedAt'] as Timestamp?)?.toDate(),
            );
          })
          .toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PETUGAS — kirim lokasi ke Firestore
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> updatePetugasLocation({
    required String uid,
    required String name,
    required LatLng location,
  }) async {
    try {
      await _firestore.collection('petugas_locations').doc(uid).set({
        'uid':       uid,
        'name':      name,
        'latitude':  location.latitude,
        'longitude': location.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error update petugas location: $e');
    }
  }

  Future<void> removePetugasLocation(String uid) async {
    try {
      await _firestore.collection('petugas_locations').doc(uid).delete();
    } catch (e) {
      print('Error remove petugas location: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PUSKESMAS
  // ═══════════════════════════════════════════════════════════════════════
  List<PuskesmasLocation> getPuskesmasList() => _puskesmasList;

  // ═══════════════════════════════════════════════════════════════════════
  // UPDATE LOKASI AMBULANCE
  // ═══════════════════════════════════════════════════════════════════════
  Future<bool> updateAmbulanceLocation(String ambulanceId, LatLng location) async {
    try {
      await _firestore.collection('ambulances').doc(ambulanceId).update({
        'latitude':    location.latitude,
        'longitude':   location.longitude,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error update ambulance location: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UTILS
  // ═══════════════════════════════════════════════════════════════════════
  double calculateDistance(LatLng from, LatLng to) =>
      _distance.as(LengthUnit.Meter, from, to);

  String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String estimateTime(double meters) {
    final minutes = (meters / 1000 * 3).round();
    if (minutes < 60) return '$minutes menit';
    return '${minutes ~/ 60} jam ${minutes % 60} menit';
  }
}