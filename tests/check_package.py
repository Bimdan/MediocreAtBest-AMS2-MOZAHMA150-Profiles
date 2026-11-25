#!/usr/bin/env python3
"""Read-only release QA: every V2-approved MOZA field against the frozen sheet export.

This is deliberately independent of the profile builder. A mismatch must fail
CI. It also checks archive fidelity, reference DB and vehicle assignments.
"""
from pathlib import Path
import argparse,csv,hashlib,json,sqlite3,zipfile
from collections import Counter,defaultdict

root=Path(__file__).resolve().parent.parent
pa=argparse.ArgumentParser()
pa.add_argument('--skip-dist',action='store_true')
a=pa.parse_args()
master=json.loads((root/'data/master-targets-v2.json').read_text(encoding='utf-8'))
manifest=json.loads((root/'Tools/manifest.json').read_text(encoding='utf-8'))
profiles=manifest['profiles']
assert master['release']==manifest['release']=='v1.3.0'
assert len(profiles)==42 and manifest['profile_count']==42
assert len(master['profiles'])==42 and master['count_cars']==565 and master['count_classes']==204
assert master['count_overrides']==10
assert len(master['build_fields'])==20
assert manifest['master_export_sha256']==master['source_export_sha256']
assert manifest['master_build_fields_count']==20
byid={s['id']:s for s in master['profiles']}
assert set(byid)=={f'P{i:02d}' for i in range(1,43)}
allcars=[]; uuids=set(); sha_lines=[]; fieldschecked=0; extras=[]
for record in profiles:
    pid=record['profile_id']; spec=byid[pid]
    fn=record['filename']
    assert fn.startswith(pid+'_') and '\\' not in fn and '/' not in fn
    path=root/'Profiles'/fn
    assert path.is_file(),path
    raw=path.read_bytes()
    sha=hashlib.sha256(raw).hexdigest()
    assert record['sha256']==sha, f'Bad SHA256 for {pid}'
    j=json.loads(raw.decode('utf-8-sig'))
    assert j['id']==record['uuid'] and j['id'] not in uuids,pid
    uuids.add(j['id'])
    assert j['version']==3 and j['tags']['gameId']==15 and j['tags']['deviceType']=='GMotion'
    assert j['tags']['devices']==['G01'] and j['deviceParams']['layout']=='F2B2'
    assert j['name']==record['name']==spec['name'],f'Naming master mismatch: {pid}'
    assert j['tags']['carModels']==record['cars']==spec['cars'],f'Car roster mismatch: {pid}'
    assert record['car_count']==len(spec['cars'])
    for dotted,expected in spec['settings'].items():
        section,key=dotted.split('.')
        actual=j['deviceParams'][section][key]
        assert type(actual) is type(expected), (pid,dotted,actual,expected)
        assert actual==expected, f'{pid} {dotted}: actual={actual!r}, master={expected!r}'
        fieldschecked+=1
    assert j['deviceParams']['platform']=={'maxMotionAngle':35,'tactileFeedbackValue':35}
    assert j['deviceParams']['AccToRoll']['Flatness']==j['deviceParams']['AccToPitch']['Flatness']==20
    assert j['deviceParams']['EngineVibration']['Frequency']==160
    allcars.extend(spec['cars'])
    sha_lines.append(f"{sha}  Profiles/{fn}")
# The user-tested Formula V10 setup is the lower-motion reference for the pack.
assert {k:byid['P07']['settings'][k] for k in (
    'Roll.Strength','Pitch.Strength','Heave.Strength','AccToRoll.Strength',
    'AccToPitch.Strength','Roll.Flatness','Pitch.Flatness'
)} == {
    'Roll.Strength':10, 'Pitch.Strength':20, 'Heave.Strength':5,
    'AccToRoll.Strength':10, 'AccToPitch.Strength':10,
    'Roll.Flatness':15, 'Pitch.Flatness':20,
}
for p in master['profiles']:
    v=p['settings']; pid=p['id']
    for field,lo,hi in (
        ('Roll.Strength',10,30),('Pitch.Strength',20,29),
        ('Heave.Strength',5,10),('AccToRoll.Strength',10,14),
        ('AccToPitch.Strength',10,14),('Roll.Flatness',15,27),
        ('Pitch.Flatness',20,28)):
        assert lo <= v[field] <= hi,(pid,field,v[field],lo,hi)

assert fieldschecked==840,fieldschecked
assert len(uuids)==42 and len(allcars)==565 and len(set(allcars))==565
assert len(list((root/'Profiles').glob('*.json')))==42
assert (root/'Tools/PRESET_SHA256.txt').read_text(encoding='utf-8')== '\n'.join(sha_lines)+'\n'
with (root/'docs/CAR-ASSIGNMENTS.csv').open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
assert len(rows)==565 and set(row['AMS2 vehicle name'] for row in rows)==set(allcars)
for row in rows:
    assert row['Group']==byid[row['Profile']]['name'].replace('AMS2 - MediocreAtBest - ','',1)
assert all(str(spec['name']).startswith('AMS2 - MediocreAtBest - ') for spec in master['profiles'])
assert len(set(spec['name'] for spec in master['profiles']))==42
assert ('LMDh / WEC Hypercar / IMSA GTP' in byid['P15']['name'])
assert ('1995-2000' in byid['P11']['name'])
# Only the derived, ID-free AMS2 additions and Windows SQLite injector may be shipped.
payload=root/'Tools/Database/ams2-additions.json'
injector=root/'Tools/Database/SqliteInjector.cs'
assert hashlib.sha256(payload.read_bytes()).hexdigest()==manifest['db_additions_sha256']
assert hashlib.sha256(injector.read_bytes()).hexdigest()==manifest['db_injector_sha256']
delta=json.loads(payload.read_text(encoding='utf-8'))
assert delta['format']==1 and delta['gameId']=='15' and len(delta['rows'])==manifest['db_added']==420
assert len({r['telemetryName'] for r in delta['rows']})==420
assert all(set(r)=={'telemetryName','name','category'} and r['name']==r['telemetryName'] and all(r.values()) for r in delta['rows'])
assert not any(p.is_file() and p.suffix.lower() in ('.db','.sqlite','.sqlite3') for p in root.rglob('*')), 'Database file must not be distributed'
assert not any(k.startswith('db_source_') or k.startswith('db_patched_') for k in manifest)

installer=(root/'Tools/SetupEngine.ps1').read_text(encoding='utf-8')
recovery=(root/'Tools/RecoveryEngine.ps1').read_text(encoding='utf-8')
assert "release = [string]$manifest.release" in installer
assert 'if ($overlap.Count -gt 0 -or $uuidMatch -or $filenameCollision)' in installer
assert 'Motion baseline mismatch' in installer
assert 'installed_hashes = $installedHashes' in installer and 'archived_hashes = $archivedHashes' in installer
assert 'installation_complete = $false' in installer
assert 'if (-not $changesStarted)' in installer and 'if (-not $changesStarted)' in recovery
assert 'Restore BLOCKED' in recovery and 'RestoreSafety-' in recovery
for launcher,engine in [('INSTALL.cmd','SetupEngine.ps1'),('RESTORE.cmd','RecoveryEngine.ps1')]:
    t=(root/launcher).read_text(encoding='ascii')
    assert 'Tools\\'+engine in t and 'powershell.exe' in t.lower() and 'pause' in t.lower()

# Public-facing documentation is a standalone product introduction while
# development builds remain private. Do not publish internal changelogs.
import re
assert not (root/'docs/RELEASE-NOTES.md').exists(), 'Private build history leaked into public docs'
for textfile in (root/'README.md',root/'README.txt',root/'docs/TECHNICAL.md',root/'docs/QA-REPORT.md'):
    t=textfile.read_text(encoding='utf-8')
    for forbidden in [r'\bv1\.0\.0\b', r'what changed in this version',
                      r'previous exported JSONs', r'preventing a repeat',
                      r'\brelease notes\b', r'\binternal (?:release|changelog|build) history\b']:
        assert not re.search(forbidden,t,re.I), (textfile,forbidden)

if not a.skip_dist:
    installer_zip=root/'dist/MediocreAtBest-AMS2-MOZA-v1.3.0.zip'
    assert installer_zip.is_file(),installer_zip
    allowed=['INSTALL.cmd','RESTORE.cmd','README.txt']
    allowed += ['Profiles/'+p['filename'] for p in profiles]
    allowed += ['Tools/Database/ams2-additions.json','Tools/Database/SqliteInjector.cs','Tools/PRESET_SHA256.txt','Tools/SetupEngine.ps1',
                'Tools/RecoveryEngine.ps1','Tools/manifest.json']
    with zipfile.ZipFile(installer_zip) as z:
        assert sorted(z.namelist())==sorted(allowed),'unexpected files in installer ZIP'
        for f in allowed:
            assert z.read(f)==(root/f).read_bytes(),f'ZIP not equal to repo file: {f}'
    sumfile=installer_zip.with_suffix('.zip.sha256')
    assert sumfile.is_file()
    assert sumfile.read_text(encoding='ascii').split()[0]==hashlib.sha256(installer_zip.read_bytes()).hexdigest()
print(f'PASS: 42 JSONs, 565 unique vehicles, {fieldschecked} V2 field comparisons, naming, hashes, DB, scripts'+(' and installer ZIP' if not a.skip_dist else ''))
