import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';

/// Inline "Check connectivity" button with loading state and result text.
class ConnectivityTestButton extends StatefulWidget {
  final Future<String> Function() onTest;
  final String label;
  final bool enabled;

  const ConnectivityTestButton({
    super.key,
    required this.onTest,
    this.label = 'Check connectivity',
    this.enabled = true,
  });

  @override
  State<ConnectivityTestButton> createState() => _ConnectivityTestButtonState();
}

class _ConnectivityTestButtonState extends State<ConnectivityTestButton> {
  bool _testing = false;
  String? _result;
  bool _ok = false;

  Future<void> _run() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final message = await widget.onTest();
      if (!mounted) return;
      setState(() {
        _ok = true;
        _result = message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _result = '$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          icon: _testing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.primary,
                  ),
                )
              : const Icon(Icons.bolt, size: 16),
          label: Text(_testing ? 'Checking…' : widget.label),
          onPressed: (!_testing && widget.enabled) ? _run : null,
        ),
        if (_result != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _result!,
            style: theme.bodySmall?.copyWith(
              color: _ok ? palette.success : palette.danger,
            ),
          ),
        ],
      ],
    );
  }
}
