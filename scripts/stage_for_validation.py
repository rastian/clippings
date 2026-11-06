#!/usr/bin/env python3
"""Copy build inputs to temporary storage when iCloud Drive blocks coordinated reads."""
import shutil
from pathlib import Path
root = Path(__file__).resolve().parents[1]
target = Path('/tmp/linkin-validation')
target.mkdir(exist_ok=True)
for name in ['App','Config','Sources','Tests','UITests','ShareExtension','linkin.xcodeproj']:
    shutil.copytree(root/name, target/name, dirs_exist_ok=True, ignore=shutil.ignore_patterns('xcuserdata'))
shutil.copy2(root/'Package.swift', target/'Package.swift')
print(target)
