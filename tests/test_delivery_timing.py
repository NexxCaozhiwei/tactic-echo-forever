"""送达证据的时钟、摘要及帧关联回归，不执行真实输入。"""
from dataclasses import replace
import importlib.util
from pathlib import Path
from types import SimpleNamespace

from tek.src.engine import TraceRecord
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.trace import TraceSampler, trace_to_dict

spec = importlib.util.spec_from_file_location("delivery_analysis", Path(__file__).resolve().parents[1] / "scripts/analyze-delivery-timing.py")
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


def record(sequence=1, **kwargs):
    return TraceRecord(accepted=True, reason="input_sent", sequence=sequence, state="armed",
                       action_code=0, dispatcher_backend="dry_run", inputSent=True,
                       session_epoch=12, frame_freshness_counter=sequence, binding_token=3, **kwargs)


def test_observation_timestamp_is_captured_before_asynchronous_serialization():
    runner = TEKRunner(SimpleNamespace(process_frame=lambda frame, context: record()), SimpleNamespace(read=lambda: object()))
    row = runner.tick(RunnerConfig(assume_wow_foreground=True))
    timing = row.diagnostics["delivery_timing"]
    assert timing["readMS"] >= 0 and timing["processMS"] >= 0 and timing["foregroundCheckMS"] >= 0
    data = trace_to_dict(row, include_diagnostics=False)
    assert data["observedAt"] == timing["readCompletedAt"]
    assert data["writtenAt"] >= data["observedAt"]
    assert data["diagnostics"]["delivery_timing"] == timing


def test_success_aggregation_keeps_first_and_last_frame_timing():
    now = [0.0]
    sampler = TraceSampler(clock=lambda: now[0])
    sampler.records_to_write(record())
    now[0] = .1
    timing = {"readCompletedAt": "2026-11-09T00:00:00.100+00:00"}
    assert not sampler.records_to_write(record(2, diagnostics={"delivery_timing": timing}))
    now[0] = .2
    sampler.records_to_write(record(3))
    rows = sampler.records_to_write(replace(record(4), inputSent=False, reason="frame_state_paused"))
    summary = rows[0].diagnostics["input_sent_summary"]
    assert summary["first_sequence"] == 2 and rows[0].sequence == 3
    assert summary["first_delivery_timing"] == timing
    assert summary["count"] == 2


def test_frame_join_handles_wrap_and_rejects_conflicts_without_clock_guess():
    segment = dict(session=12, token=3, firstSequence=65535, lastSequence=0,
                   firstFreshness=65535, lastFreshness=0, requestedAt=10,
                   firstPublishedAt=10.01, initiatedAt=10.2)
    row = dict(session_epoch=12, binding_token=3, sequence=0, frame_freshness_counter=0,
               inputSent=True, reason="input_sent", diagnostics={"delivery_timing": {
                   "readCompletedAt": "2026-11-09T00:00:00.100+00:00",
                   "dispatchCompletedAt": "2026-11-09T00:00:00.120+00:00", "readMS": 8}})
    output = analysis.analyze([segment], [row])["segments"][0]
    assert output["requestToPublishMS"] == 10 and output["requestToInitiationMS"] == 200
    assert output["tekObservedToFirstSendMS"] == 20 and output["tekMaxReadMS"] == 8
    assert not analysis.matches(segment, {**row, "binding_token": 4})
    assert not analysis.matches(segment, {**row, "frame_freshness_counter": 1})
    conflict = analysis.analyze([segment, segment], [row])
    assert conflict["ambiguousRecords"] == 1
    assert all(r["matchedRecords"] == 0 for r in conflict["segments"])
