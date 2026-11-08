# Local iOS recitation dependencies

Runner uses the same model and vocabulary as Android through the Sherpa ONNX
C API. This folder only supplies build-time dependencies; recognition does not
contact a server or download model data on the user's phone.

`pod install` invokes `../../tools/prepare_ios_asr_libraries.py` before resolving
the local `MishkatOfflineASR` pod. It downloads the two official static
XCFrameworks pinned in `artifacts.json`, checks SHA-256 before extraction, and
reuses them on later offline builds. `Vendor/` is generated and ignored by Git.
Device arm64 and simulator arm64/x86_64 slices are included. Other pod versions
are left locked.

The verified upstream `sherpa-onnx.xcframework` archive root is installed as
`Vendor/SherpaOnnxC.xcframework`, matching its inner `SherpaOnnxC.framework`
module and binary. CocoaPods derives linker flags from this outer basename.
Only the outer directory is renamed; the libraries and headers stay unchanged.

To prepare dependencies explicitly from the app directory:

```sh
python3 tools/prepare_ios_asr_libraries.py
```

For offline CI, cache the original archives using their URL filenames and run
`python3 tools/prepare_ios_asr_libraries.py --archive-dir /path/to/cache` first.
The same checksum checks apply to cached archives. Normal release URLs are
preferred; the official GitHub release-asset API is the fallback for networks
that cannot follow the usual release redirect.

Runner's `Bundle Verified Offline Recitation Model` build phase invokes
`tools/prepare_ios_asr_assets.py`. It assembles the existing three tracked model
parts, verifies the same Android model size and SHA-256, checks tokens/licenses,
and installs them in `Runner.app/asr/`. No extra 126 MiB model source is tracked.
The build fails for missing or changed assets. All model/library attribution and
license files ship beside the model. See `IOS_ENGINE_NOTICE.txt` for versions.

The pins come from the tagged upstream package manifests:

- [Sherpa ONNX 1.13.8](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/Package.swift)
- [ONNX Runtime 1.28.2](https://github.com/csukuangfj/onnxruntime-libs/blob/1.28.2/Package.swift)

Packaging regression checks, without network or Xcode:

```sh
python3 -m unittest discover -s tools/tests -p 'test_ios_asr_packaging.py'
```
