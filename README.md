## ai_crashlens

Crash-to-Jira-to-PR pipeline built with LangGraph.

Given recent Crashlytics crashes, CrashLens:
- maps stack frames to repo locations
- pulls targeted repo context and recent git history
- asks an LLM for a **minimal unified-diff fix**
- reviews + validates the fix (with bounded retries)
- (optionally) creates a **Jira issue**
- (best effort) creates a **draft GitLab merge request** by applying the diff, committing, pushing, and opening an MR

### What you get (per crash)
- **Jira issue id**: `state["jira_issue_id"]` (skipped in `--skip-jira-creation` or `--mock` Jira)
- **Fix patch**: `state["final_fix"]` (unified diff)
- **Git branch**: `state["pr_branch"]` (if PR creation ran)
- **Merge request URL**: `state["pr_url"]` (if PR creation succeeded)
- **Local crash store**: SQLite db under `db/` (see `app/services/crash_store.py`)

### Prerequisites
- **Python**: 3.11+ recommended
- **ripgrep (`rg`)**: used for code search during stacktrace mapping/context retrieval
- **git**: required if you enable PR generation

### Install ripgrep (macOS)

```bash
brew install ripgrep
rg --version
```

### Setup

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### Configuration (.env)
CrashLens loads environment variables from `.env` (see `app/config.py`).

#### Required: target repo
- **REPO_ROOT**: absolute path to the **target repository** CrashLens will read/apply patches to
- **MAIN_BRANCH**: base branch for feature branches (default: `main`)

#### LLM provider
- **LLM_PROVIDER**: `gemini` (default) or `openai`
- **GOOGLE_API_KEY** + **GEMINI_MODEL** (default model: `gemini-2.5-flash`)
- **OPENAI_API_KEY** + **OPENAI_MODEL** (default model: `gpt-4o-mini`) + **OPENAI_URL** (optional)

#### Crashlytics (BigQuery)
Used when you run without `--mock`.
- **GOOGLE_APPLICATION_CREDENTIALS**: path to GCP service account json
- **BQ_PROJECT_ID**
- **BQ_DATASET** (default: `firebase_crashlytics`)
- **BQ_CRASHLYTICS_ANDROID_TABLE** / **BQ_CRASHLYTICS_IOS_TABLE**: table names within `BQ_DATASET`

#### Jira (optional)
If you don’t pass `--skip-jira-creation`, the graph creates a Jira issue before generating a PR.
- **JIRA_SERVER_URL**
- **JIRA_PROJECT_KEY**
- **JIRA_TOKEN**
- **JIRA_VERIFY_SSL** (default: `true`)

#### GitLab merge requests (optional, requires Jira id)
PR generation is best-effort and will be skipped if `jira_issue_id` is missing.
- **GITLAB_SERVER_URL**
- **GITLAB_PROJECT**: `namespace/project`
- **GITLAB_TOKEN**
- **GITLAB_VERIFY_SSL** (default: `true`)
- **GITLAB_SSL_CA_BUNDLE** (optional, for custom CAs)

### How it works (high level)
Main graph (`app/graph/graph_builder.py`):
`map_stacktrace → repo_context → git_regression → llm_analysis → (jira_create?) → fix_generation → END`

Fix-generation subgraph (`app/graph/fix_generation_graph/fix_generation_graph.py`):
`generate_fix → review_fix → validate_fix → (retry up to fix_max_iterations) → finalize_fix → generate_pr → END`

### Run batch
Fetch \(N\) recent crashes and process each crash through the graph.

```bash
python scripts/run_batch.py --limit 10
```

#### Useful flags
- **Mock mode (no BigQuery)**:

```bash
python scripts/run_batch.py --limit 10 --mock
```

- **Skip Jira creation** (runs analysis and fix generation, but does not create a Jira issue):

```bash
python scripts/run_batch.py --limit 10 --mock --skip-jira-creation
```

- **Print final state per crash**:

```bash
python scripts/run_batch.py --limit 3 --mock --skip-jira-creation --print-results
```

### Debug in Cursor / VS Code
Use the included launch config in `.vscode/launch.json`:
- **Debug run_batch**: runs `scripts/run_batch.py` from the workspace root.
- **Debug cron_runner**: runs `scripts/cron_runner.py` (which calls the batch runner).

### Troubleshooting
- **`rg` not found**: install ripgrep (see above).
- **“Missing …” errors**: verify `.env` values listed above (LLM provider keys, `REPO_ROOT`, BigQuery/Jira/GitLab as needed).
- **PR generation skipped**: `generate_pr` requires both a `final_fix` (unified diff) and a `jira_issue_id`. If Jira is skipped, PR creation will be skipped too.
- **“Failed to apply diff via git apply”**: the generated patch didn’t apply cleanly to `REPO_ROOT`. Try re-running after ensuring the target repo is on the expected base branch and clean.
- **No working tree changes after apply**: the diff applied but resulted in no net changes; CrashLens treats that as an error to avoid empty commits.

### Notes
- Logging is controlled by `CRASHLENS_GRAPH_LOG_LEVEL` and `CRASHLENS_GRAPH_LOG_STYLE` (see `app/graph/observability.py`).
