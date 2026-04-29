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
          WHERE t.is_fatal IS TRUE

          UNION ALL

          SELECT
            t.*,
            "ios" AS _source_platform
          FROM {ios_table} AS t
          WHERE t.is_fatal IS TRUE
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

        Shape matches the current Crashlytics BigQuery schema used by this project.
        Useful for testing batch processing without BigQuery.
        """

        rows: list[dict] = []
        for i in range(max(0, int(limit))):
            idx = i + 1
            issue_id = f"issue_mock_{idx:04d}"

            rows.append(
                {
                    "platform": "android",
                    "bundle_identifier": "sa.gov.gosi.taminaty",
                    "event_id": f"mock-event-{idx:04d}",
                    "is_fatal": True,
                    "error_type": "crash",
                    "issue_id": issue_id,
                    "variant_id": "variant_mock",
                    "issue_title": "TypeError: Null check operator used on a null value",
                    "issue_subtitle": "Null check operator used on a null value",
                    "event_timestamp": f"2026-04-28T09:12:{30 + i:02d}.123Z",
                    "received_timestamp": f"2026-04-28T09:12:{35 + i:02d}.456Z",
                    "device": {
                        "manufacturer": "Google",
                        "model": "Pixel 7",
                        "architecture": "arm64-v8a",
                    },
                    "memory": {"used": 123_456_789, "free": 987_654_321},
                    "storage": {"used": 1_234_567_890, "free": 9_876_543_210},
                    "operating_system": {
                        "display_version": "14",
                        "name": "Android",
                        "modification_state": "unknown",
                        "type": "android",
                        "device_type": "phone",
                    },
                    "application": {"build_version": "3218", "display_version": "3.2.18"},
                    "user": {"name": None, "email": None, "id": f"user_mock_{idx:04d}"},
                    "custom_keys": [{"key": "SourceId", "value": "SuperApp"}],
                    "installation_uuid": f"install_mock_{idx:04d}",
                    "crashlytics_sdk_version": "18.6.0",
                    "app_orientation": "portrait",
                    "device_orientation": "portrait",
                    "process_state": "foreground",
                    "logs": [
                        {
                            "timestamp": "2026-04-28T09:12:19Z",
                            "message": "AIEnhanceServiceImpl.enhanceText called (model=iwai-v01)",
                        }
                    ],
                    "breadcrumbs": [
                        {
                            "timestamp": "2026-04-28T09:12:10Z",
                            "name": "ui_event",
                            "params": [{"key": "message", "value": "User opened Voice with AI text field"}],
                        },
                        {
                            "timestamp": "2026-04-28T09:12:20Z",
                            "name": "log",
                            "params": [
                                {
                                    "key": "message",
                                    "value": "AIEnhanceServiceImpl.enhanceText called (model=iwai-v01, SourceId=SuperApp)",
                                }
                            ],
                        },
                    ],
                    "files": [],
                    "blame_frame": {
                        "line": 69,
                        "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                        "symbol": "AIEnhanceServiceImpl.enhanceText",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": True,
                    },
                    "exceptions": [
                        {
                            "type": "_TypeError",
                            "exception_message": "Null check operator used on a null value",
                            "nested": False,
                            "title": "TypeError",
                            "subtitle": "Null check operator used on a null value",
                            "blamed": True,
                            "frames": [
                                {
                                    "line": 69,
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                                    "symbol": "AIEnhanceServiceImpl.enhanceText",
                                    "offset": 0,
                                    "address": 0,
                                    "library": "app",
                                    "owner": "app",
                                    "blamed": True,
                                },
                                {
                                    "line": 141,
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart",
                                    "symbol": "VoiceWithAITextFieldController._enhance",
                                    "offset": 0,
                                    "address": 0,
                                    "library": "app",
                                    "owner": "app",
                                    "blamed": False,
                                },
                            ],
                        }
                    ],
                    "errors": [],
                    "threads": [
                        {
                            "crashed": True,
                            "thread_name": "main",
                            "queue_name": "main",
                            "signal_name": None,
                            "signal_code": None,
                            "crash_address": None,
                            "title": "main",
                            "subtitle": None,
                            "blamed": True,
                            "frames": [
                                {
                                    "line": 69,
                                    "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                                    "symbol": "AIEnhanceServiceImpl.enhanceText",
                                    "offset": 0,
                                    "address": 0,
                                    "library": "app",
                                    "owner": "app",
                                    "blamed": True,
                                }
                            ],
                        }
                    ],
                    "unity_metadata": None,
                    "native_crash_info": None,
                    "remote_config_feature_rollouts": [],
                    "firebase_session_id": f"session_mock_{idx:04d}",
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
        issue_id = row.get("issue_id") or row.get("issueId")
        issue_title = row.get("issue_title") or row.get("issueTitle")
        issue_subtitle = row.get("issue_subtitle") or row.get("issueSubtitle")

        exc = self._first_exception(row)
        exception_type = exc.get("type")
        exception_message = exc.get("exception_message") or exc.get("message")
        exception_str = self._format_exception(exception_type, exception_message, issue_title, issue_subtitle)

        app = row.get("application") or {}
        device = row.get("device") or {}
        os = row.get("operating_system") or {}
        return {
            "crash_id": issue_id,
            "timestamp": str(row.get("event_timestamp")),
            "exception": exception_str,
            "app_version": app.get("display_version") or app.get("build_version"),
            "device": self._format_device(device=device, operating_system=os),
            "platform": platform,
            "stacktrace": self._frames_to_stacktrace(self._preferred_frames(row, exc))
        }

    def _first_exception(self, row: dict) -> dict:
        exceptions = row.get("exceptions") or []
        if isinstance(exceptions, list) and exceptions:
            first = exceptions[0]
            if isinstance(first, dict):
                return first
        return {}

    def _format_exception(
        self,
        exception_type: str | None,
        exception_message: str | None,
        issue_title: str | None,
        issue_subtitle: str | None,
    ) -> str:
        # Prefer explicit exception info; fall back to issue title/subtitle when Crashlytics didn't export exception fields.
        if exception_type and exception_message:
            return f"{exception_type}: {exception_message}"
        if exception_type:
            return str(exception_type)
        if issue_title and issue_subtitle and issue_subtitle not in issue_title:
            return f"{issue_title}: {issue_subtitle}"
        return str(issue_title or issue_subtitle or "Unknown exception")

    def _format_device(self, device: dict, operating_system: dict) -> str:
        parts: list[str] = []
        manufacturer = device.get("manufacturer")
        model = device.get("model")
        architecture = device.get("architecture")
        os_name = operating_system.get("name")
        os_display = operating_system.get("display_version")

        if manufacturer and model:
            parts.append(f"{manufacturer} {model}")
        elif model:
            parts.append(str(model))
        if os_name or os_display:
            parts.append(" ".join([str(p) for p in [os_name, os_display] if p]))
        if architecture:
            parts.append(str(architecture))
        return " - ".join(parts) if parts else "Unknown device"

    def _preferred_frames(self, row: dict, exc: dict) -> list[dict]:
        # Order of preference:
        # 1) Exception frames
        # 2) Blame frame (single)
        # 3) Crashed thread frames
        frames = exc.get("frames")
        if isinstance(frames, list) and frames:
            return [f for f in frames if isinstance(f, dict)]

        blame = row.get("blame_frame")
        if isinstance(blame, dict) and blame:
            return [blame]

        threads = row.get("threads") or []
        if isinstance(threads, list):
            for t in threads:
                if not isinstance(t, dict):
                    continue
                if t.get("crashed") is True:
                    t_frames = t.get("frames")
                    if isinstance(t_frames, list) and t_frames:
                        return [f for f in t_frames if isinstance(f, dict)]

        return []

    def _frames_to_stacktrace(self, frames: list[dict]) -> list[str]:
        lines: list[str] = []
        for idx, f in enumerate(frames):
            symbol = f.get("symbol")
            file = f.get("file")
            line = f.get("line")
            location = ""
            if file and line is not None:
                location = f"{file}:{line}"
            elif file:
                location = str(file)

            if symbol and location:
                lines.append(f"#{idx} {symbol} ({location})")
            elif symbol:
                lines.append(f"#{idx} {symbol}")
            elif location:
                lines.append(f"#{idx} ({location})")
        return lines