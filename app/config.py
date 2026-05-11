import os
import sys
from pathlib import Path

from dotenv import load_dotenv


def _load_env() -> None:
    """
    Load environment variables from a .env file.

    Priority (first file found wins):
    1) AI_CRASH_FIX_ENV_FILE (explicit path)
    2) repo/dev: ./.env (workspace root / current working directory)
    """
    explicit = (os.getenv("AI_CRASH_FIX_ENV_FILE") or "").strip()
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))

    candidates.append(Path(".env"))

    for p in candidates:
        try:
            if p.is_file():
                load_dotenv(dotenv_path=str(p), override=False)
                return
        except Exception:
            continue

    # Nothing found; proceed with process env only.
    return


_load_env()

def _data_dir() -> Path | None:
    raw = (os.getenv("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if not raw:
        return None
    try:
        return Path(raw).expanduser().resolve()
    except Exception:
        return None


REPO_ROOT = os.getenv("REPO_ROOT", os.getcwd())
MAIN_BRANCH = os.getenv("MAIN_BRANCH", "main")
# Where user-provided remote repos are cloned for analysis runs.
_workspace_raw = (os.getenv("WORKSPACE_PROJECTS_DIR") or "").strip() or None
if _workspace_raw:
    WORKSPACE_PROJECTS_DIR = _workspace_raw
else:
    base = _data_dir()
    if base is not None:
        WORKSPACE_PROJECTS_DIR = str((base / "workspace_projects").resolve())
    else:
        WORKSPACE_PROJECTS_DIR = "workspace_projects"

# Optional: monorepo packages directory.
# This directory is expected to contain child package directories, each with its own `lib/`:
#   <LOCAL_PACKAGES_DIR>/<packageName>/lib/...
#
# Prefer repo-relative values, e.g.:
#   LOCAL_PACKAGES_DIR=packages
#
# Absolute paths are also accepted; if they live under REPO_ROOT, they will be normalized
# back to a repo-relative path for consistent mapping output.
_LOCAL_PACKAGES_DIR_RAW = (os.getenv("LOCAL_PACKAGES_DIR") or "").strip()
if _LOCAL_PACKAGES_DIR_RAW:
    _p = _LOCAL_PACKAGES_DIR_RAW.rstrip("/")
    if os.path.isabs(_p):
        try:
            repo_abs = os.path.abspath(REPO_ROOT)
            pkg_abs = os.path.abspath(_p)
            if os.path.commonpath([repo_abs, pkg_abs]) == repo_abs:
                _p = os.path.relpath(pkg_abs, repo_abs)
        except Exception:
            pass
    LOCAL_PACKAGES_DIR = _p
else:
    LOCAL_PACKAGES_DIR = None

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
JIRA_EMAIL = os.getenv("JIRA_EMAIL")
JIRA_ISSUE_TYPE = os.getenv("JIRA_ISSUE_TYPE", "Bug")
JIRA_VERIFY_SSL = os.getenv("JIRA_VERIFY_SSL", "true")

GITLAB_SERVER_URL = os.getenv("GITLAB_SERVER_URL")
GITLAB_PROJECT = os.getenv("GITLAB_PROJECT")  # namespace/project
GITLAB_TOKEN = os.getenv("GITLAB_TOKEN")
GITLAB_VERIFY_SSL = os.getenv("GITLAB_VERIFY_SSL", "true")
GITLAB_SSL_CA_BUNDLE = os.getenv("GITLAB_SSL_CA_BUNDLE")


AI_CRASH_FIX_GRAPH_LOG_LEVEL = os.getenv("AI_CRASH_FIX_GRAPH_LOG_LEVEL")
AI_CRASH_FIX_GRAPH_LOG_STYLE = os.getenv("AI_CRASH_FIX_GRAPH_LOG_STYLE")