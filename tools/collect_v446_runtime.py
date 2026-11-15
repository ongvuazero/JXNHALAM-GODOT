from pathlib import Path
import os,sys,shutil,csv
root = Path(__file__).resolve().parent.parent
out = root / "reports" / "v44_6" / "runtime"
out.mkdir(parents=True, exist_ok=True)
appdata = os.getenv("APPDATA", "")
if not appdata:
    print("ERROR: APPDATA not set; run this on the Windows PC running Godot.")
    sys.exit(1)
base = Path(appdata)/"Godot"/"app_userdata"
if not base.is_dir():
    print("ERROR: Godot app_userdata directory not found:",base)
    sys.exit(1)
names = ["JXNHALAM_VFX_LINKED_10PHAI_RUNTIME.csv", "JXNHALAM_VFX_10PHAI_HASH_AUDIT.csv"]
found_count=0
for name in names:
    hits=list(base.rglob(name))
    if not hits:
        print("MISSING:",name,"-- open V44.6, press F10 in gameplay first")
        continue
    latest=max(hits,key=lambda p:p.stat().st_mtime)
    target=out/name
    shutil.copy2(latest,target)
    print("COPIED",latest,"=>",target)
    found_count+=1
    if name.endswith("LINKED_10PHAI_RUNTIME.csv"):
        with target.open(encoding="utf-8-sig",newline="") as f:
            rows=list(csv.DictReader(f))
        counts={}
        for r in rows:
            status=r.get("status","")
            counts[status]=counts.get(status,0)+1
        print("STAGE COUNTS",counts)
print("Reports at:",out)
sys.exit(0 if found_count==2 else 1)
