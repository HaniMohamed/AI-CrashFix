"""User-facing (not raw-exception) summaries for feedback regeneration outcomes.

Raw errors (git-apply dumps, GitLab/Jira HTTP bodies, JSON-parse traces) are fine for
logs but not for a chat thread or a Jira comment a non-engineer may read. This maps
them to a small set of known failure codes with EN/AR copy, falling back to a generic
message for anything unrecognized rather than ever echoing the raw text to the user.
"""

from __future__ import annotations

import re
from typing import Literal

Locale = Literal["en", "ar"]

_SUCCESS_TEMPLATES: dict[str, str] = {
    "en": "Revision {iteration} applied successfully. The merge request has been updated.",
    "ar": "تم تطبيق المراجعة {iteration} بنجاح. تم تحديث طلب الدمج (Merge Request).",
}

_ERROR_TEMPLATES: dict[str, dict[str, str]] = {
    "diff_apply_failed": {
        "en": (
            "Revision {iteration} could not be applied: the AI-generated change no longer matches "
            "the current code (it may have shifted since the last fix). Try rephrasing the note with "
            "more specific detail, or ask again — the AI will regenerate the patch against the latest code."
        ),
        "ar": (
            "تعذّر تطبيق المراجعة {iteration}: التغيير الذي أنشأه الذكاء الاصطناعي لم يعد مطابقًا للكود "
            "الحالي (قد يكون قد تغيّر منذ آخر إصلاح). حاول إعادة صياغة الملاحظة بتفاصيل أدق، أو أعد المحاولة "
            "وسيقوم الذكاء الاصطناعي بإعادة توليد التعديل بناءً على أحدث نسخة من الكود."
        ),
    },
    "no_fix_generated": {
        "en": (
            "Revision {iteration} failed: the AI couldn't produce a confident fix for this note. "
            "Try adding more specific detail about what should change."
        ),
        "ar": (
            "فشلت المراجعة {iteration}: لم يتمكن الذكاء الاصطناعي من إنشاء إصلاح واثق لهذه الملاحظة. "
            "حاول إضافة تفاصيل أكثر تحديدًا حول ما يجب تغييره."
        ),
    },
    "mr_not_found": {
        "en": (
            "Revision {iteration} failed: the original merge request for this branch could not be found "
            "(it may have been closed or merged). Please open a new fix cycle for this crash."
        ),
        "ar": (
            "فشلت المراجعة {iteration}: تعذّر العثور على طلب الدمج الأصلي لهذا الفرع (قد يكون قد أُغلق أو "
            "دُمج). يرجى بدء دورة إصلاح جديدة لهذا العطل."
        ),
    },
    "missing_jira": {
        "en": "Revision {iteration} failed: no linked Jira ticket was found to attach this fix to.",
        "ar": "فشلت المراجعة {iteration}: لم يتم العثور على تذكرة Jira مرتبطة لإرفاق هذا الإصلاح بها.",
    },
    "gitlab_error": {
        "en": (
            "Revision {iteration} failed while talking to GitLab. This is usually temporary — please try again."
        ),
        "ar": (
            "فشلت المراجعة {iteration} أثناء الاتصال بـ GitLab. عادة ما يكون هذا مؤقتًا — يرجى المحاولة مرة أخرى."
        ),
    },
    "jira_error": {
        "en": (
            "The fix was updated, but Fixora couldn't reach Jira to log it. "
            "The merge request itself should still be up to date."
        ),
        "ar": (
            "تم تحديث الإصلاح، لكن تعذّر على Fixora الوصول إلى Jira لتسجيله. "
            "يُفترض أن يكون طلب الدمج نفسه محدّثًا."
        ),
    },
    "ai_response_error": {
        "en": "Revision {iteration} failed: the AI returned an unexpected response. Please try again.",
        "ar": "فشلت المراجعة {iteration}: أعاد الذكاء الاصطناعي استجابة غير متوقعة. يرجى المحاولة مرة أخرى.",
    },
    "unknown_error": {
        "en": "Revision {iteration} failed due to an unexpected error. Please try again.",
        "ar": "فشلت المراجعة {iteration} بسبب خطأ غير متوقع. يرجى المحاولة مرة أخرى.",
    },
}

_CLASSIFIERS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("diff_apply_failed", re.compile(r"git apply|patch does not apply|corrupt patch", re.IGNORECASE)),
    ("no_fix_generated", re.compile(r"missing or insufficient generated_fix", re.IGNORECASE)),
    ("mr_not_found", re.compile(r"no open merge request found", re.IGNORECASE)),
    ("missing_jira", re.compile(r"missing jira_issue_id", re.IGNORECASE)),
    ("gitlab_error", re.compile(r"gitlab api error|gitlab request failed", re.IGNORECASE)),
    ("jira_error", re.compile(r"jira api error|jira request failed|missing jira token|missing jira base url", re.IGNORECASE)),
    ("ai_response_error", re.compile(r"expecting value|invalid json|json object|llm", re.IGNORECASE)),
)


def classify_error(raw_message: str | None) -> str:
    text = (raw_message or "").strip()
    if not text:
        return "unknown_error"
    for code, pattern in _CLASSIFIERS:
        if pattern.search(text):
            return code
    return "unknown_error"


def normalize_locale(locale: str | None) -> Locale:
    loc = (locale or "en").strip().lower()
    return "ar" if loc.startswith("ar") else "en"


def feedback_summary(
    *,
    ok: bool,
    iteration: int,
    pr_url: str | None = None,
    raw_error: str | None = None,
    locale: str | None = "en",
) -> str:
    """User-facing, localized summary for a feedback regeneration outcome. Never echoes `raw_error` verbatim."""
    loc = normalize_locale(locale)
    if ok:
        return _SUCCESS_TEMPLATES[loc].format(iteration=iteration)
    code = classify_error(raw_error)
    template = _ERROR_TEMPLATES.get(code, _ERROR_TEMPLATES["unknown_error"])[loc]
    return template.format(iteration=iteration)


def bilingual_feedback_summary(
    *,
    ok: bool,
    iteration: int,
    pr_url: str | None = None,
    raw_error: str | None = None,
) -> str:
    """EN + AR summary for audiences (e.g. a Jira ticket) that aren't tied to one viewer's locale."""
    en = feedback_summary(ok=ok, iteration=iteration, pr_url=pr_url, raw_error=raw_error, locale="en")
    ar = feedback_summary(ok=ok, iteration=iteration, pr_url=pr_url, raw_error=raw_error, locale="ar")
    return f"{en}\n\n{ar}"
