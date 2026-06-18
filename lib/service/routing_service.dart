// lib/service/routing_service.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  Future<RouteResult?> getRoute(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          // Parse geometry (GeoJSON coordinates)
          final List<dynamic> coordinates =
              route['geometry']['coordinates'] as List;

          final List<LatLng> points = coordinates
              .map((coord) => LatLng(
                    (coord[1] as num).toDouble(),
                    (coord[0] as num).toDouble(),
                  ))
              .toList();

          final double distanceMeters =
              (route['distance'] as num).toDouble();
          final double durationSeconds =
              (route['duration'] as num).toDouble();

          return RouteResult(
            points: points,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
          );
        }
      }
      return null;
    } catch (e) {
      print('Error getting route: $e');
      return null;
    }
  }

  /// Format durasi dari detik ke string readable
  String formatDuration(double seconds) {
    final int minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes menit';
    } else {
      final int hours = (minutes / 60).floor();
      final int mins = minutes % 60;
      return '$hours jam $mins menit';
    }
  }

  /// Format jarak ke string readable
  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }
}

/// Model hasil routing
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}