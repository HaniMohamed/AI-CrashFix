# AI Crash Fix - Web UI

A Flutter Web app that wraps the AI Crash Fix HTTP API. It is a dashboard,
crash explorer, run launcher, live NDJSON consumer, and read-only settings
viewer all in one.

```
frontend/
  pubspec.yaml
  web/
    index.html              boot loader (centered ring on dark gradient) + Flutter bootstrap
    manifest.json
  lib/
    main.dart               entry point: ProviderScope(AiCrashFixApp)
    app/
      app.dart              MaterialApp.router with light + dark themes
      app_settings.dart     Riverpod-backed settings (API base URL, theme mode) persisted via SharedPreferences
      router.dart           go_router routes wrapped in AppShell
      theme/
        app_theme.dart      light + dark ThemeData with custom AppPalette ThemeExtension
        colors.dart         palette tokens
        typography.dart     Manrope / Inter / JetBrains Mono scales
        spacing.dart        AppSpacing + AppRadii tokens
    core/
      api/
        api_client.dart     http.Client wrapper (FetchClient on web for streaming)
        endpoints.dart      const route paths
        ndjson_client.dart  Stream<Map<String,dynamic>> from a streaming POST
      models/
        crash.dart, analytics.dart, config_view.dart,
        run_request.dart, run_event.dart (sealed)
      providers/
        api_provider.dart, health_provider.dart, analytics_provider.dart,
        crashes_provider.dart, config_provider.dart, run_session_provider.dart
      utils/format.dart     compact ints, percent, duration, relative time
    features/
      shell/                sidebar, topbar (health pill, base-url popover, theme toggle), responsive AppShell
      dashboard/            hero header + KPI strip + funnel + charts + recent activity
      crashes/              paged list with filters; detail with overview / pipeline / state JSON / stacktrace tabs
      runs/                 new-run form (every flag from POST /api/runs) and live NDJSON consumer with per-crash timeline
      settings/             read-only config sections + connection card + Test connection
    shared/widgets/         GlassCard, GradientButton, StatusPill, PipelineStrip, EmptyState, LoadingShimmer, ErrorBanner, CopyableText
```

## Design language

Dark-mode-first; light mirror.

| Role        | Token                                   |
| ----------- | --------------------------------------- |
| `bg`        | `#0A0E1A`                               |
| `surface1`  | `#0F1525`                               |
| `surface2`  | `#171F36` (linear gradient on cards)    |
| `border`    | `#1F2A4A`                               |
| `primary`   | `#6366F1` → `#8B5CF6` (brand gradient)  |
| `secondary` | `#22D3EE`                               |
| `success`   | `#10B981`                               |
| `warning`   | `#F59E0B`                               |
| `danger`    | `#EF4444`                               |
| `text`      | `#E5E7EB` / `#94A3B8` / `#64748B`       |

Numbers use Manrope 700 with tabular figures; body uses Inter; mono uses
JetBrains Mono. Cards animate in with `flutter_animate`; KPIs count up with
`animated_flip_counter`; charts use `fl_chart` with a 600 ms swap animation.

Tokens are read through `context.palette` (an `AppPalette` extension on
`ThemeData`). Don't hard-code hex values inside features — add them to
`lib/app/theme/colors.dart` and surface them on `AppPalette`.

## Run

```bash
flutter pub get
flutter run -d chrome --web-port 5173 \
  --dart-define=API_BASE_URL=http://localhost:8000
```

The base URL is also editable in the topbar popover and on the Settings page;
both are persisted to `localStorage` so subsequent loads remember it.

## Build

```bash
flutter build web --release
# Output: build/web/
```

## How to add a new page

1. Create a `lib/features/<name>/<name>_page.dart` (a `ConsumerWidget` /
   `ConsumerStatefulWidget` from `flutter_riverpod`).
2. Add the route in `lib/app/router.dart` (it will be wrapped in `AppShell`
   automatically by the surrounding `ShellRoute`).
3. If the page needs new sidebar entries, append to `sidebarItems` in
   `lib/features/shell/sidebar.dart`.
4. Reuse the shared widgets (`GlassCard`, `GradientButton`, `StatusPill`,
   `LoadingShimmer`, `EmptyState`, `ErrorBanner`) so new screens match the
   rest of the design system.

## Backend contract

The frontend never imports backend Python; it only uses these endpoints:

- `GET  /api/health`
- `GET  /api/analytics`
- `GET  /api/config`
- `GET  /api/crashes` (paged)
- `GET  /api/crashes/{id}`
- `POST /api/runs` (NDJSON stream)

See the root `README.md` for full request / response shapes. Sealed
`RunEvent` types in `lib/core/models/run_event.dart` mirror the NDJSON event
schema documented there.
