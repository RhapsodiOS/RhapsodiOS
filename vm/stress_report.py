"""Parse, summarize and compare the STRESS lines the stress suite prints.

    python vm/stress_report.py A/result.txt B/result.txt   rate table, A -> B
"""
import json
import re
import sys

FIELD = re.compile(r'(\w+)=("[^"]*"|\S+)')
NUMBER = re.compile(r"-?(0|[1-9]\d*)(\.\d+)?$")


def _value(key, v):
    if v.startswith('"'):
        return v[1:-1]
    if key == "ops" and v.endswith("/s"):
        v = v[:-2]
    elif key == "maxlat" and v.endswith("ms"):
        v = v[:-2]
    if NUMBER.match(v):
        return float(v) if "." in v else int(v)
    return v


def parse(text):
    rows = []
    for line in text.splitlines():
        f = line.split(None, 4)
        if len(f) < 4 or f[0] != "STRESS":
            continue
        row = {"cat": f[1], "test": f[2], "result": f[3], "raw": line.strip()}
        for k, v in FIELD.findall(f[4] if len(f) > 4 else ""):
            row[k] = _value(k, v)
        rows.append(row)
    return rows


def summarize(rows):
    counts, fails, leaks, rates = {}, [], [], {}
    for r in rows:
        c = counts.setdefault(r["cat"], {"PASS": 0, "FAIL": 0, "UNSUP": 0})
        c[r["result"]] = c.get(r["result"], 0) + 1
        if r["result"] == "FAIL":
            fails.append(r["raw"])
        if "leak" in r or "wired" in r or "mbufs" in r:
            leaks.append(r["raw"])
        if "ops" in r and "maxlat" in r:
            t = rates.setdefault("%s.%s" % (r["cat"], r["test"]),
                                 {"ops": r["ops"], "maxlat": r["maxlat"]})
            t["ops"] = max(t["ops"], r["ops"])
            t["maxlat"] = max(t["maxlat"], r["maxlat"])
    return {"counts": counts, "fails": fails, "leaks": leaks, "rates": rates}


def compare(a, b):
    out = []
    for name in a["rates"]:
        if name in b["rates"]:
            x, y = a["rates"][name], b["rates"][name]
            pct = round((y["ops"] - x["ops"]) * 100.0 / x["ops"], 1) if x["ops"] else 0.0
            out.append((name, x["ops"], y["ops"], pct, x["maxlat"], y["maxlat"]))
    return sorted(out, key=lambda t: t[3])


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__)
    docs = []
    for path in argv[1:]:
        with open(path, encoding="utf-8") as f:
            docs.append(json.load(f))
    print("%-28s %10s %10s %8s %8s %8s" % ("test", "ops A", "ops B", "change", "lat A", "lat B"))
    for name, oa, ob, pct, la, lb in compare(*docs):
        print("%-28s %10s %10s %+7.1f%% %7sms %7sms" % (name, oa, ob, pct, la, lb))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
