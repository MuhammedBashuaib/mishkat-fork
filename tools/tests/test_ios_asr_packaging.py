"""Verify incomplete/corrupt local speech assets cannot enter an iOS bundle."""

import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile


TOOLS = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


assets = module("prepare_ios_asr_assets")
libraries = module("prepare_ios_asr_libraries")


class ModelPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.parts = [self.root / f"part{index}" for index in range(3)]
        for part, data in zip(self.parts, (b"model", b"-middle", b"-end")):
            part.write_bytes(data)
        self.expected = b"model-middle-end"
        self.output = self.root / "Runner.app/asr/model.int8.onnx"
        self.output.parent.mkdir(parents=True)
        self.output.write_bytes(b"previous verified model")
        self.addCleanup(patch.stopall)
        patch.object(assets, "MODEL_SIZE", len(self.expected)).start()
        patch.object(assets, "MODEL_SHA256", hashlib.sha256(self.expected).hexdigest()).start()

    def test_assembles_parts_in_the_required_order(self):
        assets.assemble_model(self.parts, self.output)
        self.assertEqual(self.output.read_bytes(), self.expected)
        self.assertEqual(list(self.output.parent.glob(".asr-model-*")), [])

    def test_corrupt_part_cannot_replace_valid_existing_model(self):
        self.parts[1].write_bytes(b"-broken")
        with self.assertRaises(ValueError):
            assets.assemble_model(self.parts, self.output)
        self.assertEqual(self.output.read_bytes(), b"previous verified model")
        self.assertEqual(list(self.output.parent.glob(".asr-model-*")), [])

    def test_missing_part_fails_without_leaving_partial_bundle(self):
        self.parts[2].unlink()
        with self.assertRaises(FileNotFoundError):
            assets.assemble_model(self.parts, self.output)
        self.assertEqual(self.output.read_bytes(), b"previous verified model")
        self.assertEqual(list(self.output.parent.glob(".asr-model-*")), [])


class LibraryPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "library.zip"
        self.vendor = self.root / "Vendor"

    def create_archive(self, path):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr(path, b"test library")
        return {"sha256": libraries.sha256(self.archive)}

    def test_modified_download_rejected_before_extraction(self):
        artifact = self.create_archive("sherpa-onnx.xcframework/Info.plist")
        with self.archive.open("ab") as destination:
            destination.write(b"corruption")
        with self.assertRaises(ValueError):
            libraries.install_archive("sherpa-onnx", artifact, self.archive, self.vendor)
        self.assertFalse(self.vendor.exists())

    def test_path_escape_rejected_even_for_matching_archive_hash(self):
        artifact = self.create_archive("sherpa-onnx.xcframework/../../escaped")
        with self.assertRaises(ValueError):
            libraries.install_archive("sherpa-onnx", artifact, self.archive, self.vendor)
        self.assertFalse((self.root / "escaped").exists())
        self.assertFalse((self.vendor / "sherpa-onnx.xcframework").exists())

    def test_marker_alone_does_not_hide_missing_framework(self):
        framework = self.vendor / "sherpa-onnx.xcframework"
        framework.mkdir(parents=True)
        artifact = {"sha256": "example"}
        (framework / ".mishkat-artifact.json").write_text(json.dumps(artifact))
        self.assertFalse(libraries.is_installed("sherpa-onnx", artifact, self.vendor))

    def test_upstream_archive_is_installed_using_actual_linker_module_name(self):
        root = "sherpa-onnx.xcframework"
        framework = root + "/ios-arm64/SherpaOnnxC.framework"
        info = {"AvailableLibraries": [{
            "LibraryIdentifier": "ios-arm64",
            "LibraryPath": "SherpaOnnxC.framework",
        }]}
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr(root + "/Info.plist", plistlib.dumps(info))
            archive.writestr(
                framework + "/Info.plist",
                plistlib.dumps({"CFBundleExecutable": "SherpaOnnxC"}),
            )
            archive.writestr(framework + "/SherpaOnnxC", b"verified static binary")
        artifact = {
            "sha256": libraries.sha256(self.archive),
            "framework_name": "SherpaOnnxC",
        }
        libraries.install_archive("sherpa-onnx", artifact, self.archive, self.vendor)
        self.assertFalse((self.vendor / root).exists())
        installed = self.vendor / "SherpaOnnxC.xcframework"
        self.assertEqual(
            (installed / "ios-arm64/SherpaOnnxC.framework/SherpaOnnxC").read_bytes(),
            b"verified static binary",
        )
        self.assertTrue(libraries.is_installed("sherpa-onnx", artifact, self.vendor))


if __name__ == "__main__":
    unittest.main()
