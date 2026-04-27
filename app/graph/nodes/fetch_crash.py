from app.services.crashlytics_service import CrashlyticsService


def fetch_crash(state):
    """
    Fetch ONE crash if not already provided.
    Allows override for testing.
    """

    # If crash already provided → skip fetching
    if state.get("stacktrace"):
        return state

    # Lazy init so missing/invalid credentials don't break imports.
    service = CrashlyticsService()
    crashes = service.fetch_recent_crashes(limit=1)

    if not crashes:
        raise ValueError("No crashes found")

    crash = crashes[0]

    state.update({
        "crash_id": crash["crash_id"],
        "exception": crash["exception"],
        "stacktrace": crash["stacktrace"],
        "app_version": crash.get("app_version"),
        "device": crash.get("device"),
        "platform": crash.get("platform"),
    })

    return state