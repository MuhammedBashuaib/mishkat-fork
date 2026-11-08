#!/usr/bin/env python3
"""Fetch checksum-pinned iOS inference libraries before CocoaPods resolves them.

This is a development/build operation only, never an application download.
Pass --archive-dir for a predownloaded/offline cache whose filenames are the
last URL components in ios/OfflineASR/artifacts.json.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import urlparse
import zipfile


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "ios/OfflineASR/artifacts.json"
VENDOR = ROOT / "ios/OfflineASR/Vendor"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def install_archive(name, artifact, archive, vendor):
    if sha256(archive) != artifact["sha256"]:
        raise ValueError(f"SHA-256 mismatch for {name}; refusing unverified library")
    vendor.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=vendor) as staging:
        staging = Path(staging)
        expected_root = name + ".xcframework"
        with zipfile.ZipFile(archive) as source:
            for item in source.infolist():
                relative = Path(item.filename)
                if (
                    relative.is_absolute()
                    or ".." in relative.parts
                    or not relative.parts
                    or relative.parts[0] != expected_root
                    or stat.S_ISLNK(item.external_attr >> 16)
                ):
                    raise ValueError(f"Unexpected archive entry: {item.filename}")
            source.extractall(staging)
        framework = staging / expected_root
        if not (framework / "Info.plist").is_file():
            raise ValueError(f"Missing XCFramework Info.plist: {name}")
        # CocoaPods derives -framework from the outer XCFramework basename.
        # Upstream calls the archive root sherpa-onnx.xcframework, although its
        # actual inner framework/module is SherpaOnnxC. Preserve all verified
        # contents and normalize only the installed outer directory name.
        framework_name = artifact.get("framework_name", name)
        with (framework / "Info.plist").open("rb") as source:
            slices = plistlib.load(source)["AvailableLibraries"]
        if not slices or any(
            Path(item["LibraryPath"]).stem != framework_name for item in slices
        ):
            raise ValueError(f"Unexpected framework/module name in {name}")
        # The marker is written only after the entire verified archive exists.
        (framework / ".mishkat-artifact.json").write_text(
            json.dumps(artifact, sort_keys=True) + "\n", encoding="utf-8"
        )
        destination = vendor / (framework_name + ".xcframework")
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(framework, destination)


def is_installed(name, artifact, vendor):
    framework = vendor / (artifact.get("framework_name", name) + ".xcframework")
    marker = framework / ".mishkat-artifact.json"
    if not marker.is_file() or not (framework / "Info.plist").is_file():
        return False
    try:
        if json.loads(marker.read_text(encoding="utf-8")) != artifact:
            return False
        with (framework / "Info.plist").open("rb") as source:
            libraries = plistlib.load(source)["AvailableLibraries"]
        for library in libraries:
            bundle = framework / library["LibraryIdentifier"] / library["LibraryPath"]
            with (bundle / "Info.plist").open("rb") as source:
                executable = plistlib.load(source)["CFBundleExecutable"]
            if not (bundle / executable).is_file():
                return False
        return bool(libraries)
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException):
        return False


def download(artifact, destination):
    # The official release API is a fallback for networks where github.com's
    # normal release redirect is unavailable; both paths require the same hash.
    for index, url in enumerate((artifact["url"], artifact["api_url"])):
        command = [
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--connect-timeout", "20", "--max-time", "300",
            "--output", str(destination),
        ]
        if index:
            command.extend(["--header", "Accept: application/octet-stream"])
        command.append(url)
        attempt = subprocess.run(command, check=False)
        if attempt.returncode == 0 and sha256(destination) == artifact["sha256"]:
            return
        destination.unlink(missing_ok=True)
    raise RuntimeError("Unable to download a verified iOS ASR library; check network or supply --archive-dir")


def prepare(archive_dir=None):
    artifacts = json.loads(CONFIG.read_text(encoding="utf-8"))
    VENDOR.mkdir(parents=True, exist_ok=True)
    for name, artifact in artifacts.items():
        if is_installed(name, artifact, VENDOR):
            continue
        filename = Path(urlparse(artifact["url"]).path).name
        local = archive_dir / filename if archive_dir else None
        if local is not None and local.is_file():
            install_archive(name, artifact, local, VENDOR)
        else:
            with tempfile.TemporaryDirectory(prefix="mishkat-asr-") as temporary:
                archive = Path(temporary) / filename
                download(artifact, archive)
                install_archive(name, artifact, archive, VENDOR)
        print(f"Verified and prepared {name} {artifact['version']} for iOS")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-dir", type=Path)
    arguments = parser.parse_args()
    prepare(arguments.archive_dir)
