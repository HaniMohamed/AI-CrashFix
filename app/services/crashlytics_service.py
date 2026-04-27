 
from google.cloud import bigquery
from app.config import BQ_PROJECT_ID, BQ_DATASET, GOOGLE_APPLICATION_CREDENTIALS

try:
    from google.oauth2 import service_account
except Exception:  # pragma: no cover
    service_account = None


class CrashlyticsService:

    def __init__(self):
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

        query = f"""
        SELECT
            event_timestamp,
            issue_id,
            exception_type,
            exception_message,
            app_info.app_version AS app_version,
            device.model AS device_model,
            platform,
            execution.exception.stack_trace AS stacktrace
        FROM `{BQ_PROJECT_ID}.{BQ_DATASET}.events_*`
        WHERE event_type = "crash"
        ORDER BY event_timestamp DESC
        LIMIT {limit}
        """

        query_job = self.client.query(query)

        crashes = []

        for row in query_job:
            crashes.append(self._map_row(row))

        return crashes

    def _map_row(self, row):
        return {
            "crash_id": row.get("issue_id"),
            "timestamp": str(row.get("event_timestamp")),
            "exception": f"{row.get('exception_type')}: {row.get('exception_message')}",
            "app_version": row.get("app_version"),
            "device": row.get("device_model"),
            "platform": row.get("platform"),
            "stacktrace": self._parse_stacktrace(row.get("stacktrace"))
        }

    def _parse_stacktrace(self, stacktrace):
        if not stacktrace:
            return []

        # Split into lines
        return [line.strip() for line in stacktrace.split("\n") if line.strip()]