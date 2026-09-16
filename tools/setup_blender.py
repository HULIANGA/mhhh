"""Fetch the pinned Blender asset toolchain into .tools.

Blender is an authoring dependency only. Runtime builds consume committed GLB
files and do not require this installation.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import platform
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".tools"
DOWNLOADS = LOCAL / "downloads"
VERSION = "5.2.2"
BASE = "https://download.blender.org/release/Blender5.2"


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    head = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "MHHH asset setup"})
    with urllib.request.urlopen(head, timeout=30) as response:
        total = int(response.headers["Content-Length"])
    copied = partial.stat().st_size if partial.exists() else 0
    if copied > total:
        raise RuntimeError(f"Oversized partial download: delete {partial} and retry")
    chunk_size = 4 * 1024 * 1024
    ranges = [(start, min(start + chunk_size, total)) for start in range(copied, total, chunk_size)]

    def fetch(bounds: tuple[int, int]) -> bytes:
        start, end = bounds
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "MHHH asset setup", "Range": f"bytes={start}-{end - 1}"},
        )
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read()
        if len(data) != end - start:
            raise RuntimeError("Download server did not honor byte ranges")
        return data

    print(f"Downloading {destination.name}: {copied // 1048576}/{total // 1048576} MiB", flush=True)
    with partial.open("ab") as output, ThreadPoolExecutor(max_workers=8) as pool:
        for data in pool.map(fetch, ranges):
            output.write(data)
            copied += len(data)
            print(f"\r  {copied // 1048576}/{total // 1048576} MiB", end="", flush=True)
    print(flush=True)
    partial.replace(destination)


def expected_checksum(filename: str) -> str:
    with urllib.request.urlopen(f"{BASE}/blender-{VERSION}.sha256", timeout=30) as response:
        lines = response.read().decode().splitlines()
    for line in lines:
        fields = line.split()
        if len(fields) >= 2 and fields[-1].lstrip("*") == filename:
            return fields[0]
    raise RuntimeError(f"No official SHA-256 entry for {filename}")


def verify(archive: Path) -> None:
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    expected = expected_checksum(archive.name)
    if digest.hexdigest() != expected:
        raise RuntimeError(f"SHA-256 mismatch: delete {archive} and retry")


def install_macos(archive: Path) -> Path:
    destination = LOCAL / "Blender.app"
    if destination.exists():
        return destination / "Contents/MacOS/Blender"
    with tempfile.TemporaryDirectory(prefix="mhhh-blender-") as mount:
        subprocess.run(["hdiutil", "attach", str(archive), "-nobrowse", "-readonly", "-mountpoint", mount], check=True)
        try:
            source = Path(mount) / "Blender.app"
            if not source.is_dir():
                raise RuntimeError("Official image did not contain Blender.app")
            shutil.copytree(source, destination, symlinks=True)
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=True)
    return destination / "Contents/MacOS/Blender"


def install_windows(archive: Path) -> Path:
    destination = LOCAL / f"blender-{VERSION}-windows-x64"
    executable = destination / "blender.exe"
    if executable.exists():
        return executable
    with zipfile.ZipFile(archive) as source:
        source.extractall(LOCAL)
    return executable


def main() -> None:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Darwin" and machine == "arm64":
        filename = f"blender-{VERSION}-macos-arm64.dmg"
        installer = install_macos
    elif system == "Windows" and machine in ("amd64", "x86_64"):
        filename = f"blender-{VERSION}-windows-x64.zip"
        installer = install_windows
    else:
        raise SystemExit("Pinned Blender setup currently supports Apple Silicon macOS and Windows x86_64 hosts.")

    LOCAL.mkdir(parents=True, exist_ok=True)
    (LOCAL / ".gdignore").touch()
    archive = DOWNLOADS / filename
    if not archive.exists():
        download(f"{BASE}/{filename}", archive)
    print(f"Verifying {filename}…", flush=True)
    verify(archive)
    executable = installer(archive)
    if not executable.is_file():
        raise RuntimeError(f"Blender installation failed: {executable}")
    print(f"Ready: {executable}")
    subprocess.run([str(executable), "--background", "--version"], check=True)


if __name__ == "__main__":
    main()
