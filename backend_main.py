from __future__ import annotations

import argparse
import os
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="AI Crash Fix backend (FastAPI) for desktop bundling.")
    parser.add_argument("--host", default=os.environ.get("AI_CRASH_FIX_HOST", "127.0.0.1"))
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("AI_CRASH_FIX_PORT", "8000")),
        help="Local HTTP port to bind (default: 8000).",
    )
    parser.add_argument("--log-level", default=os.environ.get("AI_CRASH_FIX_LOG_LEVEL", "info"))
    parser.add_argument(
        "--crash-store-backend",
        default=os.environ.get("AI_CRASH_FIX_CRASH_STORE_BACKEND"),
        help="Crash store backend: sqlite (default) or postgres.",
    )
    parser.add_argument(
        "--crash-db-url",
        default=os.environ.get("AI_CRASH_FIX_CRASH_DB_URL"),
        help="Postgres URL when --crash-store-backend=postgres.",
    )
    args = parser.parse_args(argv)

    if args.crash_store_backend:
        backend = str(args.crash_store_backend).strip().lower()
        if backend not in {"sqlite", "postgres"}:
            parser.error("--crash-store-backend must be 'sqlite' or 'postgres'")
        os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = backend
    if args.crash_db_url:
        os.environ["AI_CRASH_FIX_CRASH_DB_URL"] = str(args.crash_db_url)

    # Import late so PyInstaller collects only what it needs.
    import uvicorn  # noqa: WPS433

    uvicorn.run(
        "app.api.server:app",
        host=args.host,
        port=int(args.port),
        log_level=str(args.log_level),
        reload=False,
        access_log=False,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
