#!/usr/bin/env python3
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCALIZATION_FILES = [
    ROOT / "Currency Tracker" / "en.lproj" / "Localizable.strings",
    ROOT / "Currency Tracker" / "ru.lproj" / "Localizable.strings",
    ROOT / "Currency Tracker" / "zh-Hans.lproj" / "Localizable.strings",
]


def keys_for(path: pathlib.Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', text, re.MULTILINE))


def main() -> int:
    key_sets = {path: keys_for(path) for path in LOCALIZATION_FILES}
    all_keys = set().union(*key_sets.values())
    failed = False

    for path, keys in key_sets.items():
        missing = sorted(all_keys - keys)
        if missing:
            failed = True
            print(f"{path.relative_to(ROOT)} is missing {len(missing)} key(s):")
            for key in missing:
                print(f"  - {key}")

    if failed:
        return 1

    print(f"Localization keys are aligned across {len(LOCALIZATION_FILES)} locales ({len(all_keys)} keys).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
