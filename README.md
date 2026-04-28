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

### Debug in Cursor / VS Code
Use the included launch config in `.vscode/launch.json`:
- Update your launch config to run `scripts/run_batch.py` (or run it from the terminal as above).

### Notes
- `.env` exists at the repo root but integrations are not wired yet in this scaffold.
