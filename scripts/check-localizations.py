#!/usr/bin/env python3
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCALIZATION_FILES = sorted((ROOT / "Currency Tracker").glob("*.lproj/Localizable.strings"))
REFERENCE_FILE = ROOT / "Currency Tracker" / "zh-Hans.lproj" / "Localizable.strings"


def keys_for(path: pathlib.Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', text, re.MULTILINE))


def main() -> int:
    key_sets = {path: keys_for(path) for path in LOCALIZATION_FILES}
    reference_keys = key_sets.get(REFERENCE_FILE)
    if reference_keys is None:
        print(f"Missing reference localization: {REFERENCE_FILE.relative_to(ROOT)}")
        return 1

    failed = False

    for path, keys in key_sets.items():
        missing = sorted(reference_keys - keys)
        extra = sorted(keys - reference_keys)
        if missing:
            failed = True
            print(f"{path.relative_to(ROOT)} is missing {len(missing)} key(s):")
            for key in missing:
                print(f"  - {key}")
        if extra:
            failed = True
            print(f"{path.relative_to(ROOT)} has {len(extra)} unexpected key(s):")
            for key in extra:
                print(f"  - {key}")

    if failed:
        return 1

    print(f"Localization keys are aligned across {len(LOCALIZATION_FILES)} locales ({len(reference_keys)} keys).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
