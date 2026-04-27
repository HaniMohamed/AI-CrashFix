
class RepoService:

    def get_file_context(self, file, line, radius=20):
        with open(file, "r") as f:
            lines = f.readlines()

        start = max(0, line - radius)
        end = line + radius

        return "".join(lines[start:end])



    def extract_method(self, file_path, line_number):
        with open(file_path, "r") as f:
            lines = f.readlines()

        # naive but effective for MVP
        start = max(0, line_number - 50)
        end = min(len(lines), line_number + 50)

        block = lines[start:end]

        return "".join(block)