#!/usr/bin/env python3
"""Deterministic user installer distribution from repository source files."""
from pathlib import Path
import hashlib,json,zipfile
root=Path(__file__).resolve().parent.parent
man=json.loads((root/'Tools/manifest.json').read_text(encoding='utf-8'))
release=man['release']
files=[Path('INSTALL.cmd'),Path('RESTORE.cmd'),Path('README.txt')]
files += [Path('Profiles')/p['filename'] for p in man['profiles']]
files += [Path(f) for f in ['Tools/Database/ams2-additions.json','Tools/Database/SqliteInjector.cs','Tools/PRESET_SHA256.txt','Tools/RecoveryEngine.ps1','Tools/SetupEngine.ps1','Tools/manifest.json']]
out=root/'dist'/f'MediocreAtBest-AMS2-MOZA-{release}.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for file in files:
        assert (root/file).is_file(),file
        entry=zipfile.ZipInfo(file.as_posix(),date_time=(2026,11,25,21,30,0))
        entry.compress_type=zipfile.ZIP_DEFLATED
        entry.external_attr=0o100644<<16
        z.writestr(entry,(root/file).read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
sha=hashlib.sha256(out.read_bytes()).hexdigest()
(out.parent/(out.name+'.sha256')).write_text(f'{sha}  {out.name}\n',encoding='ascii')
print(f'BUILT: {out.name}, {len(files)} files, SHA256 {sha}')
