import re
import os
import glob
import subprocess
from typing import List, Dict

from app import config as cfg

# ==============================
# Regex Patterns
# ==============================

# Matches Flutter-style Dart frames like:
#   #0 SomeClass.method (lib/foo/bar.dart:12:34)
LIB_DART_REGEX = re.compile(
    r'#\d+\s+(?P<method>[\w.<>\s$]+)\s+\((?P<path>lib/.*?\.dart):(?P<line>\d+)(?::\d+)?\)'
)

# Matches package frames like:
#   #3 Widget.build (package:flutter/src/widgets/framework.dart:123:45)
PACKAGE_DART_REGEX = re.compile(
    r'#\d+\s+(?P<method>[\w.<>\s$]+)\s+\(package:(?P<package>[\w_]+)/(?P<path>.*?\.dart):(?P<line>\d+)(?::\d+)?\)'
)

# Crashlytics-style short paths: (my_widget.dart:42) — project lib only, not (lib/...) or (package:...)
BARE_DART_REGEX = re.compile(
    r'#\d+\s+(?P<method>[\w.<>\s$]+)\s+\((?!(?:lib/|package:))(?P<file>[a-zA-Z0-9_]+\.dart):(?P<line>\d+)(?::\d+)?\)'
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

def run_rg_search(query: str, *, repo_root: str) -> str:
    """Fallback search using ripgrep"""
    try:
        rg_path = (os.getenv("AI_CRASH_FIX_RG_PATH") or "").strip() or "rg"
        result = subprocess.check_output(
            [rg_path, "--files-with-matches", query],
            cwd=repo_root,
            text=True,
            stderr=subprocess.STDOUT,
        )
        return result.splitlines()[0] if result else None
    except Exception:
        return None


def file_exists(path: str, *, repo_root: str) -> bool:
    if not path:
        return False
    candidate = path if os.path.isabs(path) else os.path.join(repo_root, path)
    return os.path.exists(candidate)


def normalize_frame(frame_type, file, line, method=None, *, resolved_by: str):
    return {
        "type": frame_type,
        "file": file,
        "line": int(line),
        "method": method,
        "resolved_by": resolved_by,
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

def _dart_file_declares_pascal_symbol(abs_path: str, head: str) -> bool:
    """True if this source file declares class/mixin/extension named head (word boundaries)."""
    if not head or not head[0].isupper():
        return False
    he = re.escape(head)
    try:
        with open(abs_path, "r", encoding="utf-8", errors="ignore") as fh:
            chunk = fh.read(262144)
    except OSError:
        return False
    if re.search(rf"\bclass\s+{he}\b", chunk):
        return True
    if re.search(rf"\bmixin\s+{he}\b", chunk):
        return True
    if re.search(rf"\bextension\s+{he}\b", chunk):
        return True
    return False


def _iter_dart_source_roots() -> List[str]:
    """
    Repo-relative roots to search for Dart files.
    - Always includes "lib"
    - Optionally includes "<packages_dir>/*/lib" for monorepo packages (melos, etc)
    """
    roots = ["lib"]
    packages_dirs = []
    if getattr(cfg, "LOCAL_PACKAGES_DIR", None):
        packages_dirs = [str(getattr(cfg, "LOCAL_PACKAGES_DIR")).strip().strip("/")]
    for d in packages_dirs:
        if d:
            roots.append(os.path.join(d, "*", "lib"))
    return roots


def _iter_dart_source_roots_for(packages_dirs: list[str]) -> List[str]:
    roots = ["lib"]
    for d in packages_dirs or []:
        d = (d or "").strip().strip("/")
        if d:
            roots.append(os.path.join(d, "*", "lib"))
    return roots


def resolve_dart_basename_in_repo_sources(
    basename: str,
    method: str,
    *,
    repo_root: str,
    packages_dirs: list[str],
) -> str | None:
    """
    Resolve a short stack filename to a repo-relative path.
    Searches:
      - lib/**/<basename>
      - <packages_dir>/*/lib/**/<basename>  (if configured)
    Returns repo-relative posix path or None.
    """
    abs_hits: list[str] = []
    for root in _iter_dart_source_roots_for(packages_dirs):
        root_abs = os.path.join(repo_root, root)
        if "*" in root:
            # e.g. packages/*/lib → ensure parent exists before globbing
            parent_dir = root.split(os.sep)[0]
            parent = os.path.join(repo_root, parent_dir) if parent_dir else None
            if not parent or not os.path.isdir(parent):
                continue
        else:
            if not os.path.isdir(root_abs):
                continue
        pattern = os.path.join(root_abs, "**", basename)
        abs_hits.extend(glob.glob(pattern, recursive=True))

    if not abs_hits:
        return None

    rels = [os.path.relpath(p, repo_root) for p in abs_hits]
    rels = [r.replace(os.sep, "/") for r in rels]
    allowed_prefixes = ["lib/"]
    for d in packages_dirs or []:
        d = (d or "").strip().strip("/")
        if d:
            allowed_prefixes.append(f"{d}/")
    rels = [r for r in rels if any(r.startswith(pref) for pref in allowed_prefixes)]
    if not rels:
        return None

    head = (method or "").strip().split(".")[0]
    if not head or not head[0].isupper():
        return None
    matches = []
    for rel in rels:
        abs_p = os.path.join(repo_root, rel)
        if _dart_file_declares_pascal_symbol(abs_p, head):
            matches.append(rel)
    if not matches:
        # Fallback: some frames reference functions/extensions where the file doesn't declare the class name.
        # Prefer the single hit; otherwise pick the shortest path to avoid deep duplicates.
        if len(rels) == 1:
            return rels[0]
        rels.sort(key=len)
        return rels[0]
    if len(matches) == 1:
        return matches[0]
    matches.sort(key=len)
    return matches[0]


def parse_dart(
    stack_lines: List[str],
    *,
    repo_root: str,
    packages_dirs: list[str],
    repo_key: str | None = None,
    head_sha: str | None = None,
) -> List[Dict]:
    frames = []
    # Best-effort: load symbol index if available.
    index = None
    if repo_key and head_sha:
        try:
            from app.services.dart_symbol_index import load_symbol_index, lookup_symbol

            index = load_symbol_index(repo_key=repo_key, commit_sha=head_sha, repo_root=repo_root)
        except Exception:
            index = None

    for line in stack_lines:
        match = LIB_DART_REGEX.search(line)
        if match:
            file_path = match.group("path")
            line_no = match.group("line")
            method = match.group("method").strip()
            if file_exists(file_path, repo_root=repo_root):
                frames.append(
                    normalize_frame(
                        "dart",
                        file_path,
                        line_no,
                        method,
                        resolved_by="dart_stack_lib_path",
                    )
                )
            continue

        match = PACKAGE_DART_REGEX.search(line)
        if match:
            # For AI Crash Fix repo mapping, package: frames are usually Flutter/Dart SDK noise.
            # Only map them if they can be resolved to an actual repo file without guessing.
            package = match.group("package")
            path = match.group("path")
            line_no = match.group("line")
            method = match.group("method").strip()

            # 1) Try root lib/ (some repos mirror package layout there)
            candidate = os.path.join("lib", path)
            if file_exists(candidate, repo_root=repo_root):
                frames.append(
                    normalize_frame(
                        "dart",
                        candidate.replace(os.sep, "/"),
                        line_no,
                        method,
                        resolved_by="dart_package_as_lib_path",
                    )
                )
                continue

            # 2) Try local monorepo packages: <LOCAL_PACKAGES_DIR>/<package>/lib/<path>
            if packages_dirs:
                for d in packages_dirs:
                    d = (d or "").strip().strip("/")
                    if not d:
                        continue
                    local_candidate = os.path.join(d, package, "lib", path)
                    if file_exists(local_candidate, repo_root=repo_root):
                        frames.append(
                            normalize_frame(
                                "dart",
                                local_candidate.replace(os.sep, "/"),
                                line_no,
                                method,
                                resolved_by="dart_package_local_dir",
                            )
                        )
                        break
                else:
                    # If package dir name doesn't match, fall back to scanning all child packages.
                    for d in packages_dirs:
                        d = (d or "").strip().strip("/")
                        if not d:
                            continue
                        pattern = os.path.join(repo_root, d, "*", "lib", path)
                        hits = glob.glob(pattern, recursive=False)
                        if hits:
                            rel = os.path.relpath(hits[0], repo_root).replace(os.sep, "/")
                            frames.append(
                                normalize_frame(
                                    "dart",
                                    rel,
                                    line_no,
                                    method,
                                    resolved_by="dart_package_glob_fallback",
                                )
                            )
                            break
            continue

        bare = BARE_DART_REGEX.search(line)
        if bare:
            basename = bare.group("file")
            line_no = bare.group("line")
            method = bare.group("method").strip()
            resolved = None
            resolved_by = None
            if index is not None:
                try:
                    from app.services.dart_symbol_index import lookup_symbol

                    # Use method name as-is; prefer candidates matching the basename.
                    cands = lookup_symbol(index, qualified=method, file_hint=basename)
                    if cands:
                        resolved = cands[0].file
                        resolved_by = "dart_ast_index"
                except Exception:
                    resolved = None
            if not resolved:
                resolved = resolve_dart_basename_in_repo_sources(
                    basename, method, repo_root=repo_root, packages_dirs=packages_dirs
                )
                if resolved:
                    resolved_by = "dart_legacy_glob"
            if resolved and file_exists(resolved, repo_root=repo_root):
                frames.append(
                    normalize_frame(
                        "dart",
                        resolved,
                        line_no,
                        method,
                        resolved_by=(resolved_by or "dart_unknown"),
                    )
                )

    return frames


# ==============================
# Android Parser
# ==============================

def resolve_android_path(class_name: str, file_name: str, *, repo_root: str) -> str:
    class_path = class_name.replace(".", "/")

    for base in ANDROID_SRC_PATHS:
        for ext in [".kt", ".java"]:
            full_path = os.path.join(base, class_path + ext)
            if file_exists(full_path, repo_root=repo_root):
                return full_path

    # fallback search
    found = run_rg_search(file_name, repo_root=repo_root)
    return found


def parse_android(stack_lines: List[str], *, repo_root: str) -> List[Dict]:
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

        file_path = resolve_android_path(class_name, file_name, repo_root=repo_root)

        if not file_path:
            continue

        frame_type = "kotlin" if file_path.endswith(".kt") else "java"

        resolved_by = "android_direct_path"
        if file_path and ("/" not in file_path and "\\" not in file_path):
            # rg --files-with-matches returns a filename only in some environments; treat as search-based.
            resolved_by = "android_rg_search"
        frames.append(normalize_frame(frame_type, file_path, line_no, method, resolved_by=resolved_by))

    return frames


# ==============================
# iOS Parser
# ==============================

def resolve_ios_path(file_name: str, *, repo_root: str) -> str:
    for root, _, files in os.walk(os.path.join(repo_root, IOS_ROOT)):
        if file_name in files:
            return os.path.join(root, file_name)

    # fallback search
    return run_rg_search(file_name, repo_root=repo_root)


def parse_ios(stack_lines: List[str], *, repo_root: str) -> List[Dict]:
    frames = []

    for line in stack_lines:
        match = IOS_REGEX.search(line)
        if not match:
            continue

        file_name = match.group("file")
        line_no = match.group("line")

        file_path = resolve_ios_path(file_name, repo_root=repo_root)

        if not file_path:
            continue

        resolved_by = "ios_walk_search"
        if file_path and ("/" not in file_path and "\\" not in file_path):
            resolved_by = "ios_rg_search"
        frames.append(normalize_frame("swift", file_path, line_no, resolved_by=resolved_by))

    return frames


# ==============================
# Main Mapper Function (LangGraph Node)
# ==============================

def map_stacktrace(state: Dict) -> Dict:
    repo_root = (state.get("repo_root") or cfg.REPO_ROOT or "").strip()
    stack_lines = state.get("stacktrace", [])
    repo_key = (state.get("repo_key") or "").strip() or None

    packages_dirs = state.get("packages_dirs")
    if isinstance(packages_dirs, list):
        packages_dirs = [str(x) for x in packages_dirs if str(x).strip()]
    else:
        # Back-compat: env config (deprecated; UI should set repo-scoped packages dirs).
        packages_dirs = []
        if getattr(cfg, "LOCAL_PACKAGES_DIR", None):
            packages_dirs = [str(getattr(cfg, "LOCAL_PACKAGES_DIR")).strip().strip("/")]

    head_sha = None
    if repo_root and repo_key:
        try:
            from app.services.project_service import ProjectService

            head_sha = ProjectService.get_head_sha(repo_root)
        except Exception:
            head_sha = None

    dart_frames = parse_dart(
        stack_lines,
        repo_root=repo_root,
        packages_dirs=packages_dirs,
        repo_key=repo_key,
        head_sha=head_sha,
    )
    android_frames = parse_android(stack_lines, repo_root=repo_root)
    ios_frames = parse_ios(stack_lines, repo_root=repo_root)

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