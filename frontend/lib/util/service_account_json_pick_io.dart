import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'service_account_json_pick_types.dart';

Future<ServiceAccountJsonPick?> pickServiceAccountJsonFile() async {
  final pick = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (pick == null || pick.files.isEmpty) return null;
  final file = pick.files.single;
  var bytes = file.bytes;
  // Desktop pickers sometimes omit in-memory bytes even with withData: true.
  if ((bytes == null || bytes.isEmpty) && (file.path ?? '').trim().isNotEmpty) {
    try {
      bytes = await File(file.path!).readAsBytes();
    } catch (_) {
      bytes = null;
    }
  }
  if (bytes == null || bytes.isEmpty) return null;
  final name =
      file.name.trim().isEmpty ? 'credentials.json' : file.name.trim();
  return ServiceAccountJsonPick(bytes: bytes, name: name);
}
