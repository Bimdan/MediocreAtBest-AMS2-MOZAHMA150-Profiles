from pathlib import Path
import argparse,json,sqlite3
p=argparse.ArgumentParser();p.add_argument('path',type=Path);p.add_argument('--complete',action='store_true');p.add_argument('--partial',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
delta=json.loads((Path(__file__).resolve().parents[1]/'Tools/Database/ams2-additions.json').read_text(encoding='utf-8'))['rows']
if a.path.exists():a.path.unlink()
with sqlite3.connect(a.path) as c:
 c.execute('CREATE TABLE CarModels(id INTEGER PRIMARY KEY AUTOINCREMENT, gameId TEXT NOT NULL, telemetryName TEXT, name TEXT, category TEXT'+(', extra TEXT' if a.unsupported else '')+')')
 c.execute('CREATE INDEX idx_car_models_game_telemetry ON CarModels(gameId, telemetryName)')
 c.executemany('INSERT INTO CarModels(gameId,telemetryName,name,category) VALUES(?,?,?,?)',[('2','fixture-other','Unrelated game','Fixture'),('15','fixture-existing','Existing AMS2','Fixture')])
 if a.complete:c.executemany("INSERT INTO CarModels(gameId,telemetryName,name,category) VALUES('15',?,?,?)",[(r['telemetryName'],r['name'],r['category']) for r in delta])
 if a.partial:c.execute("INSERT INTO CarModels(gameId,telemetryName,name,category) VALUES('15',?,'User customised name','User category')",(delta[0]['telemetryName'],))
