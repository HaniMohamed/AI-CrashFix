"""HTTP/streaming API layer for the AI Crash Fix pipeline.

This package wraps the existing graph/runner so a UI can:
- start a run (batch or single crash) and consume per-step events as NDJSON
- read crash records persisted by `CrashStore`

It does not change any existing pipeline behavior; the CLI script
`scripts/run_batch.py` continues to work unmodified.
"""
