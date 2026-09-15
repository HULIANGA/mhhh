"""One entry point for import, tests, exports, and localhost-only Web preview."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import os
import platform
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def engine():
    configured = os.environ.get("GODOT_BIN")
    default = ROOT / ".tools/Godot.app/Contents/MacOS/Godot" if platform.system() == "Darwin" else ROOT / ".tools/Godot_v4.7.2-stable_win64.exe"
    path = Path(configured) if configured else default
    if not path.is_file():
        raise SystemExit("Godot not found. Run python3 tools/setup.py, or set GODOT_BIN to your Godot executable.")
    return str(path)


def run(*arguments):
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    result = subprocess.run([engine(), "--headless", "--path", str(ROOT), "--log-file", str(ROOT / "build/godot.log"), *arguments], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="", flush=True)
    # Import may return 0 even when GDScript compilation failed.
    if result.returncode or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):", result.stdout):
        raise SystemExit(result.returncode or 1)


def import_project():
    run("--editor", "--import")


def export(target):
    folder, preset, filename = ("web", "Web", "index.html") if target == "web" else ("windows", "Windows", "MHHH.exe")
    destination = ROOT / "build" / folder
    destination.mkdir(parents=True, exist_ok=True)
    run("--export-release", preset, str(destination / filename))


class PreviewHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".pck": "application/octet-stream"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "test", "web", "windows", "all", "serve", "preview"])
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    if args.command not in ("serve",):
        import_project()
    if args.command == "test":
        run("--script", "res://tests/movement_test.gd")
    if args.command in ("web", "all", "preview"):
        export("web")
    if args.command in ("windows", "all"):
        export("windows")
    if args.command in ("serve", "preview"):
        directory = ROOT / "build/web"
        if not (directory / "index.html").is_file():
            raise SystemExit("No Web build. Run python3 tools/dev.py web first.")
        server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(PreviewHandler, directory=str(directory)))
        print(f"Preview: http://127.0.0.1:{args.port}  (Ctrl+C to stop)", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            server.server_close()


if __name__ == "__main__":
    main()
