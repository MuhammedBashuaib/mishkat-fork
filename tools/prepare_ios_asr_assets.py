#!/usr/bin/env python3
"""Package the existing Android model into Runner without a second source copy.

Called by the Runner build phase. It performs no network access, and fails the
build before packaging incomplete or modified speech-model assets.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile


ROOT = Path(__file__).resolve().parents[1]
MODEL_SIZE = 131_652_502
MODEL_SHA256 = "0067900797b4ef012fe5da8476e71253366af945b876da614ae356c37392a6f7"
ASSET_SHA256 = {
    "tokens.txt": "9b938381a19a69bb279cdcfc299419f25a049ea1de192e0d10317274a0f20074",
    "NOTICE.txt": "a6d43af140cddf3f48eeca52d750dae490ebfc0c4f67f7e8248aebe9696cd67b",
    "SHERPA_ONNX_LICENSE.txt": "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
    "ONNX_RUNTIME_LICENSE.txt": "2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c",
}


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def assemble_model(parts, output):
    """Validate all source parts while atomically replacing the bundle model."""
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".asr-model-", dir=output.parent)
    digest = hashlib.sha256()
    size = 0
    try:
        with os.fdopen(descriptor, "wb") as destination:
            for part in parts:
                with part.open("rb") as source:
                    for block in iter(lambda: source.read(1024 * 1024), b""):
                        size += len(block)
                        if size > MODEL_SIZE:
                            raise ValueError("Offline model exceeds its expected size")
                        digest.update(block)
                        destination.write(block)
        if size != MODEL_SIZE or digest.hexdigest() != MODEL_SHA256:
            raise ValueError("Offline model size or SHA-256 verification failed")
        os.replace(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)


def prepare(app_bundle):
    destination = app_bundle / "asr"
    assets = ROOT / "android/app/src/main/assets/asr"
    parts = [
        ROOT / f"android/app/model/asr/model.int8.onnx.part{index:02d}"
        for index in range(3)
    ]
    for name, expected in ASSET_SHA256.items():
        if file_sha256(assets / name) != expected:
            raise ValueError(f"Offline recitation asset verification failed: {name}")
    assemble_model(parts, destination / "model.int8.onnx")
    for name in ASSET_SHA256:
        shutil.copyfile(assets / name, destination / name)
    shutil.copyfile(
        ROOT / "ios/OfflineASR/IOS_ENGINE_NOTICE.txt",
        destination / "IOS_ENGINE_NOTICE.txt",
    )
    print("Verified iOS offline model and tokens; packaged model and licenses in asr/")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-bundle", type=Path, required=True)
    arguments = parser.parse_args()
    prepare(arguments.app_bundle.resolve())
