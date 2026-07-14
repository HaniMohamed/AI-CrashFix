from app.prompts.json_output import JSON_OUTPUT_SYSTEM_RULES, json_output_user_reminder
from app.utils.llm_helpers import extract_top_commits
from app.utils.prompt_budget import json_prompt


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
    """ + JSON_OUTPUT_SYSTEM_RULES

def USER_PROMPT(prompt_input):
    repo_context = prompt_input.get("repo_context")
    top_commits = prompt_input.get("top_commits")
    if top_commits is None and repo_context:
        top_commits = extract_top_commits(repo_context)
    regression = prompt_input.get("regression_analysis") or repo_context

    return f"""
    Analyze this production crash and determine root cause.

    ### STACKTRACE FRAMES
    {json_prompt(prompt_input.get("mapped_frames"))}

    ### CODE CONTEXT
    {json_prompt(repo_context)}

    ### GIT REGRESSION ANALYSIS
    {json_prompt(regression)}

    ### TOP COMMITS
    {json_prompt(top_commits)}

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
    """ + json_output_user_reminder()
