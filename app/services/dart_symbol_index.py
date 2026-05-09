from __future__ import annotations

import json
import os
import re
from bisect import bisect_right
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class SymbolLocation:
    file: str  # repo-relative posix path
    line: int  # 1-based
    kind: str  # class|mixin|extension|method|function|unknown


def _posix_relpath(path: str, *, repo_root: str) -> str:
    rel = os.path.relpath(path, repo_root)
    return rel.replace(os.sep, "/")


def _line_starts(text: str) -> list[int]:
    starts = [0]
    for m in re.finditer(r"\n", text):
        starts.append(m.end())
    return starts


def _offset_to_line(line_starts: list[int], offset: int) -> int:
    # 1-based line number
    return bisect_right(line_starts, offset)


_DECL_RE = re.compile(r"(?m)^\s*(class|mixin|extension)\s+(?P<name>[A-Za-z_]\w*)\b")

# Best-effort member matcher inside class-like blocks.
_METHOD_RE = re.compile(
    r"(?m)^\s*"
    r"(?:@[\w().,:<>\s]+\s*)*"  # annotations
    r"(?:external\s+|static\s+|final\s+|const\s+|factory\s+|late\s+)*"
    r"(?:[\w<>\?\[\]\s]+\s+)?"  # return type-ish
    r"(?P<name>[A-Za-z_]\w*)\s*\(",
)

# Best-effort top-level function matcher (used only if we can't find a containing class).
_TOPLEVEL_FN_RE = re.compile(
    r"(?m)^\s*"
    r"(?:@[\w().,:<>\s]+\s*)*"
    r"(?:[\w<>\?\[\]\s]+\s+)"
    r"(?P<name>[a-z_]\w*)\s*\(",
)


def _iter_dart_files(*, repo_root: str, packages_dirs: list[str]) -> Iterable[str]:
    repo_root = (repo_root or "").strip()
    if not repo_root:
        return
    roots: list[Path] = []
    roots.append(Path(repo_root) / "lib")
    for d in packages_dirs:
        # <dir>/*/lib
        base = (Path(repo_root) / d).resolve()
        if not base.is_dir():
            continue
        for child in base.iterdir():
            lib = child / "lib"
            if lib.is_dir():
                roots.append(lib)

    seen: set[str] = set()
    for root in roots:
        if not root.is_dir():
            continue
        for p in root.rglob("*.dart"):
            try:
                rp = p.resolve()
            except Exception:
                continue
            s = str(rp)
            if s in seen:
                continue
            seen.add(s)
            yield s


def build_symbol_index(
    *,
    repo_root: str,
    repo_key: str,
    commit_sha: str,
    packages_dirs: list[str],
    out_dir: str | None = None,
) -> dict[str, Any]:
    """
    Build a lightweight, best-effort Dart symbol index (no analyzer dependency).

    Outputs a JSON structure suitable for on-disk caching.
    """
    repo_root = (repo_root or "").strip()
    repo_key = (repo_key or "").strip()
    commit_sha = (commit_sha or "").strip()
    if not repo_root:
        raise ValueError("repo_root is required")
    if not repo_key:
        raise ValueError("repo_key is required")
    if not commit_sha:
        raise ValueError("commit_sha is required")

    out_base = Path(out_dir or "db/ast_index").expanduser().resolve()
    target = (out_base / repo_key / commit_sha).resolve()
    target.mkdir(parents=True, exist_ok=True)

    symbols: dict[str, list[dict[str, Any]]] = {}
    file_map: dict[str, dict[str, Any]] = {}

    for abs_path in _iter_dart_files(repo_root=repo_root, packages_dirs=packages_dirs):
        rel = _posix_relpath(abs_path, repo_root=repo_root)
        try:
            text = Path(abs_path).read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        starts = _line_starts(text)
        file_entry: dict[str, Any] = {"classes": {}}

        # Parse class/mixin/extension blocks with naive brace counting.
        for m in _DECL_RE.finditer(text):
            kind = m.group(1)
            name = m.group("name")
            line = _offset_to_line(starts, m.start())

            symbols.setdefault(name, []).append({"file": rel, "line": line, "kind": kind})

            # Find block start '{' after declaration.
            block_open = text.find("{", m.end())
            if block_open == -1:
                continue
            depth = 0
            i = block_open
            end = None
            while i < len(text):
                ch = text[i]
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
                i += 1
            if end is None:
                continue

            block = text[block_open + 1 : end]
            cls_methods: dict[str, list[dict[str, Any]]] = {}
            for mm in _METHOD_RE.finditer(block):
                meth = mm.group("name")
                # Ignore obvious keyword-ish matches.
                if meth in {"if", "for", "while", "switch", "catch", "return", "await"}:
                    continue
                abs_off = (block_open + 1) + mm.start()
                meth_line = _offset_to_line(starts, abs_off)
                qname = f"{name}.{meth}"
                loc = {"file": rel, "line": meth_line, "kind": "method"}
                symbols.setdefault(qname, []).append(loc)
                cls_methods.setdefault(meth, []).append(loc)

            file_entry["classes"][name] = {
                "kind": kind,
                "decl": {"file": rel, "line": line},
                "methods": cls_methods,
            }

        # Top-level functions (best-effort). Only add if file has no classes.
        if not file_entry["classes"]:
            for fm in _TOPLEVEL_FN_RE.finditer(text):
                fn = fm.group("name")
                line = _offset_to_line(starts, fm.start())
                symbols.setdefault(fn, []).append({"file": rel, "line": line, "kind": "function"})

        file_map[rel] = file_entry

    payload: dict[str, Any] = {
        "meta": {
            "repo_key": repo_key,
            "commit_sha": commit_sha,
            "packages_dirs": list(packages_dirs),
            "built_at": datetime.utcnow().isoformat(),
            "version": 1,
        },
        "symbols": symbols,
        "file_map": file_map,
    }

    (target / "symbols.json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return payload


def load_symbol_index(*, repo_key: str, commit_sha: str, base_dir: str | None = None) -> dict[str, Any] | None:
    repo_key = (repo_key or "").strip()
    commit_sha = (commit_sha or "").strip()
    if not repo_key or not commit_sha:
        return None
    base = Path(base_dir or "db/ast_index").expanduser().resolve()
    p = (base / repo_key / commit_sha / "symbols.json").resolve()
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None


def index_exists(*, repo_key: str, commit_sha: str, base_dir: str | None = None) -> bool:
    repo_key = (repo_key or "").strip()
    commit_sha = (commit_sha or "").strip()
    if not repo_key or not commit_sha:
        return False
    base = Path(base_dir or "db/ast_index").expanduser().resolve()
    p = (base / repo_key / commit_sha / "symbols.json").resolve()
    return p.is_file()


def lookup_symbol(
    index: dict[str, Any],
    *,
    qualified: str | None = None,
    class_name: str | None = None,
    member: str | None = None,
    file_hint: str | None = None,
) -> list[SymbolLocation]:
    """
    Best-effort query helper. Returns a ranked list of candidate locations.
    """
    symbols = (index or {}).get("symbols") or {}
    q = (qualified or "").strip() or None
    if not q and class_name and member:
        q = f"{class_name.strip()}.{member.strip()}"
    if not q:
        return []

    hits = symbols.get(q) or []
    locs: list[SymbolLocation] = []
    for h in hits:
        try:
            locs.append(SymbolLocation(file=str(h["file"]), line=int(h["line"]), kind=str(h.get("kind") or "unknown")))
        except Exception:
            continue

    hint = (file_hint or "").strip() or None
    if hint:
        # prefer exact file match then basename match
        def _score(loc: SymbolLocation) -> tuple[int, int]:
            if loc.file == hint:
                return (0, loc.line)
            if loc.file.endswith("/" + os.path.basename(hint)) or os.path.basename(loc.file) == os.path.basename(hint):
                return (1, loc.line)
            return (2, loc.line)

        locs.sort(key=_score)
    else:
        locs.sort(key=lambda l: (l.file, l.line))
    return locs

