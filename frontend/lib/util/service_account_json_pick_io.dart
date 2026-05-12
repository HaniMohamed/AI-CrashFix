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
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  final name =
      file.name.trim().isEmpty ? 'credentials.json' : file.name.trim();
  return ServiceAccountJsonPick(bytes: bytes, name: name);
}
