import 'dart:typed_data';

/// Result of choosing a GCP service account key JSON file.
class ServiceAccountJsonPick {
  final Uint8List bytes;
  final String name;

  ServiceAccountJsonPick({required this.bytes, required this.name});
}
