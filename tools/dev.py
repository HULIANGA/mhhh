"""One entry point for imports, tests, exports, and Web previews."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import errno
import os
import platform
import re
import shutil
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BLENDER_VERSION = "5.2.2"


def engine():
    configured = os.environ.get("GODOT_BIN")
    default = ROOT / ".tools/Godot.app/Contents/MacOS/Godot" if platform.system() == "Darwin" else ROOT / ".tools/Godot_v4.7.2-stable_win64.exe"
    path = Path(configured) if configured else default
    if not path.is_file():
        raise SystemExit("Godot not found. Run python3 tools/setup.py, or set GODOT_BIN to your Godot executable.")
    return str(path)


def blender():
    configured = os.environ.get("BLENDER_BIN")
    if configured:
        candidates = [Path(configured)]
    elif platform.system() == "Darwin":
        candidates = [
            ROOT / ".tools/Blender.app/Contents/MacOS/Blender",
            Path("/Applications/Blender.app/Contents/MacOS/Blender"),
            Path.home() / "Applications/Blender.app/Contents/MacOS/Blender",
        ]
    elif platform.system() == "Windows":
        candidates = [ROOT / ".tools/blender-5.2.2-windows-x64/blender.exe"]
    else:
        candidates = []
    system_blender = shutil.which("blender")
    if system_blender:
        candidates.append(Path(system_blender))
    for path in candidates:
        if path.is_file():
            return str(path)
    raise SystemExit("Blender 5.2.2 not found. Run python3 tools/setup_blender.py, or set BLENDER_BIN.")


def export_art_assets():
    executable = blender()
    version = subprocess.run(
        [executable, "--background", "--version"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    ).stdout
    if not re.search(rf"(?m)^Blender {re.escape(BLENDER_VERSION)}(?:\s|$)", version):
        raise SystemExit(f"M4 assets require Blender {BLENDER_VERSION}; selected executable reported:\n{version}")
    command = [
        executable, "--background", "--factory-startup",
        "--python", str(ROOT / "art/blender/build_contract_asset.py"),
        "--", "--root", str(ROOT),
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="", flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)


def validate_art_assets():
    subprocess.run([sys.executable, str(ROOT / "tools/validate_art_assets.py")], cwd=ROOT, check=True)


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


def lan_addresses():
    addresses = set()
    try:
        addresses.update(
            address[4][0]
            for address in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
        )
    except socket.gaierror:
        pass
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 9))
            addresses.add(probe.getsockname()[0])
    except OSError:
        pass
    return sorted(address for address in addresses if not address.startswith("127."))


def serve(host, port):
    directory = ROOT / "build/web"
    if not (directory / "index.html").is_file():
        raise SystemExit("No Web build. Run python3 tools/dev.py web first.")
    server = None
    selected_port = port
    for candidate in range(port, port + 10):
        try:
            server = ThreadingHTTPServer((host, candidate), partial(PreviewHandler, directory=str(directory)))
            selected_port = candidate
            break
        except OSError as error:
            if error.errno != errno.EADDRINUSE:
                raise
    if server is None:
        raise SystemExit(f"Ports {port}–{port + 9} are already in use. Choose another with --port.")
    if selected_port != port:
        print(f"Port {port} is already in use; using {selected_port} instead.", flush=True)
    if host == "127.0.0.1":
        print(f"Local preview: http://127.0.0.1:{selected_port}  (Ctrl+C to stop)", flush=True)
    else:
        addresses = lan_addresses()
        urls = ", ".join(f"http://{address}:{selected_port}" for address in addresses)
        print(f"LAN preview: {urls or f'http://<this-device-ip>:{selected_port}'}  (Ctrl+C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=[
            "check", "test", "web", "windows", "all",
            "art-export", "art-check",
            "serve-local", "serve-lan", "preview-local", "preview-lan",
            "serve", "preview",
        ],
    )
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    serve_commands = ("serve", "serve-local", "serve-lan")
    preview_commands = ("preview", "preview-local", "preview-lan")
    if args.command == "art-export":
        export_art_assets()
        validate_art_assets()
        import_project()
        run("--script", "res://tests/art_asset_test.gd")
        return
    if args.command == "art-check":
        validate_art_assets()
        import_project()
        run("--script", "res://tests/art_asset_test.gd")
        return
    if args.command not in serve_commands:
        import_project()
    if args.command == "test":
        validate_art_assets()
        run("--script", "res://tests/art_asset_test.gd")
        run("--script", "res://tests/input_test.gd")
        run("--script", "res://tests/movement_test.gd")
        run("--script", "res://tests/combat_test.gd")
        run("--script", "res://tests/vitality_test.gd")
        run("--script", "res://tests/monster_test.gd")
        run("--script", "res://tests/monster_attack_test.gd")
        run("--script", "res://tests/monster_pounce_test.gd")
        run("--script", "res://tests/monster_charge_test.gd")
        run("--script", "res://tests/monster_decision_test.gd")
        run("--script", "res://tests/battle_flow_test.gd")
        run("--script", "res://tests/round_stability_test.gd")
    if args.command in ("web", "all", *preview_commands):
        export("web")
    if args.command in ("windows", "all"):
        export("windows")
    if args.command in (*serve_commands, *preview_commands):
        host = "0.0.0.0" if args.command.endswith("-lan") else "127.0.0.1"
        serve(host, args.port)


if __name__ == "__main__":
    main()
