import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import 'auth_scaffold.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _bootstrapUsernameCtrl = TextEditingController();
  final _tenantIdCtrl = TextEditingController();
  bool _obscure = true;
  /// 0 = sign in, 1 = create admin
  int _mode = 0;
  String? _tempPassword;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _bootstrapUsernameCtrl.dispose();
    _tenantIdCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillTenant());
  }

  Future<void> _prefillTenant() async {
    try {
      final health = ref.read(healthProvider).valueOrNull;
      final uid = health?.userId;
      if (uid != null && uid.isNotEmpty && _tenantIdCtrl.text.isEmpty) {
        _tenantIdCtrl.text = uid;
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    final ok = await ref.read(authProvider.notifier).login(
          _usernameCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (!ok || !mounted) return;
    final auth = ref.read(authProvider);
    if (auth.user?.mustChangePassword == true) {
      context.go('/change-password');
    } else {
      context.go('/');
    }
  }

  Future<void> _bootstrap() async {
    final temp = await ref.read(authProvider.notifier).bootstrapAdmin(
          username: _bootstrapUsernameCtrl.text.trim(),
          tenantUserId: _tenantIdCtrl.text.trim().isEmpty
              ? null
              : _tenantIdCtrl.text.trim(),
        );
    if (!mounted) return;
    if (temp != null) {
      setState(() {
        _tempPassword = temp;
        _usernameCtrl.text = _bootstrapUsernameCtrl.text.trim();
        _passwordCtrl.text = temp;
        _mode = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated && !auth.user!.mustChangePassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
    }

    if (auth.initialized && auth.needsStoreSetup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.mounted) return;
        final path = GoRouterState.of(context).uri.path;
        if (path != '/setup/database') context.go('/setup/database');
      });
    }

    final creatingAdmin = auth.needsAdmin && _mode == 1;

    return AuthScaffold(
      title: creatingAdmin ? 'Create administrator' : 'Welcome back',
      subtitle: creatingAdmin
          ? 'Create the first admin account. You’ll get a temporary password, then set a new one.'
          : 'Sign in to $kProductName to turn crashes into fixes.',
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.loading && !auth.initialized)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (creatingAdmin) ...[
            TextField(
              controller: _bootstrapUsernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Admin username',
                hintText: 'e.g. admin',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _tenantIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Machine user ID (optional)',
                helperText:
                    'Scopes repos/settings — pre-filled from existing install if set.',
              ),
            ),
            if (auth.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(auth.error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
            ],
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: auth.loading ? 'Creating…' : 'Create administrator',
              onPressed: auth.loading ? null : _bootstrap,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => setState(() => _mode = 0),
              child: const Text('Back to sign in'),
            ),
          ] else ...[
            if (auth.needsAdmin) ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Sign in'), icon: Icon(Icons.login, size: 16)),
                  ButtonSegment(
                    value: 1,
                    label: Text('Create admin'),
                    icon: Icon(Icons.person_add_alt_1_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No administrator exists yet. Switch to Create admin to get started.',
                style: theme.bodySmall?.copyWith(color: palette.warning),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            TextField(
              controller: _usernameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _login(),
            ),
            if (_tempPassword != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Temporary password (copy now — it will not be shown again):',
                style: theme.bodySmall?.copyWith(color: palette.success),
              ),
              SelectableText(
                _tempPassword!,
                style: theme.titleMedium?.copyWith(color: palette.primary),
              ),
            ],
            if (auth.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(auth.error!, style: theme.bodySmall?.copyWith(color: palette.danger)),
            ],
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: auth.loading ? 'Signing in…' : 'Sign in',
              icon: Icons.arrow_forward_rounded,
              onPressed: auth.loading ? null : _login,
            ),
          ],
        ],
      ),
    );
  }
}
