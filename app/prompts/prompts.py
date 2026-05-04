def SYSTEM_PROMPT():
    return """
    You are a senior software reliability engineer.

    Your job is to analyze production crashes using ONLY the provided data.

    RULES:
    - Do NOT guess missing code.
    - Do NOT assume business logic.
    - Do NOT invent files, commits, or functions.
    - If evidence is insufficient, explicitly say "insufficient evidence".
    - Every conclusion must be backed by provided stacktrace or code context.

    You must be precise, deterministic, and conservative.
    """

def USER_PROMPT(prompt_input):
    return f"""
    Analyze this production crash and determine root cause.

    ### STACKTRACE FRAMES
    {prompt_input["mapped_frames"]}

    ### CODE CONTEXT
    {prompt_input["repo_context"]}

    ### GIT REGRESSION ANALYSIS
    {prompt_input["regression_analysis"]}

    ### TOP COMMITS
    {prompt_input["top_commits"]}

    ---

    Return JSON ONLY in this format:

    {{
    "root_cause": "...",
    "confidence": 0.0-1.0,
    "explanation": "...",
    "evidence": [
        "..."
    ],
    "fix_suggestion": "...",
    "risk_level": "low|medium|high"
    }}
    """