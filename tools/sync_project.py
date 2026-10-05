#!/usr/bin/env python3
"""Sync new source/resource files into Knuckled.xcodeproj/project.pbxproj.

Usage: python3 tools/sync_project.py [--check]
  --check: exit 1 if anything is missing (CI gate), else add it.
Idempotent: stable IDs derived from paths, so re-runs are no-ops.
"""
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "Knuckled.xcodeproj" / "project.pbxproj"

NS = {
    "fileref": uuid.UUID("11111111-1111-4111-8111-111111111111"),
    "buildfile": uuid.UUID("22222222-2222-4222-8222-222222222222"),
    "group": uuid.UUID("33333333-3333-4333-8333-333333333333"),
}


def oid(kind: str, rel: str) -> str:
    return uuid.uuid5(NS[kind], rel).hex[:24].upper()


# target dir -> (sources phase id, group id, group path)
SOURCES = {
    "Knuckled": ("430000000000000000000001", "400000000000000000000002", "Knuckled"),
    "KnuckledTests": ("430000000000000000000004", "400000000000000000000003", "KnuckledTests"),
    "KnuckledUITests": ("430000000000000000000007", "400000000000000000000004", "KnuckledUITests"),
}
RES_PHASE = "430000000000000000000002"
RES_GROUP = "400000000000000000000006"  # Knuckled/Resources

FILETYPE = {
    ".swift": "sourcecode.swift",
    ".ttf": "file",
    ".wav": "audio.wav",
    ".usdz": "file",
    ".png": "image.png",
    ".xcassets": "folder.assetcatalog",
    ".xcprivacy": "text.plist.xml",
}


def want_files():
    out = []  # (relpath-posix, kind[target-dir or "Resources"], filetype)
    for sub in ("Knuckled", "KnuckledTests", "KnuckledUITests"):
        d = ROOT / sub
        if not d.is_dir():
            continue
        for p in sorted(d.rglob("*")):
            if p.is_dir():
                if p.suffix == ".xcassets":
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[".xcassets"]))
                continue
            if any(part.endswith(".xcassets") for part in p.parts):
                continue  # compiled by actool via the .xcassets entry; not a loose resource
            if p.suffix in FILETYPE and not (sub == "Knuckled" and p.name == "Info.plist"):
                kind = "Resources" if p.suffix not in (".swift",) and sub == "Knuckled" and p.parent.name == "Resources" else None
                if p.suffix == ".swift":
                    out.append((p.relative_to(ROOT).as_posix(), sub, FILETYPE[".swift"]))
                elif p.suffix in (".ttf", ".wav", ".usdz", ".png"):
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[p.suffix]))
                elif p.suffix == ".xcprivacy":
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[".xcprivacy"]))
    return out


def main() -> int:
    check_only = "--check" in sys.argv
    text = PBX.read_text()
    changed = False

    for rel, target, ftype in want_files():
        name = Path(rel).name
        # rel itself never appears in project.pbxproj (entries use basenames),
        # so also treat an existing "/* basename */" reference as registered.
        # This keeps the script idempotent against hand-registered entries.
        if rel in text or f"/* {name} */" in text:
            continue
        if target == "Resources":
            phase = RES_PHASE
            # fileRef group must mirror the file's real directory, otherwise
            # Xcode resolves sourceTree="<group>" against the wrong folder
            # (e.g. Knuckled/PrivacyInfo.xcprivacy is NOT in Knuckled/Resources/).
            if Path(rel).parent.as_posix() == "Knuckled/Resources":
                group = RES_GROUP
                fr_path = name
            elif rel.startswith("Knuckled/Resources/"):
                # resource subdir (e.g. DiceFaces/1.png): keep it in the
                # Resources group, mirroring the hand-registered
                # Sounds/*.wav precedent (path = Sounds/land.wav)
                group = RES_GROUP
                fr_path = Path(rel).relative_to("Knuckled/Resources").as_posix()
            else:
                _, group, _ = SOURCES["Knuckled"]
                fr_path = Path(rel).relative_to("Knuckled").as_posix() if rel.startswith("Knuckled/") else name
            group_path = "Knuckled/Resources"
        else:
            phase, group, group_path = SOURCES[target]
        fr = oid("fileref", rel)
        bf = oid("buildfile", rel)
        if target == "Resources":
            fr_line = f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {fr_path}; sourceTree = \"<group>\"; }};\n"
        else:
            fr_line = f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {name}; sourceTree = \"<group>\"; }};\n"
        bf_comment = "in Resources" if target == "Resources" else "in Sources"
        bf_line = f"\t\t{bf} /* {name} {bf_comment} */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n"
        text = text.replace("/* End PBXFileReference section */", fr_line + "/* End PBXFileReference section */")
        text = text.replace("/* End PBXBuildFile section */", bf_line + "/* End PBXBuildFile section */")
        # append file to phase + group (before closing ");")
        phase_anchor = f"\t\t{phase} /* {'Resources' if target == 'Resources' else 'Sources'} */ = {{\n"
        text = text.replace(
            phase_anchor + "\t\t\tisa = PB",
            phase_anchor + "\t\t\tisa = PB", 1,
        )
        # insert into files list: find phase block, insert before "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing"
        # (?<!\t) anchors to the 2-tab top-level definition, not deeper-indented
        # references to the same id (e.g. in a target's buildPhases list).
        phase_pat = re.compile(
            r"((?<!\t)\t\t" + phase + r" /\*.*?\*/ = \{\n(?:.*?\n)*?\t\t\tfiles = \(\n)(.*?)(\t\t\t\);\n)",
            re.DOTALL,
        )

        def add_file(m):
            return m.group(1) + m.group(2) + f"\t\t\t\t{bf} /* {name} {bf_comment} */,\n" + m.group(3)

        text, n = phase_pat.subn(add_file, text, count=1)
        assert n == 1, f"phase block not found for {phase}"
        # group children: insert before the group's closing "\t\t\t);\n\t\t\tpath = " or name line
        # (?<!\t) anchors to the 2-tab top-level definition, not deeper-indented
        # references to the same id (e.g. Resources listed as a child of Knuckled).
        group_pat = re.compile(
            r"((?<!\t)\t\t" + group + r" /\*.*?\*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n)",
            re.DOTALL,
        )

        def add_child(m):
            return m.group(1) + m.group(2) + f"\t\t\t\t{fr} /* {name} */,\n" + m.group(3)

        text, n2 = group_pat.subn(add_child, text, count=1)
        assert n2 == 1, f"group block not found for {group}"
        changed = True
        print(f"registered {rel}")

    if changed and not check_only:
        PBX.write_text(text)
        print("project.pbxproj updated")
    elif changed:
        print("MISSING entries (run without --check to add)")
        return 1
    else:
        print("project in sync (no changes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
