from app.config import (
    BQ_PROJECT_ID,
    BQ_DATASET,
    BQ_CRASHLYTICS_ANDROID_TABLE,
    BQ_CRASHLYTICS_IOS_TABLE,
    GOOGLE_APPLICATION_CREDENTIALS,
    CRASHLYTICS_FETCH_BACKEND,
)

try:
    from google.cloud import bigquery  # type: ignore
except Exception:  # pragma: no cover
    bigquery = None

try:
    from google.cloud import logging as cloud_logging  # type: ignore
except Exception:  # pragma: no cover
    cloud_logging = None

try:
    from google.oauth2 import service_account
except Exception:  # pragma: no cover
    service_account = None


def _resolve_crashlytics_backend(raw: str) -> str:
    normalized = (raw or "bigquery").strip().lower()
    if normalized in ("cloud_logging", "logging", "gcl"):
        return "cloud_logging"
    if normalized in ("bigquery", "bq"):
        return "bigquery"
    raise ValueError(
        f"Unknown CRASHLYTICS_FETCH_BACKEND={raw!r}; use 'bigquery' or 'cloud_logging'."
    )


class CrashlyticsService:

    def __init__(self):
        self._backend = _resolve_crashlytics_backend(CRASHLYTICS_FETCH_BACKEND)
        credentials = self._load_credentials()
        self.client = None
        self._logging_client = None

        if self._backend == "bigquery":
            if bigquery is None:
                raise RuntimeError(
                    "Missing dependency for BigQuery. Install google-cloud-bigquery to enable Crashlytics fetch."
                )
            if not BQ_PROJECT_ID:
                raise RuntimeError("BQ_PROJECT_ID is required when CRASHLYTICS_FETCH_BACKEND=bigquery.")
            # If credentials is None, BigQuery will use Application Default Credentials.
            self.client = bigquery.Client(project=BQ_PROJECT_ID, credentials=credentials)
            return

        if cloud_logging is None:
            raise RuntimeError(
                "Missing dependency for Cloud Logging. Install google-cloud-logging to enable Crashlytics fetch."
            )
        if not BQ_PROJECT_ID:
            raise RuntimeError(
                "BQ_PROJECT_ID (GCP project id) is required when CRASHLYTICS_FETCH_BACKEND=cloud_logging."
            )
        self._logging_client = cloud_logging.Client(project=BQ_PROJECT_ID, credentials=credentials)

    @staticmethod
    def _load_credentials():
        """BigQuery and Cloud Logging expect a google-auth Credentials object (not a path string)."""
        if GOOGLE_APPLICATION_CREDENTIALS and service_account is not None:
            return service_account.Credentials.from_service_account_file(
                GOOGLE_APPLICATION_CREDENTIALS
            )
        return None

    def fetch_recent_crashes(self, limit=10):
        """
        Fetch latest crash events from BigQuery or Cloud Logging (see CRASHLYTICS_FETCH_BACKEND).
        """
        if self._backend == "cloud_logging":
            return self._fetch_recent_crashes_cloud_logging(limit=limit)
        return self._fetch_recent_crashes_bigquery(limit=limit)

    def _fetch_recent_crashes_bigquery(self, limit: int) -> list[dict]:
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
            AND UPPER(TRIM(t.error_type)) = 'FATAL'

          UNION ALL

          SELECT
            t.*,
            "ios" AS _source_platform
          FROM {ios_table} AS t
          WHERE t.is_fatal IS TRUE
            AND UPPER(TRIM(t.error_type)) = 'FATAL'
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

    def _fetch_recent_crashes_cloud_logging(self, limit: int) -> list[dict]:
        assert self._logging_client is not None
        project_id = BQ_PROJECT_ID
        # Firebase Crashlytics → Cloud Logging uses firebasecrashlytics.googleapis.com/events;
        # older samples may use crashlytics.googleapis.com/crash_events.
        fb = f'logName="projects/{project_id}/logs/firebasecrashlytics.googleapis.com%2Fevents"'
        legacy = f'logName="projects/{project_id}/logs/crashlytics.googleapis.com%2Fcrash_events"'
        fatal = '(jsonPayload.issue.errorType="FATAL" OR jsonPayload.errorType="FATAL")'
        filter_str = f"({fb} OR {legacy}) AND {fatal}"
        # Many consecutive log rows can be the same Crashlytics issue; fetch extra and keep one
        # row per ``jsonPayload.issue.id`` (most recent first due to order_by).
        lim = int(limit)
        max_fetch = min(max(lim * 40, lim), 1000)
        entries = self._logging_client.list_entries(
            filter_=filter_str,
            max_results=max_fetch,
            order_by="timestamp desc",
        )

        crashes: list[dict] = []
        seen_keys: set[str] = set()
        for entry in entries:
            if len(crashes) >= lim:
                break
            payload = self._logging_entry_payload_dict(entry)
            if not self._logging_payload_is_fatal_crash(payload):
                continue
            row = self._logging_payload_to_row(payload)
            if not row:
                continue
            key = self._cloud_logging_issue_group_key(payload, entry)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            crashes.append(self._map_row(row))

        return crashes

    @staticmethod
    def _cloud_logging_issue_group_key(payload: dict, entry) -> str:
        """
        Stable key for de-duplicating Cloud Logging crash rows: prefer Firebase ``issue.id``,
        else fall back to log entry identity so we do not merge unrelated events.
        """
        if isinstance(payload, dict):
            issue = payload.get("issue")
            if isinstance(issue, dict) and issue.get("id") is not None:
                sid = str(issue["id"]).strip()
                if sid:
                    return f"issue:{sid}"
        ins = getattr(entry, "insert_id", None)
        if ins:
            return f"entry:{ins}"
        ts = getattr(entry, "timestamp", None)
        return f"fallback:{ts!s}:{id(entry)}"

    @staticmethod
    def _logging_payload_is_fatal_crash(payload: dict) -> bool:
        """Only Firebase ``issue.errorType`` (or top-level ``errorType``) equal to FATAL counts as a crash."""
        if not isinstance(payload, dict):
            return False
        issue = payload.get("issue")
        if isinstance(issue, dict):
            et = issue.get("errorType") or issue.get("error_type")
            if et is None:
                return False
            return str(et).strip().upper() == "FATAL"
        et = payload.get("errorType") or payload.get("error_type")
        if et is None:
            return False
        return str(et).strip().upper() == "FATAL"

    @staticmethod
    def _logging_entry_payload_dict(entry) -> dict:
        """Resolve structured Crashlytics jsonPayload from a LogEntry."""
        payload = getattr(entry, "json_payload", None)
        if isinstance(payload, dict):
            return payload
        raw = getattr(entry, "payload", None)
        return raw if isinstance(raw, dict) else {}

    @staticmethod
    def _normalize_logging_frame_dict(frame: dict) -> dict:
        out = dict(frame)
        if "line" in out and out["line"] is not None and not isinstance(out["line"], int):
            try:
                out["line"] = int(str(out["line"]).strip())
            except (TypeError, ValueError):
                pass
        return out

    @staticmethod
    def _normalize_logging_exception_dict(exc: dict) -> dict:
        out = dict(exc)
        if out.get("exception_message") is None:
            em = out.get("exceptionMessage") or out.get("message")
            if em is not None:
                out["exception_message"] = em
        frames = out.get("frames")
        if isinstance(frames, list):
            out["frames"] = [
                CrashlyticsService._normalize_logging_frame_dict(f)
                if isinstance(f, dict)
                else f
                for f in frames
            ]
        return out

    @staticmethod
    def _normalize_logging_thread_dict(thread: dict) -> dict:
        out = dict(thread)
        if out.get("queue_name") is None and out.get("queue") is not None:
            out["queue_name"] = out["queue"]
        frames = out.get("frames")
        if isinstance(frames, list):
            out["frames"] = [
                CrashlyticsService._normalize_logging_frame_dict(f)
                if isinstance(f, dict)
                else f
                for f in frames
            ]
        return out

    @staticmethod
    def _logging_payload_to_row(payload: dict) -> dict:
        """
        Align Cloud Logging jsonPayload with the nested dict shape expected by _map_row.

        Supports Firebase Crashlytics Event JSON (camelCase, nested ``issue`` / ``version`` /
        ``operatingSystem`` / ``blameFrame``) as well as flatter BigQuery-like keys.
        """
        if not isinstance(payload, dict):
            return {}
        row = dict(payload)

        issue = row.get("issue")
        if isinstance(issue, dict):
            if row.get("issue_id") is None and issue.get("id") is not None:
                row["issue_id"] = issue["id"]
            if row.get("issue_title") is None and issue.get("title") is not None:
                row["issue_title"] = issue["title"]
            if row.get("issue_subtitle") is None and issue.get("subtitle") is not None:
                row["issue_subtitle"] = issue["subtitle"]

        if row.get("event_timestamp") is None and row.get("eventTime") is not None:
            row["event_timestamp"] = row["eventTime"]
        if row.get("received_timestamp") is None and row.get("receivedTime") is not None:
            row["received_timestamp"] = row["receivedTime"]

        aliases: list[tuple[str, str]] = [
            ("issue_id", "issueId"),
            ("issue_title", "issueTitle"),
            ("issue_subtitle", "issueSubtitle"),
            ("event_timestamp", "eventTimestamp"),
            ("received_timestamp", "receivedTimestamp"),
            ("installation_uuid", "installationUuid"),
        ]
        for snake, camel in aliases:
            if row.get(snake) is None and camel in row and row[camel] is not None:
                row[snake] = row[camel]

        if row.get("issue_id") is None and row.get("eventId") is not None:
            row["issue_id"] = str(row["eventId"])

        ver = row.get("version")
        if isinstance(ver, dict) and not row.get("application"):
            row["application"] = {
                "display_version": ver.get("displayVersion") or ver.get("display_version"),
                "build_version": ver.get("buildVersion") or ver.get("build_version"),
            }

        os_raw = row.get("operating_system") or row.get("operatingSystem")
        if isinstance(os_raw, dict) and not row.get("operating_system"):
            display_name = os_raw.get("displayName") or os_raw.get("display_name")
            if display_name:
                row["operating_system"] = {
                    "name": display_name,
                    "display_version": None,
                    "device_type": os_raw.get("device_type") or os_raw.get("deviceType"),
                    "type": os_raw.get("type") or os_raw.get("os"),
                    "modification_state": os_raw.get("modification_state")
                    or os_raw.get("modificationState"),
                }
            else:
                row["operating_system"] = {
                    "name": os_raw.get("name")
                    or os_raw.get("os")
                    or os_raw.get("type"),
                    "display_version": os_raw.get("display_version")
                    or os_raw.get("displayVersion"),
                    "device_type": os_raw.get("device_type") or os_raw.get("deviceType"),
                    "type": os_raw.get("type") or os_raw.get("os"),
                    "modification_state": os_raw.get("modification_state")
                    or os_raw.get("modificationState"),
                }

        bf = row.get("blame_frame") or row.get("blameFrame")
        if isinstance(bf, dict) and not row.get("blame_frame"):
            row["blame_frame"] = CrashlyticsService._normalize_logging_frame_dict(bf)

        ex_list = row.get("exceptions")
        if isinstance(ex_list, list):
            row["exceptions"] = [
                CrashlyticsService._normalize_logging_exception_dict(e)
                if isinstance(e, dict)
                else e
                for e in ex_list
            ]

        threads = row.get("threads")
        if isinstance(threads, list):
            row["threads"] = [
                CrashlyticsService._normalize_logging_thread_dict(t)
                if isinstance(t, dict)
                else t
                for t in threads
            ]

        if row.get("platform") and not row.get("_source_platform"):
            row["_source_platform"] = row["platform"]

        return row

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
                    "error_type": "FATAL",
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
        exception_message = (
            exc.get("exception_message") or exc.get("message") or exc.get("exceptionMessage")
        )
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