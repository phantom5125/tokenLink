"""Copy framework-owned flash inputs into the environment build directory."""

from pathlib import Path
from shutil import copy2

Import("env")  # type: ignore[name-defined]  # Provided by PlatformIO/SCons.


def export_release_files(source, target, env):  # type: ignore[no-untyped-def]
    framework = Path(
        env.PioPlatform().get_package_dir("framework-arduinoespressif32")
    )
    boot_app0 = framework / "tools" / "partitions" / "boot_app0.bin"
    build_dir = Path(env.subst("$BUILD_DIR"))
    if not boot_app0.is_file():
        raise RuntimeError(f"Framework boot_app0.bin is missing: {boot_app0}")
    copy2(boot_app0, build_dir / "boot_app0.bin")


env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", export_release_files)
