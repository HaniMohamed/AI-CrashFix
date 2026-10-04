from __future__ import annotations

import argparse
import os
import sys
import threading
import time


def _set_process_title() -> None:
    """Prefer a Fixora-branded name in Activity Monitor / ps when possible."""
    title = "Fixora Backend"
    try:
        import setproctitle  # type: ignore

        setproctitle.setproctitle(title)
        return
    except Exception:
        pass
    try:
        # Best-effort on Unix; Activity Monitor primarily uses the executable name.
        if hasattr(sys, "argv") and sys.argv:
            sys.argv[0] = title
    except Exception:
        pass


def _start_parent_watchdog() -> None:
    """Exit when the Flutter/parent process dies (covers Force Quit / missed SIGTERM)."""
    raw = (os.environ.get("AI_CRASH_FIX_PARENT_PID") or "").strip()
    if not raw:
        return
    try:
        parent_pid = int(raw)
    except ValueError:
        return
    if parent_pid <= 1:
        return

    def _watch() -> None:
        while True:
            time.sleep(0.75)
            try:
                # Signal 0: existence check. Raises if parent is gone.
                os.kill(parent_pid, 0)
            except ProcessLookupError:
                os._exit(0)
            except PermissionError:
                # Process exists but we cannot signal it — treat as still alive.
                continue
            except OSError:
                os._exit(0)

    t = threading.Thread(target=_watch, name="parent-watchdog", daemon=True)
    t.start()


def main(argv: list[str] | None = None) -> int:
    _set_process_title()
    parser = argparse.ArgumentParser(description="Fixora backend (FastAPI) for desktop bundling.")
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

    _start_parent_watchdog()

    # Import late so PyInstaller collects only what it needs.
    import uvicorn  # noqa: WPS433
    from app.services.backend_logging import uvicorn_log_config

    log_config = uvicorn_log_config(str(args.log_level))

    uvicorn.run(
        "app.api.server:app",
        host=args.host,
        port=int(args.port),
        log_level=str(args.log_level),
        log_config=log_config,
        reload=False,
        access_log=False,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
