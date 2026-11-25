#!/usr/bin/env python3
"""Freeze precisely the approved V2 motion fields and assignments from a Sheets XLSX export.

Run this when a new master export is approved, then regenerate/validate the
profiles with tools/build_profiles.py. The private research workbook is never
included in the public repository.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from collections import Counter, defaultdict
import openpyxl

ROOT = Path(__file__).resolve().parent.parent
FIELDS = {
    'Roll.Strength': 5, 'Pitch.Strength': 6, 'Heave.Strength': 7,
    'AccToRoll.Strength': 8, 'AccToPitch.Strength': 9,
    'RoadDetail.Strength': 10, 'GearShift.Strength': 11,
    'EngineVibration.Strength': 12, 'WheelSlip.Strength': 13,
    'Roll.Flatness': 14, 'Pitch.Flatness': 15, 'Heave.Flatness': 16,
    'AccToRoll.Flatness': 17, 'AccToPitch.Flatness': 18,
    'RoadDetail.Flatness': 19, 'EngineVibration.Frequency': 20,
    'ABSTrigger.enabled': 21, 'TractionControl.enabled': 22,
    'platform.maxMotionAngle': 23, 'platform.tactileFeedbackValue': 24,
}

def rows(ws):
    return list(ws.iter_rows(values_only=True))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('xlsx', type=Path, help='Native V2 Google Sheets export (.xlsx)')
    parser.add_argument('--out', type=Path, default=ROOT/'data/master-targets-v2.json')
    args = parser.parse_args()
    book = openpyxl.load_workbook(args.xlsx, data_only=True, read_only=True)
    profiles = rows(book['V2 - Profile Tuning'])
    roster = rows(book['V2 - Car Assignments'])
    classes = rows(book['V2 - Class Map'])
    readme = dict((r[0],r[1]) for r in rows(book['V2 - Read Me'])[1:] if r[0])
    qc = rows(book['V2 - QA'])
    for r in qc[1:]:
        if r[0] and r[3] != 'PASS': raise ValueError(f"Source sheet QA not passing: {r[0]} = {r[3]}")
    assigned = defaultdict(list)
    originals = defaultdict(list)
    override_count = 0
    for r in roster[1:]:
        if not r[0]: continue
        p = r[4]
        assigned[p].append(str(r[0]))
        originals[p].append((str(r[1]),str(r[2])))
        if str(r[8]).strip().upper() == 'YES':override_count += 1
    assert len(roster)-1 >= 565
    assert sum(map(len,assigned.values())) == 565
    assert len(set(n for cars in assigned.values() for n in cars)) == 565
    cls = [r for r in classes[1:] if r[0]]
    assert len(cls)==204, len(cls)
    assert override_count==10,override_count
    result=[]
    for r in profiles[1:]:
        if not r[0]: continue
        pid=str(r[0]); assert pid in assigned, pid
        settings={}
        for field,idx in FIELDS.items():
            value=r[idx]
            if field.endswith('.enabled'):
                assert isinstance(value,bool),(pid,field,value)
            else:
                assert isinstance(value,(int,float)),(pid,field,value)
                assert float(value).is_integer(),(pid,field,value)
                value=int(value)
            settings[field]=value
        assert settings['platform.maxMotionAngle']==35 and settings['platform.tactileFeedbackValue']==35,pid
        assert settings['AccToRoll.Flatness']==20 and settings['AccToPitch.Flatness']==20,pid
        assert settings['EngineVibration.Frequency']==160,pid
        assert int(r[3])==len(assigned[pid]),pid
        assert str(r[1]).startswith('AMS2 - '),pid
        display_name='AMS2 - MediocreAtBest - '+str(r[1]).split(' - ',2)[2]
        result.append({'id':pid,'name':display_name,'cars':sorted(assigned[pid]),'settings':settings})
    assert len(result)==42,len(result)
    assert set(p['id'] for p in result)=={f'P{i:02d}' for i in range(1,43)}
    by_id={p['id']:p for p in result}
    for r in cls:
        assert r[3] in by_id, (r[0],r[3])
        assert str(r[4]).split(' - ',2)[2]==by_id[r[3]]['name'].split(' - ',2)[2], (r[0],r[4])
    for r in roster[1:]:
        if not r[0]:continue
        assert str(r[5]).split(' - ',2)[2]==by_id[r[4]]['name'].split(' - ',2)[2],r[0]
    assert all(p['settings']['AccToRoll.Flatness']==20 for p in result)
    out={
        'schema':'MediocreAtBest AMS2 V2 immutable build-target snapshot v1',
        'source_url':'Private source workbook (not distributed)',
        'source_export_sha256':hashlib.sha256(args.xlsx.read_bytes()).hexdigest(),
        'source_export_date':'2026-11-25',
        'release':'v1.3.0',
        'count_profiles':42,'count_cars':565,'count_classes':204,'count_overrides':10,
        'naming_policy':'Names begin AMS2 - MediocreAtBest - followed by class and era.',
        'build_fields':list(FIELDS.keys()),
        'profiles':result,
    }
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"FROZEN: {len(result)} profiles, {sum(len(p['cars']) for p in result)} cars, 20 mapped fields/profile, xlsx SHA {out['source_export_sha256'][:16]}")

if __name__=='__main__':main()
