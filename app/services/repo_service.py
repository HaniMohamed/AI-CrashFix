class RepoService:

    def get_file_context(self, file, line, radius=20):
        with open(file, "r") as f:
            lines = f.readlines()

        start = max(0, line - radius)
        end = line + radius

        return "".join(lines[start:end])