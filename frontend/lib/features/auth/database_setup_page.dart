import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/api/endpoints.dart';
import '../../core/providers/auth_provider.dart'; // baseApiClientProvider
import '../../shared/widgets/gradient_button.dart';
import '../setup/store_config_panel.dart';
import 'auth_scaffold.dart';

/// First-run database configuration — shown before administrator creation.
class DatabaseSetupPage extends ConsumerStatefulWidget {
  const DatabaseSetupPage({super.key});

  @override
  ConsumerState<DatabaseSetupPage> createState() => _DatabaseSetupPageState();
}

class _DatabaseSetupPageState extends ConsumerState<DatabaseSetupPage> {
  String _storeBackend = 'sqlite';
  final _dbUrlCtrl = TextEditingController();
  final _dbUserCtrl = TextEditingController();
  final _dbPasswordCtrl = TextEditingController();
  final _machineUserIdCtrl = TextEditingController();
  bool _showDbPassword = false;
  bool _busy = false;
  bool _bootstrapped = false;
  String? _dbUrlMasked;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _dbUrlCtrl.dispose();
    _dbUserCtrl.dispose();
    _dbPasswordCtrl.dispose();
    _machineUserIdCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final auth = ref.read(authProvider);
    if (!auth.needsStoreSetup) {
      if (mounted) context.go('/login');
      return;
    }
    await _syncStoreConfig();
    if (mounted) setState(() {});
  }

  Future<void> _syncStoreConfig() async {
    try {
      final api = ref.read(baseApiClientProvider);
      final res = await api.getJson(Endpoints.setupStore);
      final cfg = (res as Map).cast<String, dynamic>();
      final backend = (cfg['backend'] ?? 'sqlite').toString().toLowerCase();
      _storeBackend = backend == 'postgres' ? 'postgres' : 'sqlite';
      _dbUrlMasked = cfg['db_url_masked']?.toString();
      final uid = cfg['user_id']?.toString() ?? '';
      if (uid.isNotEmpty) _machineUserIdCtrl.text = uid;
      if (_dbUrlCtrl.text.trim().isEmpty &&
          _dbUrlMasked != null &&
          !_dbUrlMasked!.contains('***')) {
        _dbUrlCtrl.text = _dbUrlMasked!;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_storeBackend == 'postgres') {
        final url = _dbUrlCtrl.text.trim();
        if (url.isEmpty && (_dbUrlMasked == null || _dbUrlMasked!.isEmpty)) {
          throw Exception('Postgres URL is required');
        }
        if (_machineUserIdCtrl.text.trim().isEmpty) {
          throw Exception('Machine user ID is required for remote Postgres');
        }
      }
      final api = ref.read(baseApiClientProvider);
      final body = <String, dynamic>{
        'backend': _storeBackend,
        'test_connection': _storeBackend == 'postgres',
        if (_dbUrlCtrl.text.trim().isNotEmpty) 'db_url': _dbUrlCtrl.text.trim(),
        if (_dbUserCtrl.text.trim().isNotEmpty) 'username': _dbUserCtrl.text.trim(),
        if (_dbPasswordCtrl.text.isNotEmpty) 'password': _dbPasswordCtrl.text,
        if (_machineUserIdCtrl.text.trim().isNotEmpty)
          'user_id': _machineUserIdCtrl.text.trim(),
      };
      await api.postJson(Endpoints.setupStore, body: body);
      await ref.read(authProvider.notifier).refreshBootstrapStatus();
      _dbPasswordCtrl.clear();
      if (!mounted) return;
      setState(() {
        _info = _storeBackend == 'sqlite'
            ? 'Local SQLite store saved. Continue to create your administrator account.'
            : 'Remote Postgres connected. Continue to create your administrator account.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);

    if (auth.initialized && !auth.needsStoreSetup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
    }

    return AuthScaffold(
      maxWidth: 520,
      title: 'Choose your database',
      subtitle:
          'First step: where $kProductName stores application data. Next you’ll create an administrator.',
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!auth.initialized)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            StoreConfigPanel(
              storeBackend: _storeBackend,
              onBackendChanged: (b) => setState(() => _storeBackend = b),
              dbUrlCtrl: _dbUrlCtrl,
              dbUserCtrl: _dbUserCtrl,
              dbPasswordCtrl: _dbPasswordCtrl,
              machineUserIdCtrl: _machineUserIdCtrl,
              showDbPassword: _showDbPassword,
              onToggleDbPassword: () =>
                  setState(() => _showDbPassword = !_showDbPassword),
              dbUrlMasked: _dbUrlMasked,
              busy: _busy,
            ),
            if (_info != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_info!, style: theme.bodySmall?.copyWith(color: palette.success)),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
            ],
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: _busy
                  ? 'Saving…'
                  : (_storeBackend == 'postgres'
                      ? 'Test connection & continue'
                      : 'Continue'),
              icon: Icons.arrow_forward_rounded,
              onPressed: _busy ? null : _save,
            ),
          ],
        ],
      ),
    );
  }
}
