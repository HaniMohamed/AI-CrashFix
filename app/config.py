import os
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env", override=False)

REPO_ROOT = os.getenv("REPO_ROOT", os.getcwd())

LLM_PROVIDER = os.getenv("LLM_PROVIDER", "gemini")  # or "openai"

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_URL = os.getenv("OPENAI_URL", "https://api.openai.com/v1")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")


GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
BQ_PROJECT_ID = os.getenv("BQ_PROJECT_ID")
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


CRASHLENS_GRAPH_LOG_LEVEL = os.getenv("CRASHLENS_GRAPH_LOG_LEVEL", "INFO")
CRASHLENS_GRAPH_LOG_STYLE = os.getenv("CRASHLENS_GRAPH_LOG_STYLE", "pretty")