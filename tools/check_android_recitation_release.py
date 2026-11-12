#!/usr/bin/env python3
"""Verify the offline-recitation JNI contract in a built AAB or complete APK.

Usage: python3 tools/check_android_recitation_release.py path/to/release.aab

Reads the actual DEX definitions, not R8 mappings or build configuration. The
vendored AAR's class files define the field/method names and JVM descriptors
expected by its JNI library. The recursive config graph includes otherwise
unused model configs: JNI reads these too. No Android SDK or Python packages are
required. APK input must be a universal/monolithic APK, not an individual split.
This does not replace initializing and decoding with the release on a device.
"""

import argparse
import hashlib
import io
from pathlib import Path
import re
import struct
import sys
import zipfile


APP = Path(__file__).resolve().parents[1]
PREFIX = "Lcom/k2fsa/sherpa/onnx/"
AAR = APP / "android/app/libs/sherpa-onnx-static-link-onnxruntime-1.13.8.aar"
MODEL_SHA256 = "0067900797b4ef012fe5da8476e71253366af945b876da614ae356c37392a6f7"
MODEL_SIZE = 131652502
STATIC, NATIVE, SYNTHETIC = 0x0008, 0x0100, 0x1000


class Reader:
    def __init__(self, data, offset=0):
        self.data, self.offset = data, offset

    def take(self, size):
        end = self.offset + size
        if size < 0 or end > len(self.data):
            raise ValueError("Truncated binary structure")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def uint(self, size, order="big"):
        return int.from_bytes(self.take(size), order)

    def uleb(self):
        value = 0
        for shift in range(0, 35, 7):
            byte = self.uint(1)
            value |= (byte & 127) << shift
            if not byte & 128:
                return value
        raise ValueError("Invalid ULEB128")


def class_members(data):
    """Return instance fields and methods from one JVM class file."""
    r = Reader(data)
    if r.take(4) != b"\xca\xfe\xba\xbe":
        raise ValueError("Invalid AAR class file")
    r.take(4)  # Minor and major class-file versions.
    pool = [None] * r.uint(2)
    index = 1
    widths = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4,
              11: 4, 12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
    while index < len(pool):
        tag = r.uint(1)
        if tag == 1:
            pool[index] = r.take(r.uint(2)).decode("utf-8", errors="replace")
        elif tag in widths:
            r.take(widths[tag])
        else:
            raise ValueError(f"Unsupported class-file constant tag {tag}")
        index += 2 if tag in (5, 6) else 1
    r.take(6)  # Access flags, this class, superclass.
    r.take(2 * r.uint(2))  # Interfaces.

    def members():
        result = {}
        for _ in range(r.uint(2)):
            flags, name, descriptor = r.uint(2), pool[r.uint(2)], pool[r.uint(2)]
            result[(name, descriptor)] = flags
            for _ in range(r.uint(2)):
                r.take(2)
                r.take(r.uint(4))
        return result

    fields, methods = members(), members()
    return {key: flags for key, flags in fields.items() if not flags & STATIC}, methods


def dex_classes(data):
    """Read defined classes/members from standard DEX 035–040 (all DEX shards)."""
    if data[:4] != b"dex\n" or data[4:7] not in (
        b"035", b"037", b"038", b"039", b"040"
    ) or data[7:8] != b"\0":
        raise ValueError("Unsupported DEX format")
    if struct.unpack_from("<I", data, 40)[0] != 0x12345678:
        raise ValueError("Unsupported DEX endianness")

    def table(header, width, fmt):
        count, offset = struct.unpack_from("<II", data, header)
        return [struct.unpack_from(fmt, data, offset + i * width) for i in range(count)]

    strings = []
    for (offset,) in table(56, 4, "<I"):
        reader = Reader(data, offset)
        reader.uleb()  # UTF-16 length; identifiers/descriptors here are ASCII.
        end = data.index(b"\0", reader.offset)
        strings.append(data[reader.offset:end].decode("utf-8", errors="replace"))
    types = [strings[index] for (index,) in table(64, 4, "<I")]
    protos = []
    for _, result, offset in table(72, 12, "<III"):
        args = []
        if offset:
            count = struct.unpack_from("<I", data, offset)[0]
            args = [types[struct.unpack_from("<H", data, offset + 4 + i * 2)[0]]
                    for i in range(count)]
        protos.append("(" + "".join(args) + ")" + types[result])
    fields = [(types[owner], strings[name], types[kind])
              for owner, kind, name in table(80, 8, "<HHI")]
    methods = [(types[owner], strings[name], protos[proto])
               for owner, proto, name in table(88, 8, "<HHI")]
    result = {}
    for definition in table(96, 32, "<IIIIIIII"):
        owner, offset = types[definition[0]], definition[6]
        instance_fields, class_methods = {}, {}
        result[owner] = instance_fields, class_methods
        if not offset:
            continue
        reader = Reader(data, offset)
        counts = [reader.uleb() for _ in range(4)]
        for group, count in enumerate(counts):
            index = 0
            for _ in range(count):
                index += reader.uleb()
                flags = reader.uleb()
                _, name, descriptor = (fields if group < 2 else methods)[index]
                if group == 1:
                    instance_fields[(name, descriptor)] = flags
                elif group >= 2:
                    reader.uleb()  # code_off; native methods have no code.
                    class_methods[(name, descriptor)] = flags
    return result


def expected_contract():
    with zipfile.ZipFile(AAR) as aar:
        with zipfile.ZipFile(io.BytesIO(aar.read("classes.jar"))) as jar:
            expected = {}
            pending = [PREFIX + name + ";" for name in (
                "OfflineRecognizerConfig", "OfflineRecognizerResult"
            )]
            while pending:
                name = pending.pop()
                if name in expected:
                    continue
                fields, methods = class_members(jar.read(name[1:-1] + ".class"))
                # JNI constructs result objects using the original constructor.
                constructors = {key: flags for key, flags in methods.items()
                                if name.endswith("Result;") and key[0] == "<init>"
                                and not flags & SYNTHETIC}
                expected[name] = fields, constructors
                pending.extend(kind for _, kind in fields if kind.startswith(PREFIX))
            for short in ("OfflineRecognizer", "OfflineStream"):
                name = PREFIX + short + ";"
                _, methods = class_members(jar.read(name[1:-1] + ".class"))
                native = {key: flags for key, flags in methods.items() if flags & NATIVE}
                if not native:
                    raise ValueError(f"No native entry points found in AAR: {short}")
                expected[name] = {}, native
    return expected


def zip_digest(archive, name):
    digest = hashlib.sha256()
    with archive.open(name) as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path):
    problems = []
    expected = expected_contract()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        bundle = "BundleConfig.pb" in names
        prefix = "base/" if bundle else ""
        dex_pattern = r"base/dex/classes\d*\.dex" if bundle else r"classes\d*\.dex"
        shards = [name for name in names if re.fullmatch(dex_pattern, name)]
        if not shards:
            raise ValueError("No base DEX files; supply an AAB or complete APK")
        actual = {}
        for name in shards:
            actual.update(dex_classes(archive.read(name)))
        field_count = method_count = 0
        for name, (fields, methods) in expected.items():
            if name not in actual:
                problems.append(f"Missing JNI class: {name}")
                continue
            actual_fields, actual_methods = actual[name]
            for field in fields:
                field_count += 1
                if field not in actual_fields:
                    problems.append(f"Missing JNI field: {name} {field[0]} {field[1]}")
            for method, flags in methods.items():
                method_count += 1
                observed = actual_methods.get(method)
                if observed is None or (flags & NATIVE and not observed & NATIVE):
                    problems.append(f"Missing JNI method: {name} {method[0]}{method[1]}")

        for asset, expected_hash in (
            ("model.int8.onnx", MODEL_SHA256),
            ("tokens.txt", hashlib.sha256((APP / "android/app/src/main/assets/asr/tokens.txt").read_bytes()).hexdigest()),
        ):
            name = prefix + "assets/asr/" + asset
            if name not in names:
                problems.append(f"Missing asset: {name}")
                continue
            if zip_digest(archive, name) != expected_hash:
                problems.append(f"Asset SHA-256 mismatch: {name}")
            if asset.endswith("onnx"):
                info = archive.getinfo(name)
                if info.file_size != MODEL_SIZE:
                    problems.append(f"Model size mismatch: {info.file_size}")
                if not bundle and info.compress_type != zipfile.ZIP_STORED:
                    problems.append("APK model is compressed; AssetManager.openFd will fail")

        abi_pattern = re.escape(prefix) + r"lib/([^/]+)/libflutter\.so"
        abis = sorted(match.group(1) for name in names
                      if (match := re.fullmatch(abi_pattern, name)))
        if not abis:
            problems.append("No Flutter ABI libraries; supply a complete APK/AAB")
        for abi in abis:
            name = prefix + f"lib/{abi}/libsherpa-onnx-jni.so"
            if name not in names:
                problems.append(f"Missing native recognition library: {abi}")

    if problems:
        print(f"FAIL: {path} ({len(problems)} contract violations)")
        for problem in problems[:30]:
            print("  " + problem)
        if len(problems) > 30:
            print(f"  ... {len(problems) - 30} further violations")
        return 1
    print(f"PASS: {path}")
    print(f"  {len(shards)} DEX files; {len(expected)} JNI classes; "
          f"{field_count} fields; {method_count} native methods/constructors")
    print(f"  Model and tokens verified; native recognition ABIs: {', '.join(abis)}")
    if bundle:
        print("  Check generated APK compression and run a release device smoke test too.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help="Release AAB or complete APK")
    args = parser.parse_args()
    try:
        return verify(args.artifact)
    except (OSError, ValueError, KeyError, IndexError, struct.error, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
