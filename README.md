## ai_crashlens

Crash-to-fix pipeline scaffold (LangGraph).

### Prerequisites
- **Python**: 3.11+ recommended
- **ripgrep (`rg`)**: used by `app/graph/nodes/map_stacktrace.py`

### Configure repo root
Set `REPO_ROOT` in `.env` to the **target repository** you want to analyze (your app repo).

### Install ripgrep (macOS)
If you see `zsh: command not found: rg`, install ripgrep:

```bash
brew install ripgrep
rg --version
```

### Create and activate a virtual environment
From the repo root:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
```

### Install Python dependencies
Dependencies are listed in `requirements.txt`:

```bash
pip install -r requirements.txt
```

### Run batch
Fetch \(N\) recent crashes and process each crash through the graph:

```bash
python scripts/run_batch.py --limit 10
```

#### Useful flags
- **Mock mode (no BigQuery)**:

```bash
python scripts/run_batch.py --limit 10 --mock
```

- **Skip Jira creation** (runs analysis, but routes to `END` instead of `jira_create`):

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

### Notes
- Logging is controlled by `CRASHLENS_GRAPH_LOG_LEVEL` and `CRASHLENS_GRAPH_LOG_STYLE` (see `app/graph/observability.py`).
