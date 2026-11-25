#!/usr/bin/env python3
"""Generate / verify MOZA JSONs directly from the frozen V2 approved targets.

Only schema fields absent from the approved master are retained from the
existing MOZA-compatible JSON structure; mapped fields are ALL overwritten and
must equal the master. UUIDs stay unchanged so v1.0.0 upgrades don't duplicate
car assignments. Run tests/check_package.py after rebuilding.
"""
from pathlib import Path
import argparse, csv, hashlib, json
from copy import deepcopy

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT/'data/master-targets-v2.json'
MANIFEST = ROOT/'Tools/manifest.json'
PROFILES = ROOT/'Profiles'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    pa=argparse.ArgumentParser()
    pa.add_argument('--check',action='store_true',help='validate current files without changing anything')
    a=pa.parse_args()
    frozen=json.loads(SOURCE.read_text(encoding='utf-8'))
    manifest=json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert frozen['release']=='v1.3.0'
    assert len(frozen['profiles'])==len(manifest['profiles'])==42
    src={s['id']:s for s in frozen['profiles']}
    manifest['release']=frozen['release']
    manifest['date']='2026-11-25'
    manifest['master_export_sha256']=frozen['source_export_sha256']
    manifest['master_source_url']=frozen['source_url']
    manifest['master_build_fields_count']=len(frozen['build_fields'])
    updated=[]
    for p in manifest['profiles']:
        s=src[p['profile_id']]
        path=PROFILES/p['filename']
        j=json.loads(path.read_text(encoding='utf-8-sig'))
        assert j['id']==p['uuid']
        assert set(j['tags']['carModels'])==set(s['cars']),p['profile_id']
        assert len(s['cars'])==p['car_count']
        assert j['deviceParams']['layout']=='F2B2' and j['tags']['gameId']==15
        j['name']=s['name']
        j['tags']['carModels']=s['cars']
        j['lastModified']='2026-11-25T21:30:00'
        for field,value in s['settings'].items():
            segment,key=field.split('.')
            assert segment in j['deviceParams'] and key in j['deviceParams'][segment], (p['profile_id'],field)
            assert type(j['deviceParams'][segment][key]) is type(value), (p['profile_id'],field)
            j['deviceParams'][segment][key]=value
        content=json.dumps(j,ensure_ascii=False,sort_keys=True,indent=2)+'\n'
        data=content.encode('utf-8')
        if not a.check: path.write_bytes(data)
        else: assert path.read_bytes()==data, (p['profile_id'],'not deterministic build')
        p['name']=s['name']
        p['cars']=s['cars']
        p['sha256']=hashlib.sha256(data).hexdigest()
        updated.append(p)
    manifest['profiles']=updated
    man_bytes=(json.dumps(manifest,ensure_ascii=False,sort_keys=False,indent=2)+'\n').encode('utf-8')
    if not a.check:MANIFEST.write_bytes(man_bytes)
    else: assert MANIFEST.read_bytes()==man_bytes, 'manifest not up to date'
    sha_lines=[f"{p['sha256']}  Profiles/{p['filename']}" for p in updated]
    text='\n'.join(sha_lines)+'\n'
    if not a.check:(ROOT/'Tools/PRESET_SHA256.txt').write_text(text,encoding='utf-8')
    else:assert (ROOT/'Tools/PRESET_SHA256.txt').read_text(encoding='utf-8')==text
    if not a.check:
        with (ROOT/'docs/CAR-ASSIGNMENTS.csv').open('w',encoding='utf-8-sig',newline='') as f:
            w=csv.writer(f);w.writerow(['Profile','Group','AMS2 vehicle name'])
            for p in updated:
                for car in p['cars']:
                    w.writerow([p['profile_id'],p['name'].replace('AMS2 - MediocreAtBest - ','',1),car])
        group_md=['# Profile groups','','Recognisable AMS2 class/search terms come first, followed by useful series names and generation years.','','Each car belongs to one group. Motion strengths reflect broad chassis characteristics; acceleration smoothness is a common responsiveness setting, not car-specific.','', '| ID | Search-friendly MOZA profile name | Cars |','|---|---|---:|']
        for p in updated:group_md.append(f"| {p['profile_id']} | {p['name']} | {p['car_count']} |")
        group_md+=['','See [CAR-ASSIGNMENTS.csv](CAR-ASSIGNMENTS.csv) for exact AMS2 vehicle names.','']
        (ROOT/'docs/PROFILES.md').write_text('\n'.join(group_md),encoding='utf-8')
    print(f"PASS: {len(updated)} profiles, 565 cars, 20 V2 fields each; release {manifest['release']}")

if __name__=='__main__':main()
