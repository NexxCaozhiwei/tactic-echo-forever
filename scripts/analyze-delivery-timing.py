"""按既有帧身份关联插件与TEK证据，不假定两端时钟具有相同起点。"""
import argparse
from datetime import datetime
import json
from pathlib import Path


def matches(segment, row):
    if (row.get("session_epoch") != segment.get("session")
            or row.get("binding_token") != segment.get("token")):
        return False
    sequence, freshness = row.get("sequence"), row.get("frame_freshness_counter")
    if not isinstance(sequence, int) or not isinstance(freshness, int):
        return False
    span = (segment["lastSequence"]-segment["firstSequence"]) % 65536
    fresh_span = (segment["lastFreshness"]-segment["firstFreshness"]) % 65536
    delta = (sequence-segment["firstSequence"]) % 65536
    return span < 4096 and span == fresh_span and delta <= span and delta == (freshness-segment["firstFreshness"]) % 65536


def elapsed_ms(start, end):
    try:
        delta = (datetime.fromisoformat(end)-datetime.fromisoformat(start)).total_seconds()*1000
        return round(delta, 3) if delta >= 0 else None
    except (ValueError, TypeError):
        return None


def analyze(segments, records):
    groups = [[] for _ in segments]
    ambiguous = 0
    for record in records:
        variants = [record]
        summary = (record.get("diagnostics") or {}).get("input_sent_summary") or {}
        first_timing = summary.get("first_delivery_timing")
        if first_timing:
            variants.append({**record, "sequence": summary.get("first_sequence"),
                             "session_epoch": summary.get("first_session"),
                             "binding_token": summary.get("first_binding_token"),
                             "frame_freshness_counter": summary.get("first_freshness_counter"),
                             "observedAt": first_timing.get("readCompletedAt"),
                             "diagnostics": {"delivery_timing": first_timing}})
        for row in variants:
            candidates = [i for i, segment in enumerate(segments) if matches(segment, row)]
            if len(candidates) == 1:
                groups[candidates[0]].append(row)
            elif len(candidates) > 1:
                ambiguous += 1
    results = []
    for segment, rows in zip(segments, groups):
        output = {**segment, "matchedRecords": len(rows)}
        requested, published, initiated = (segment.get(key) for key in ("requestedAt", "firstPublishedAt", "initiatedAt"))
        output["requestToPublishMS"] = round((published-requested)*1000, 3) if requested is not None and published >= requested else None
        output["requestToInitiationMS"] = round((initiated-requested)*1000, 3) if initiated is not None and requested is not None and initiated >= requested else None
        timings = [(r.get("diagnostics") or {}).get("delivery_timing") or {} for r in rows]
        observed = sorted(t["readCompletedAt"] for t in timings if t.get("readCompletedAt"))
        sent = sorted(((r.get("diagnostics") or {}).get("delivery_timing") or {}).get("dispatchCompletedAt")
                      for r in rows if r.get("inputSent") and ((r.get("diagnostics") or {}).get("delivery_timing") or {}).get("dispatchCompletedAt"))
        output["tekObservedToFirstSendMS"] = elapsed_ms(observed[0], sent[0]) if observed and sent else None
        for key in ("readMS", "foregroundCheckMS", "processMS", "dispatchMS"):
            values = [t[key] for t in timings if isinstance(t.get(key), (int, float)) and t[key] >= 0]
            output["tekMax"+key[0].upper()+key[1:]] = round(max(values), 3) if values else None
        output["tekReasons"] = sorted({r.get("reason", "未知") for r in rows})
        results.append(output)
    return {"clockBoundary": "两端时钟起点未经校准，不直接计算插件发布至TEK识别的单向耗时；仅关联帧身份并分别测量同端阶段。",
            "ambiguousRecords": ambiguous, "segments": results}


def read_segments(path):
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime()
    environment = lua.table()
    lua.eval("function(s,e) local f=assert(loadstring(s));setfenv(f,e);f() end")(
        Path(path).read_text(encoding="utf-8-sig"), environment)
    database = environment.TEF_DB
    rows = database.deliveryDiagnostics if database is not None else None
    return [dict(rows[i].items()) for i in range(1, len(rows)+1)] if rows is not None else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", required=True)
    parser.add_argument("--trace", nargs="+", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    records = []
    for name in args.trace:
        for line in Path(name).read_text(encoding="utf-8-sig").splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    result = analyze(read_segments(args.saved_variables), records)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        destination = Path(args.output)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text+"\n", encoding="utf-8")
    else:
        print(text)


if __name__ == "__main__":
    main()
