from pathlib import Path
import argparse,json,sqlite3
p=argparse.ArgumentParser();p.add_argument('path',type=Path);p.add_argument('--partial',action='store_true');a=p.parse_args()
delta=json.loads((Path(__file__).resolve().parents[1]/'Tools/Database/ams2-additions.json').read_text(encoding='utf-8'))['rows']
with sqlite3.connect(f'file:{a.path}?mode=ro',uri=True) as c:
 assert c.execute('PRAGMA integrity_check').fetchone()==('ok',)
 assert c.execute('SELECT * FROM CarModels WHERE id IN (1,2) ORDER BY id').fetchall()==[(1,'2','fixture-other','Unrelated game','Fixture'),(2,'15','fixture-existing','Existing AMS2','Fixture')]
 assert c.execute('SELECT COUNT(*) FROM CarModels').fetchone()[0]==422
 for i,r in enumerate(delta):
  x=c.execute("SELECT name,category FROM CarModels WHERE gameId='15' AND telemetryName=? COLLATE BINARY",(r['telemetryName'],)).fetchall()
  assert x==([('User customised name','User category')] if a.partial and i==0 else [(r['name'],r['category'])]),(i,x)
print('PASS: all 420 AMS2 keys present; original and custom records unchanged')
