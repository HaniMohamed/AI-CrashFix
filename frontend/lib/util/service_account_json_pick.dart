import 'service_account_json_pick_types.dart';
import 'service_account_json_pick_io.dart'
    if (dart.library.html) 'service_account_json_pick_web.dart' as impl;

export 'service_account_json_pick_types.dart';

Future<ServiceAccountJsonPick?> pickServiceAccountJsonFile() =>
    impl.pickServiceAccountJsonFile();
