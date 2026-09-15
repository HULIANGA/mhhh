"""Fetch the pinned Godot toolchain into .tools, without a system installation.

Only Web and Windows templates are extracted from the official remote ZIP.
HTTP byte ranges avoid downloading unrelated mobile/.NET templates.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import io
import platform
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
LOCAL = ROOT / ".tools"
CHUNK = 2 * 1024 * 1024


def curl(*args: str) -> bytes:
    return subprocess.check_output(["curl", "-fsSL", "--retry", "3", "--connect-timeout", "20", "--max-time", "300", *args])


class RemoteZip(io.RawIOBase):
    def __init__(self, url: str):
        self.url = url
        headers = curl("-I", url).decode()
        lengths = re.findall(r"(?im)^content-length:\s*(\d+)", headers)
        if not lengths:
            raise RuntimeError("Download server did not report archive size")
        self.length = int(lengths[-1])
        self.position = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else (self.position if whence == 1 else self.length) + offset
        return self.position

    def tell(self):
        return self.position

    def _range(self, bounds):
        start, end = bounds
        data = curl("-H", f"Range: bytes={start}-{end - 1}", self.url)
        if len(data) != end - start:
            raise RuntimeError("Server did not honor byte range; refusing invalid archive data")
        return data

    def read(self, size=-1):
        end = self.length if size < 0 else min(self.position + size, self.length)
        if end <= self.position:
            return b""
        ranges = [(i, min(i + CHUNK, end)) for i in range(self.position, end, CHUNK)]
        with ThreadPoolExecutor(max_workers=8) as pool:
            data = b"".join(pool.map(self._range, ranges))
        self.position = end
        return data


def main():
    downloads = LOCAL / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    (LOCAL / ".gdignore").touch()
    templates = LOCAL / "templates"
    templates.mkdir(exist_ok=True)
    system = platform.system()
    if system == "Darwin":
        slug, local_name = "macos.universal.zip", "godot-macos.zip"
        executable = LOCAL / "Godot.app/Contents/MacOS/Godot"
    elif system == "Windows":
        slug, local_name = "win64.exe.zip", "godot-windows.zip"
        executable = LOCAL / f"Godot_v{VERSION}-stable_win64.exe"
    else:
        raise SystemExit("This setup script currently supports macOS and Windows x86_64 development hosts.")

    if not executable.exists():
        name = f"Godot_v{VERSION}-stable_{slug}"
        archive = downloads / local_name
        remote = RemoteZip(f"{BASE}/{name}")
        start = archive.stat().st_size if archive.exists() else 0
        if start > remote.length:
            raise RuntimeError(f"Oversized cached archive: delete {archive} and retry")
        print(f"Downloading {name}: {start // 1048576}/{remote.length // 1048576} MiB", flush=True)
        with archive.open("ab") as output:
            for offset in range(start, remote.length, CHUNK * 8):
                remote.seek(offset)
                output.write(remote.read(min(CHUNK * 8, remote.length - offset)))
                print(f"  {output.tell() // 1048576} MiB", flush=True)
        checksums = curl(f"{BASE}/SHA512-SUMS.txt").decode()
        expected = next(line.split()[0] for line in checksums.splitlines() if line.rstrip().endswith(name))
        with archive.open("rb") as source:
            digest = hashlib.sha512()
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
            if digest.hexdigest() != expected:
                raise RuntimeError(f"SHA-512 mismatch: delete {archive} and retry")
        with zipfile.ZipFile(archive) as source:
            source.extractall(LOCAL)
        executable.chmod(executable.stat().st_mode | 0o111)

    names = ["web_nothreads_debug.zip", "web_nothreads_release.zip", "windows_debug_x86_64.exe", "windows_release_x86_64.exe"]
    missing = [name for name in names if not (templates / name).exists()]
    if missing:
        print("Fetching Web and Windows templates from the official archive…", flush=True)
        with zipfile.ZipFile(RemoteZip(f"{BASE}/Godot_v{VERSION}-stable_export_templates.tpz")) as source:
            for name in missing:
                path = f"templates/{name}"
                print(f"  {name}", flush=True)
                # ZipFile validates each entry's CRC before we persist it.
                data = source.read(path)
                (templates / name).write_bytes(data)
    (LOCAL / ".gdignore").touch()
    print(f"Ready: {executable}", flush=True)
    subprocess.run([str(executable), "--headless", "--version"], check=True)


if __name__ == "__main__":
    main()
