import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/spacing.dart';
import '../../core/providers/log_viewer_provider.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/glass_card.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _scrollBackend = ScrollController();
  final _scrollLauncher = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _scrollBackend.dispose();
    _scrollLauncher.dispose();
    super.dispose();
  }

  ScrollController _controllerFor(String source) =>
      source == 'launcher' ? _scrollLauncher : _scrollBackend;

  void _scrollToEnd(String source) {
    final c = _controllerFor(source);
    if (!c.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients) return;
      c.jumpTo(c.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logs', style: theme.displaySmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Backend and launcher output from the server data directory '
            '(macOS: ~/Library/Application Support/AI Crash Fix/).',
            style: theme.bodyLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(
                icon: Icon(Icons.terminal_outlined, size: 18),
                text: 'Backend',
              ),
              Tab(
                icon: Icon(Icons.rocket_launch_outlined, size: 18),
                text: 'Launcher',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _LogPanel(
                  source: 'backend',
                  scrollController: _scrollBackend,
                  onContentUpdated: () => _scrollToEnd('backend'),
                ),
                _LogPanel(
                  source: 'launcher',
                  scrollController: _scrollLauncher,
                  onContentUpdated: () => _scrollToEnd('launcher'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends ConsumerStatefulWidget {
  final String source;
  final ScrollController scrollController;
  final VoidCallback onContentUpdated;

  const _LogPanel({
    required this.source,
    required this.scrollController,
    required this.onContentUpdated,
  });

  @override
  ConsumerState<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends ConsumerState<_LogPanel> {
  String? _lastContentLen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final log = ref.watch(logViewerProvider(widget.source));
    final notifier = ref.read(logViewerProvider(widget.source).notifier);

    if (log.followTail &&
        !log.loading &&
        log.content.length.toString() != _lastContentLen) {
      _lastContentLen = log.content.length.toString();
      widget.onContentUpdated();
    }

    // TabBarView children must expand; otherwise Column+Expanded gets zero height.
    return SizedBox.expand(
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.source == 'backend'
                              ? 'backend.log'
                              : 'launcher.log',
                          style: theme.titleMedium,
                        ),
                        if (log.path.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            log.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall?.copyWith(
                              color: palette.textMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        if (log.dataDir != null && log.dataDir!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Data dir: ${log.dataDir}',
                            style: theme.labelSmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (log.loading)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.primary,
                        ),
                      ),
                    )
                  else if (log.available) ...[
                    Text(
                      _formatSize(log.size),
                      style: theme.labelSmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: log.loading ? null : () => notifier.refresh(),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                  if (log.path.isNotEmpty)
                    IconButton(
                      tooltip: 'Copy path',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: log.path));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Path copied')),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined, size: 20),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Follow tail'),
                    selected: log.followTail,
                    onSelected: log.loading ? null : notifier.setFollowTail,
                  ),
                  FilterChip(
                    label: const Text('Auto-refresh (2s)'),
                    selected: log.autoRefresh,
                    onSelected: log.loading ? null : notifier.setAutoRefresh,
                  ),
                  if (log.truncated)
                    Chip(
                      avatar: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: palette.warning,
                      ),
                      label: Text(
                        'Showing last chunk only',
                        style: theme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _LogBody(
                  log: log,
                  scrollController: widget.scrollController,
                  onRetry: () => notifier.refresh(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _LogBody extends StatelessWidget {
  final LogViewerState log;
  final ScrollController scrollController;
  final VoidCallback onRetry;

  const _LogBody({
    required this.log,
    required this.scrollController,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface1,
        borderRadius: AppRadii.all(AppRadii.md),
        border: Border.all(color: palette.border.withValues(alpha: 0.6)),
      ),
      child: _inner(context, palette, theme),
    );
  }

  Widget _inner(BuildContext context, AppPalette palette, TextTheme theme) {
    if (log.loading && log.content.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: palette.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Loading log…',
              style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      );
    }

    if (log.message != null && log.message!.isNotEmpty && !log.available) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ErrorBanner(message: log.message!, onRetry: onRetry),
      );
    }

    if (!log.available && log.content.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            log.message ??
                'Log file is not available yet. Start the macOS app (writes backend.log and launcher.log) '
                'or rebuild the backend so GET /api/logs/* is available.',
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ),
      );
    }

    if (log.content.isEmpty) {
      return Center(
        child: Text(
          'Log file exists but is empty.',
          style: theme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
      );
    }

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SelectableText(
          log.content,
          style: theme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.45,
            color: palette.text,
          ),
        ),
      ),
    );
  }
}
