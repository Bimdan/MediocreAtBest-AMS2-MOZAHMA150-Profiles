// Uses the SQLite library shipped with supported Windows 10/11 installations.
// No third-party SQLite binaries or MOZA database are included.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Linq;

public static class MediocreAtBestSqliteInjector {
    private const string Library = "winsqlite3.dll";
    private const int OK = 0, ROW = 100, DONE = 101;
    private static readonly IntPtr Transient = new IntPtr(-1);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_open_v2(byte[] path, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_close_v2(IntPtr db);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int bytes, out IntPtr stmt, IntPtr tail);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int bytes, IntPtr destructor);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_step(IntPtr stmt);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_column_type(IntPtr stmt, int col);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern IntPtr sqlite3_column_text(IntPtr stmt, int col);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_column_bytes(IntPtr stmt, int col);
    [DllImport(Library, CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_changes(IntPtr db);

    private static byte[] Utf8(string value) { return Encoding.UTF8.GetBytes(value + "\0"); }
    private static string ReadUtf8(IntPtr ptr, int bytes) {
        if (ptr == IntPtr.Zero) return null;
        byte[] b = new byte[bytes]; if (bytes > 0) Marshal.Copy(ptr,b,0,bytes);
        return Encoding.UTF8.GetString(b);
    }
    private static string Error(IntPtr db) {
        if (db == IntPtr.Zero) return "Could not open SQLite database";
        IntPtr p = sqlite3_errmsg(db); int n=0; while (p != IntPtr.Zero && Marshal.ReadByte(p,n) != 0) n++;
        return ReadUtf8(p,n);
    }
    private static void Check(IntPtr db,int rc,string where) {
        if (rc != OK) throw new InvalidOperationException(where + ": " + Error(db) + " (SQLite " + rc + ")");
    }
    private static List<string[]> Query(IntPtr db,string sql,params string[] args) {
        IntPtr st=IntPtr.Zero;
        try {
            byte[] statement=Utf8(sql);
            Check(db,sqlite3_prepare_v2(db,statement,statement.Length-1,out st,IntPtr.Zero),"Prepare");
            for(int i=0;i<args.Length;i++) {
                byte[] value=Utf8(args[i]); Check(db,sqlite3_bind_text(st,i+1,value,value.Length-1,Transient),"Bind");
            }
            List<string[]> rows=new List<string[]>(); int rc;
            while((rc=sqlite3_step(st))==ROW) {
                int cols=sqlite3_column_count(st); string[] row=new string[cols];
                for(int i=0;i<cols;i++) {
                    if(sqlite3_column_type(st,i)==5) row[i]=null;
                    else { IntPtr ptr=sqlite3_column_text(st,i); row[i]=ReadUtf8(ptr,sqlite3_column_bytes(st,i)); }
                }
                rows.Add(row);
            }
            if(rc!=DONE) Check(db,rc,"Execute");
            return rows;
        } finally { if(st!=IntPtr.Zero) sqlite3_finalize(st); }
    }
    private static void Integrity(IntPtr db) {
        List<string[]> r=Query(db,"PRAGMA integrity_check");
        if(r.Count!=1 || r[0][0]!="ok") throw new InvalidOperationException("SQLite integrity check failed");
    }
    private static void Schema(IntPtr db) {
        // Fail closed for an unexpected schema or journal mode. Do not change it.
        var table=Query(db,"SELECT type,sql FROM sqlite_master WHERE name='CarModels' COLLATE BINARY");
        if(table.Count!=1 || table[0][0]!="table" || table[0][1]==null || table[0][1].IndexOf("VIRTUAL",StringComparison.OrdinalIgnoreCase)>=0)
            throw new InvalidOperationException("Unsupported CarModels table");
        var cols=Query(db,"PRAGMA table_info(CarModels)");
        string[] names={"id","gameId","telemetryName","name","category"};
        if(cols.Count!=5) throw new InvalidOperationException("Unsupported CarModels column count");
        for(int i=0;i<5;i++) {
            if(cols[i][1]!=names[i] || !String.Equals(cols[i][2],i==0?"INTEGER":"TEXT",StringComparison.OrdinalIgnoreCase) || cols[i][5]!=(i==0?"1":"0"))
                throw new InvalidOperationException("Unsupported CarModels column definition");
        }
        if(Query(db,"SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='CarModels' COLLATE NOCASE").Count!=0)
            throw new InvalidOperationException("Custom CarModels triggers are not supported");
        var journal=Query(db,"PRAGMA journal_mode");
        if(journal.Count!=1 || journal[0][0]!="delete") throw new InvalidOperationException("Database journal mode is not DELETE; leaving database untouched");
        Integrity(db);
    }
    // Flat triples are UTF-8 bound values. The game ID is deliberately hard-coded;
    // IDs are allocated by the local database, not copied from the reference.
    private const string ExistsSql="SELECT 1 FROM CarModels WHERE gameId='15' COLLATE BINARY AND telemetryName=? COLLATE BINARY LIMIT 1";
    private const string InsertSql="INSERT INTO CarModels(gameId,telemetryName,name,category) SELECT '15',?,?,? WHERE NOT EXISTS (SELECT 1 FROM CarModels WHERE gameId='15' COLLATE BINARY AND telemetryName=? COLLATE BINARY)";
    private const string SnapshotSql="SELECT id,typeof(gameId),gameId,typeof(telemetryName),telemetryName,typeof(name),name,typeof(category),category FROM CarModels ORDER BY id";
    public static int Run(string path,string[] rows,bool apply) {
        if(rows==null || rows.Length!=1260) throw new InvalidOperationException("Expected exactly 420 AMS2 records");
        var names=new HashSet<string>(StringComparer.Ordinal);
        for(int i=0;i<rows.Length;i+=3) {
            if(String.IsNullOrEmpty(rows[i]) || String.IsNullOrEmpty(rows[i+1]) || String.IsNullOrEmpty(rows[i+2]) || !names.Add(rows[i]) || rows[i]!=rows[i+1])
                throw new InvalidOperationException("Invalid or duplicate AMS2 addition");
        }
        IntPtr db=IntPtr.Zero; bool tx=false;
        try {
            // READONLY for preview, READWRITE without CREATE for staging.
            int opened=sqlite3_open_v2(Utf8(path),out db,apply?2:1,IntPtr.Zero); Check(db,opened,"Open");
            Check(db,sqlite3_busy_timeout(db,1500),"Busy timeout");
            if(apply) { Query(db,"PRAGMA foreign_keys=ON"); Query(db,"BEGIN IMMEDIATE"); tx=true; }
            Schema(db);
            int missing=0;
            for(int i=0;i<rows.Length;i+=3) if(Query(db,ExistsSql,rows[i]).Count==0) missing++;
            if(!apply) return missing;
            if(missing==0) { Query(db,"ROLLBACK"); tx=false; return 0; }
            var before=Query(db,SnapshotSql); int inserted=0;
            for(int i=0;i<rows.Length;i+=3) {
                Query(db,InsertSql,rows[i],rows[i+1],rows[i+2],rows[i]);
                int count=sqlite3_changes(db); if(count!=0 && count!=1) throw new InvalidOperationException("Unexpected insertion count"); inserted+=count;
            }
            if(inserted!=missing) throw new InvalidOperationException("Insertion count changed during transaction");
            var after=Query(db,SnapshotSql);
            if(after.Count!=before.Count+inserted) throw new InvalidOperationException("Unexpected total record count");
            var byId=after.ToDictionary(x=>x[0],StringComparer.Ordinal);
            foreach(var old in before) { string[] now; if(!byId.TryGetValue(old[0],out now) || !old.SequenceEqual(now)) throw new InvalidOperationException("An original database row changed"); }
            for(int i=0;i<rows.Length;i+=3) if(Query(db,ExistsSql,rows[i]).Count==0) throw new InvalidOperationException("Expected AMS2 row missing");
            Integrity(db);
            Query(db,"COMMIT"); tx=false;
            return inserted;
        } catch { if(tx && db!=IntPtr.Zero) { try { Query(db,"ROLLBACK"); } catch {} } throw; }
        finally { if(db!=IntPtr.Zero) sqlite3_close_v2(db); }
    }
}
