import os
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env", override=False)

REPO_ROOT = os.getenv("REPO_ROOT", os.getcwd())
MAIN_BRANCH = os.getenv("MAIN_BRANCH", "main")

LLM_PROVIDER = os.getenv("LLM_PROVIDER", "gemini")  # or "openai"

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_URL = os.getenv("OPENAI_URL", "https://api.openai.com/v1")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")


GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
BQ_PROJECT_ID = os.getenv("BQ_PROJECT_ID")
# Firebase Console deep links (defaults to the same GCP project as BigQuery).
FIREBASE_CONSOLE_PROJECT_ID = (os.getenv("FIREBASE_CONSOLE_PROJECT_ID") or "").strip() or BQ_PROJECT_ID
# Fallback bundle / package when the Crashlytics export row has no application identifier.
CRASHLYTICS_ANDROID_PACKAGE_DEFAULT = (os.getenv("CRASHLYTICS_ANDROID_PACKAGE") or "").strip() or None
CRASHLYTICS_IOS_BUNDLE_ID_DEFAULT = (os.getenv("CRASHLYTICS_IOS_BUNDLE_ID") or "").strip() or None
# Crashlytics crash source: "bigquery" (exported tables) or "cloud_logging" (Crashlytics log router).
CRASHLYTICS_FETCH_BACKEND = os.getenv("CRASHLYTICS_FETCH_BACKEND", "bigquery").strip().lower()
BQ_DATASET = os.getenv("BQ_DATASET", "firebase_crashlytics")

# Crashlytics export tables (within BQ_DATASET). Keep defaults aligned with current Firebase export.
BQ_CRASHLYTICS_ANDROID_TABLE = os.getenv(
    "BQ_CRASHLYTICS_ANDROID_TABLE", "sa_gov_gosi_taminaty_ANDROID"
)
BQ_CRASHLYTICS_IOS_TABLE = os.getenv(
    "BQ_CRASHLYTICS_IOS_TABLE", "sa_gov_gosi_taminaty_IOS"
)


JIRA_SERVER_URL = os.getenv("JIRA_SERVER_URL")
JIRA_PROJECT_KEY = os.getenv("JIRA_PROJECT_KEY")
JIRA_TOKEN = os.getenv("JIRA_TOKEN")
JIRA_VERIFY_SSL = os.getenv("JIRA_VERIFY_SSL", "true")

GITLAB_SERVER_URL = os.getenv("GITLAB_SERVER_URL")
GITLAB_PROJECT = os.getenv("GITLAB_PROJECT")  # namespace/project
GITLAB_TOKEN = os.getenv("GITLAB_TOKEN")
GITLAB_VERIFY_SSL = os.getenv("GITLAB_VERIFY_SSL", "true")
GITLAB_SSL_CA_BUNDLE = os.getenv("GITLAB_SSL_CA_BUNDLE")


AI_CRASH_FIX_GRAPH_LOG_LEVEL = os.getenv("AI_CRASH_FIX_GRAPH_LOG_LEVEL")
AI_CRASH_FIX_GRAPH_LOG_STYLE = os.getenv("AI_CRASH_FIX_GRAPH_LOG_STYLE")