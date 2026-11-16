#!/usr/bin/env python3
"""Build and package native libraries from this checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Cargo.toml"

def run(*args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", help="Rust target triple; defaults to the host")
    parser.add_argument("--output", type=Path, help="Also copy the built libraries into this directory")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--archive", action="store_true", help="Create release ZIPs and SHA-256 files")
    args = parser.parse_args()
    host = next(line[6:] for line in subprocess.check_output(["rustc", "-vV"], text=True, cwd=ROOT).splitlines() if line.startswith("host: "))
    target = args.target or host
    env = os.environ.copy()
    if "apple-darwin" in target:
        env["CARGO_PROFILE_RELEASE_STRIP"] = "none"
    strip = shutil.which("strip")
    if "android" in target:
        ndk = env.get("ANDROID_NDK_HOME") or env.get("ANDROID_NDK_ROOT")
        if not ndk:
            parser.error("Android builds require ANDROID_NDK_HOME or ANDROID_NDK_ROOT")
        ndk_host = "darwin-x86_64" if platform.system() == "Darwin" else "linux-x86_64"
        binaries = Path(ndk) / "toolchains/llvm/prebuilt" / ndk_host / "bin"
        compiler_target = "armv7a-linux-androideabi" if target == "armv7-linux-androideabi" else target
        compiler = str(binaries / (compiler_target + "26-clang"))
        env["CARGO_TARGET_" + target.upper().replace("-", "_") + "_LINKER"] = compiler
        env["CC_" + target.replace("-", "_")] = compiler
        env["AR_" + target.replace("-", "_")] = str(binaries / "llvm-ar")
        strip = str(binaries / "llvm-strip")
    is_ios = target.endswith(("-apple-ios", "-apple-ios-sim"))
    if is_ios:
        env.setdefault("IPHONEOS_DEPLOYMENT_TARGET", "13.0")
        env["CARGO_PROFILE_RELEASE_LTO"] = "off"
        env["CARGO_PROFILE_RELEASE_STRIP"] = "none"
        suffix = ".a"
    elif "windows" in target:
        suffix = ".dll"
    elif "apple-darwin" in target:
        suffix = ".dylib"
    else:
        suffix = ".so"
    packages = [("wear-net", "wear_net", "runtime")]
    command = ["cargo", "rustc", "--crate-type", "staticlib"] if is_ios else ["cargo", "rustc" if suffix == ".dylib" else "build"]
    command.extend(["--locked", "--release", "--manifest-path", str(MANIFEST)])
    if args.offline:
        command.append("--offline")
    target_root = Path(env.get("CARGO_TARGET_DIR", MANIFEST.parent / "target")).resolve()
    env["CARGO_TARGET_DIR"] = str(target_root)
    metadata_command = ["cargo", "metadata", "--locked", "--format-version", "1", "--manifest-path", str(MANIFEST), "--filter-platform", target]
    if args.offline:
        metadata_command.append("--offline")
    metadata = json.loads(subprocess.check_output(metadata_command, env=env, cwd=ROOT))
    metadata_packages = {item["id"]: item for item in metadata["packages"]}
    nodes = {
        node["id"]: {
            dependency["pkg"] for dependency in node["deps"]
            if any(kind["kind"] != "dev" for kind in dependency["dep_kinds"])
        }
        for node in metadata["resolve"]["nodes"]
    }
    source_commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    for package, library, role in packages:
        package_id = next(item["id"] for item in metadata_packages.values() if item["name"] == package)
        included = set()
        pending = [package_id]
        while pending:
            current = pending.pop()
            if current in included:
                continue
            included.add(current)
            pending.extend(nodes[current])
        filename = ("" if suffix == ".dll" else "lib") + library + suffix
        target_args = ["--target", target] if target != host else []
        # 为 Flutter 改写动态库绝对路径预留加载命令空间
        link_args = ["--", "-C", "link-arg=-Wl,-headerpad_max_install_names"] if suffix == ".dylib" else []
        run(*command, *target_args, "-p", package, "--lib", *link_args, env=env)
        source = target_root / (target if target != host else "") / "release" / filename
        stage = ROOT / "dist" / target / role
        if stage.exists():
            shutil.rmtree(stage)
        (stage / "lib").mkdir(parents=True)
        output = stage / "lib" / filename
        shutil.copy2(source, output)
        if suffix == ".dylib":
            run("install_name_tool", "-id", "@rpath/" + filename, str(output))
            run("strip", "-x", str(output))
        elif suffix == ".so" and strip:
            run(strip, "--strip-unneeded", str(output))
        if suffix == ".dll" and source.with_suffix(".dll.lib").exists():
            shutil.copy2(source.with_suffix(".dll.lib"), stage / "lib")
        for name in ("LICENSE", "README.md", "README.en.md", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.en.md"):
            shutil.copy2(ROOT / name, stage / name)
        if (ROOT / "include").exists():
            shutil.copytree(ROOT / "include", stage / "include")
        shutil.copy2(MANIFEST.parent / "Cargo.lock", stage / "Cargo.lock")
        licenses = stage / "licenses"
        licenses.mkdir()
        dependency_notices = []
        for item in metadata_packages.values():
            if item["id"] not in included:
                continue
            dependency_notices.append({key: item.get(key) for key in ("name", "version", "license", "source")})
            dependency_root = Path(item["manifest_path"]).parent
            destination = licenses / (item["name"] + "-" + item["version"])
            for notice in dependency_root.iterdir():
                if notice.is_file() and notice.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "UNLICENSE")):
                    destination.mkdir(exist_ok=True)
                    shutil.copy2(notice, destination / notice.name)
        if (ROOT / "licenses").exists():
            shutil.copytree(ROOT / "licenses", licenses / "repository")
        (stage / "dependencies.json").write_text(json.dumps(dependency_notices, indent=2) + "\n")
        manifest = {
            "target": target,
            "role": role,
            "abi": 1,
            "lto": env.get("CARGO_PROFILE_RELEASE_LTO", "thin"),
            "commit": source_commit,
            "dirty": bool(subprocess.check_output([
                "git", "-C", str(ROOT), "status", "--porcelain",
            ])),
            "rustc": subprocess.check_output(
                ["rustc", "--version"], text=True, cwd=ROOT,
            ).strip(),
            "library": filename,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        }
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            shutil.copy2(output, args.output / filename)
        if args.archive:
            name = "wear_net"
            archive = ROOT / "dist" / (name + "-" + target + ".zip")
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, strict_timestamps=False) as zipped:
                for path in sorted(stage.rglob("*")):
                    if path.is_file():
                        zipped.write(path, path.relative_to(stage))
            archive.with_suffix(".zip.sha256").write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + archive.name + "\n")
            print(archive)
        print(output)

if __name__ == "__main__":
    main()
