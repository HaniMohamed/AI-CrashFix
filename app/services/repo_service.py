
import os

from app.config import REPO_ROOT

class RepoService:

    def _abs_path(self, path: str) -> str:
        if not path:
            return path
        return path if os.path.isabs(path) else os.path.join(REPO_ROOT, path)

    def get_file_context(self, file, line, radius=20):
        file_path = self._abs_path(file)
        with open(file_path, "r") as f:
            lines = f.readlines()

        start = max(0, line - radius)
        end = line + radius

        return "".join(lines[start:end])



    def extract_method(self, file_path, line_number):
        abs_path = self._abs_path(file_path)
        with open(abs_path, "r") as f:
            lines = f.readlines()

        # naive but effective for MVP
        start = max(0, line_number - 50)
        end = min(len(lines), line_number + 50)

        block = lines[start:end]

        return "".join(block)