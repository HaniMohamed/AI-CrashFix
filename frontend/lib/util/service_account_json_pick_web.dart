import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'service_account_json_pick_types.dart';

/// WebKit (Safari) ignores [HTMLInputElement.click] on inputs with `display:none`.
/// The `file_picker` package also removes the input from the DOM immediately after
/// `click()`, which can prevent the chooser from appearing. This path keeps a
/// minimally "visible" off-screen input attached until the user picks or cancels.
Future<ServiceAccountJsonPick?> pickServiceAccountJsonFile() async {
  final completer = Completer<ServiceAccountJsonPick?>();
  var changeReceived = false;

  void complete(ServiceAccountJsonPick? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
  }

  final input = HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json'
    ..multiple = false;

  final style = input.style;
  style.setProperty('position', 'fixed');
  style.setProperty('left', '-9999px');
  style.setProperty('top', '0');
  style.setProperty('width', '1px');
  style.setProperty('height', '1px');
  style.setProperty('opacity', '0.01');
  style.setProperty('pointer-events', 'none');

  Timer? cancelTimer;

  void disposeInput() {
    input.remove();
  }

  late final EventListener changeListener;
  late final EventListener focusListener;

  void onChange(Event _) {
    changeReceived = true;
    cancelTimer?.cancel();
    window.removeEventListener('focus', focusListener);
    input.removeEventListener('change', changeListener);

    final files = input.files;
    if (files == null || files.length == 0) {
      disposeInput();
      complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      disposeInput();
      complete(null);
      return;
    }

    final reader = FileReader();

    late final EventListener loadEndListener;
    void onLoadEnd(Event _) {
      reader.removeEventListener('loadend', loadEndListener);
      disposeInput();
      final raw = reader.result;
      if (raw == null || !raw.isA<JSArrayBuffer>()) {
        complete(null);
        return;
      }
      final bytes = (raw as JSArrayBuffer).toDart.asUint8List();
      if (bytes.isEmpty) {
        complete(null);
        return;
      }
      final name =
          file.name.trim().isEmpty ? 'credentials.json' : file.name.trim();
      complete(ServiceAccountJsonPick(bytes: bytes, name: name));
    }

    loadEndListener = onLoadEnd.toJS;
    reader.addEventListener('loadend', loadEndListener);
    reader.readAsArrayBuffer(file);
  }

  void onFocus(Event _) {
    window.removeEventListener('focus', focusListener);
    cancelTimer = Timer(const Duration(seconds: 1), () {
      if (changeReceived) return;
      input.removeEventListener('change', changeListener);
      disposeInput();
      complete(null);
    });
  }

  changeListener = onChange.toJS;
  focusListener = onFocus.toJS;

  input.addEventListener('change', changeListener);
  window.addEventListener('focus', focusListener);

  document.querySelector('body')!.appendChild(input);
  input.click();

  return completer.future;
}
