import re
import os
import subprocess
from typing import List, Dict

from app.config import REPO_ROOT

# ==============================
# Regex Patterns
# ==============================

DART_REGEX = re.compile(
    r'#\d+\s+(?P<method>[\w.<>\s]+)\s+\(package:(?P<package>[\w_]+)/(?P<path>.*\.dart):(?P<line>\d+):\d+\)'
)

ANDROID_REGEX = re.compile(
    r'at\s+(?P<class>[\w\.]+)\.(?P<method>\w+)\((?P<file>[\w\.]+):(?P<line>\d+)\)'
)

IOS_REGEX = re.compile(
    r'(?P<file>\w+\.swift):(?P<line>\d+)'
)

# ==============================
# Config
# ==============================

ANDROID_SRC_PATHS = [
    "android/app/src/main/java",
    "android/app/src/main/kotlin"
]

IOS_ROOT = "ios"

# ==============================
# Helpers
# ==============================

def run_rg_search(query: str) -> str:
    """Fallback search using ripgrep"""
    try:
        result = subprocess.check_output(
            ["rg", "--files-with-matches", query],
            cwd=REPO_ROOT,
            text=True
        )
        return result.splitlines()[0] if result else None
    except Exception:
        return None


def file_exists(path: str) -> bool:
    if not path:
        return False
    candidate = path if os.path.isabs(path) else os.path.join(REPO_ROOT, path)
    return os.path.exists(candidate)


def normalize_frame(frame_type, file, line, method=None):
    return {
        "type": frame_type,
        "file": file,
        "line": int(line),
        "method": method
    }


def get_priority(frame_type: str) -> int:
    priorities = {
        "dart": 1,
        "kotlin": 2,
        "java": 2,
        "swift": 3
    }
    return priorities.get(frame_type, 99)


def is_noise_frame(class_name: str) -> bool:
    noise_prefixes = [
        "io.flutter",
        "androidx",
        "java.",
        "kotlin.",
        "dart:"
    ]
    return any(class_name.startswith(p) for p in noise_prefixes)


# ==============================
# Dart Parser
# ==============================

def parse_dart(stack_lines: List[str]) -> List[Dict]:
    frames = []

    for line in stack_lines:
        match = DART_REGEX.search(line)
        if not match:
            continue

        path = match.group("path")
        line_no = match.group("line")
        method = match.group("method").strip()

        file_path = os.path.join("lib", path)

        if not file_exists(file_path):
            # fallback search by filename
            file_name = os.path.basename(path)
            found = run_rg_search(file_name)
            if found:
                file_path = found
            else:
                continue

        frames.append(normalize_frame("dart", file_path, line_no, method))

    return frames


# ==============================
# Android Parser
# ==============================

def resolve_android_path(class_name: str, file_name: str) -> str:
    class_path = class_name.replace(".", "/")

    for base in ANDROID_SRC_PATHS:
        for ext in [".kt", ".java"]:
            full_path = os.path.join(base, class_path + ext)
            if file_exists(full_path):
                return full_path

    # fallback search
    found = run_rg_search(file_name)
    return found


def parse_android(stack_lines: List[str]) -> List[Dict]:
    frames = []

    for line in stack_lines:
        match = ANDROID_REGEX.search(line)
        if not match:
            continue

        class_name = match.group("class")
        method = match.group("method")
        file_name = match.group("file")
        line_no = match.group("line")

        if is_noise_frame(class_name):
            continue

        file_path = resolve_android_path(class_name, file_name)

        if not file_path:
            continue

        frame_type = "kotlin" if file_path.endswith(".kt") else "java"

        frames.append(normalize_frame(frame_type, file_path, line_no, method))

    return frames


# ==============================
# iOS Parser
# ==============================

def resolve_ios_path(file_name: str) -> str:
    for root, _, files in os.walk(IOS_ROOT):
        if file_name in files:
            return os.path.join(root, file_name)

    # fallback search
    return run_rg_search(file_name)


def parse_ios(stack_lines: List[str]) -> List[Dict]:
    frames = []

    for line in stack_lines:
        match = IOS_REGEX.search(line)
        if not match:
            continue

        file_name = match.group("file")
        line_no = match.group("line")

        file_path = resolve_ios_path(file_name)

        if not file_path:
            continue

        frames.append(normalize_frame("swift", file_path, line_no))

    return frames


# ==============================
# Main Mapper Function (LangGraph Node)
# ==============================

def map_stacktrace(state: Dict) -> Dict:
    stack_lines = state.get("stacktrace", [])

    dart_frames = parse_dart(stack_lines)
    android_frames = parse_android(stack_lines)
    ios_frames = parse_ios(stack_lines)

    all_frames = dart_frames + android_frames + ios_frames

    # Remove duplicates (same file + line)
    seen = set()
    unique_frames = []
    for f in all_frames:
        key = (f["file"], f["line"])
        if key not in seen:
            seen.add(key)
            unique_frames.append(f)

    # Sort by priority
    unique_frames.sort(key=lambda f: get_priority(f["type"]))

    # Take top 5 most relevant frames
    state["mapped_frames"] = unique_frames[:5]

    return state