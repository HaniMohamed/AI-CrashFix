RISK_KEYWORDS = [
    "refactor",
    "migrate",
    "cleanup",
    "optimize",
    "null",
    "async",
    "state"
]


def find_top_commit(commits):
    if not commits:
        return None

    # prioritize risky commits first
    for c in commits:
        msg = c["message"].lower()

        if any(k in msg for k in RISK_KEYWORDS):
            return c

    # fallback → most recent
    return commits[0]