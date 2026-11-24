#!/usr/bin/env python3
"""Build and verify a CurseForge-ready runtime ZIP without Finder extras."""

from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
NAME = "StrutYourBootsy"
TOC = ROOT / (NAME + ".toc")
toc = TOC.read_text(encoding="utf-8")
version = re.search(r"^## Version: ([0-9A-Za-z.-]+)$", toc, re.M).group(1)
lua = [line.strip() for line in toc.splitlines() if re.fullmatch(r"[A-Za-z0-9_]+\.lua", line.strip())]
assets = [
    "Assets/ArmoryClose.tga",
    "Assets/ArmoryStarOff.tga",
    "Assets/ArmoryStarOn.tga",
    "Assets/ArmoryTrim.tga",
    "Assets/BootsyMinimap.tga",
    "Assets/GoldleafCorner.tga",
    "Assets/HelpBubble.tga",
    "Assets/SnowglowFlake.tga",
]
assert lua and len(set(lua)) == len(lua) and lua[-1] == "Main.lua", lua
files = [TOC.name, *lua, *assets]
out = ROOT / "dist" / f"{NAME}-{version}.zip"
out.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(out, "w", compression=ZIP_DEFLATED, compresslevel=9) as z:
    for path in files:
        source = ROOT / path
        assert source.is_file() and not source.is_symlink() and source.stat().st_size > 0, path
        info = ZipInfo(f"{NAME}/{path}")
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        z.writestr(info, source.read_bytes())
with ZipFile(out) as z:
    assert z.namelist() == [f"{NAME}/{p}" for p in files]
    assert z.testzip() is None
    for name, path in zip(z.namelist(), files):
        assert z.read(name) == (ROOT / path).read_bytes(), name
print(out)
