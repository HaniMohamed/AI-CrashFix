
import os

from app.utils.line_numbering import annotate_with_line_numbers

class RepoService:
    def __init__(self, repo_root: str) -> None:
        if not repo_root or not str(repo_root).strip():
            raise ValueError("repo_root is required")
        self.repo_root = str(repo_root).strip()

    def _abs_path(self, path: str) -> str:
        if not path:
            return path
        return path if os.path.isabs(path) else os.path.join(self.repo_root, path)

    def get_file_context(self, file, line, radius=20):
        file_path = self._abs_path(file)
        with open(file_path, "r") as f:
            lines = f.readlines()

        start = max(0, line - radius)
        end = line + radius

        # Line numbers are real (1-indexed) file line numbers, not snippet-relative —
        # the fix-generation prompt relies on these to produce accurate `@@` hunk headers.
        return annotate_with_line_numbers("".join(lines[start:end]), start_line=start + 1)



    def extract_method(self, file_path, line_number):
        abs_path = self._abs_path(file_path)
        with open(abs_path, "r") as f:
            lines = f.readlines()

        # naive but effective for MVP
        start = max(0, line_number - 50)
        end = min(len(lines), line_number + 50)

        block = lines[start:end]

        return annotate_with_line_numbers("".join(block), start_line=start + 1)