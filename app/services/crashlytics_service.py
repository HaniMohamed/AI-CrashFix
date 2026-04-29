from app.config import (
    BQ_PROJECT_ID,
    BQ_DATASET,
    BQ_CRASHLYTICS_ANDROID_TABLE,
    BQ_CRASHLYTICS_IOS_TABLE,
    GOOGLE_APPLICATION_CREDENTIALS,
)

try:
    from google.cloud import bigquery  # type: ignore
except Exception:  # pragma: no cover
    bigquery = None

try:
    from google.oauth2 import service_account
except Exception:  # pragma: no cover
    service_account = None


class CrashlyticsService:

    def __init__(self):
        if bigquery is None:
            raise RuntimeError(
                "Missing dependency for BigQuery. Install google-cloud-bigquery to enable Crashlytics fetch."
            )
        # BigQuery expects a google-auth Credentials object (not a string path).
        credentials = None
        if GOOGLE_APPLICATION_CREDENTIALS and service_account is not None:
            credentials = service_account.Credentials.from_service_account_file(
                GOOGLE_APPLICATION_CREDENTIALS
            )

        # If credentials is None, BigQuery will use Application Default Credentials.
        self.client = bigquery.Client(project=BQ_PROJECT_ID, credentials=credentials)

    def fetch_recent_crashes(self, limit=10):
        """
        Fetch latest crash events from BigQuery
        """

        # Crashlytics export is split by app/platform into concrete tables.
        # We union Android + iOS into a single stream and then apply a global LIMIT.
        android_table = f"`{BQ_PROJECT_ID}.{BQ_DATASET}.{BQ_CRASHLYTICS_ANDROID_TABLE}`"
        ios_table = f"`{BQ_PROJECT_ID}.{BQ_DATASET}.{BQ_CRASHLYTICS_IOS_TABLE}`"

        query = f"""
        WITH unioned AS (
          SELECT
            t.*,
            "android" AS _source_platform
          FROM {android_table} AS t
          WHERE t.event_type = "crash"

          UNION ALL

          SELECT
            t.*,
            "ios" AS _source_platform
          FROM {ios_table} AS t
          WHERE t.event_type = "crash"
        )
        SELECT * FROM unioned
        ORDER BY event_timestamp DESC
        LIMIT {int(limit)}
        """

        query_job = self.client.query(query)

        crashes = []

        for row in query_job:
            crashes.append(self._map_row(self._row_to_dict(row)))

        return crashes

    def fetch_recent_crashes_mock_rows(self, limit: int = 10) -> list[dict]:
        """
        Return mocked Crashlytics/BigQuery-like crash "rows".

        Shape matches the example row dict used in this project (issue/application/device/exception, etc.).
        Useful for testing batch processing without BigQuery.
        """

        base_stack = (
            "#0 AIEnhanceServiceImpl.enhanceText (lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart:69:55)\n"
            "#1 VoiceWithAITextFieldController._enhance (lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart:141:18)\n"
            "#2 VoiceWithAITextFieldController.onSendPressed (lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart:102:9)\n"
            "#3 _InkResponseState._handleTap (package:flutter/src/material/ink_well.dart:1171:21)\n"
            "#4 GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:357:24)\n"
            "#5 TapGestureRecognizer.handleTapUp (package:flutter/src/gestures/tap.dart:652:11)\n"
            "#6 GestureBinding.handleEvent (package:flutter/src/gestures/binding.dart:499:19)\n"
            "#7 WidgetsBinding.drawFrame (package:flutter/src/widgets/binding.dart:1195:21)\n"
            "#8 _invoke (dart:ui/hooks.dart:324:13)\n"
            "#9 PlatformDispatcher._drawFrame (dart:ui/platform_dispatcher.dart:425:5)"
        )

        rows: list[dict] = []
        for i in range(max(0, int(limit))):
            idx = i + 1
            issue_id = f"issue_mock_{idx:04d}"

            rows.append(
                {
                    "event_timestamp": f"2026-04-28T09:12:{30 + i:02d}.123Z",
                    "event_id": f"mock-event-{idx:04d}",
                    "event_type": "crash",
                    "issue": {
                        "issue_id": issue_id,
                        "title": "TypeError: Null check operator used on a null value",
                    },
                    "application": {
                        "app_id": "sa.gov.gosi.taminaty",
                        "version": "3.2.18",
                        "build_version": "3218",
                    },
                    "device": {
                        "model": "Pixel 7",
                        "os_version": "Android 14",
                        "architecture": "arm64-v8a",
                    },
                    "platform": "android",
                    "exception": {
                        "type": "_TypeError",
                        "message": "Null check operator used on a null value",
                        "stacktrace": base_stack,
                    },
                    "threads": [
                        {
                            "name": "main",
                            "crashed": True,
                            "frames": [
                                {
                                    "symbol": "AIEnhanceServiceImpl.enhanceText",
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                                    "line": 69,
                                },
                                {
                                    "symbol": "VoiceWithAITextFieldController._enhance",
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart",
                                    "line": 141,
                                },
                                {
                                    "symbol": "VoiceWithAITextFieldController.onSendPressed",
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart",
                                    "line": 102,
                                },
                            ],
                        }
                    ],
                    "breadcrumbs": [
                        {
                            "timestamp": "2026-04-28T09:12:10Z",
                            "message": "User opened Voice with AI text field",
                        },
                        {
                            "timestamp": "2026-04-28T09:12:20Z",
                            "message": "AIEnhanceServiceImpl.enhanceText called (model=iwai-v01, SourceId=SuperApp)",
                        },
                    ],
                }
            )

        return rows

    def fetch_recent_crashes_mock(self, limit: int = 10) -> list[dict]:
        """
        Return mocked crashes in the *mapped* shape used by the graph (same as fetch_recent_crashes()).
        """

        return [self._map_row(r) for r in self.fetch_recent_crashes_mock_rows(limit=limit)]

    def _row_to_dict(self, row):
        """
        Normalize BigQuery Row (or dict-like) into a plain nested dict.
        """
        if row is None:
            return {}
        if isinstance(row, dict):
            return row
        # google.cloud.bigquery.table.Row behaves like a Mapping.
        try:
            return dict(row)
        except Exception:
            pass
        try:
            # Fall back to attribute access when available.
            return row.__dict__
        except Exception:
            return {}

    def _map_row(self, row):
        platform = row.get("platform") or row.get("_source_platform")
        return {
            "crash_id": row.get("issue").get("issue_id"),
            "timestamp": str(row.get("event_timestamp")),
            "exception": f"{row.get('exception').get('type')}: {row.get('exception').get('message')}",
            "app_version": row.get("application").get("version"),
            "device": row.get("device").get("model") + " - " + row.get("device").get("os_version") + " - " + row.get("device").get("architecture"),
            "platform": platform,
            "stacktrace": self._parse_stacktrace(row.get("exception").get("stacktrace"))
        }

    def _parse_stacktrace(self, stacktrace):
        if not stacktrace:
            return []

        # Split into lines
        return [line.strip() for line in stacktrace.split("\n") if line.strip()]