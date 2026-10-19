import unittest
from dataclasses import replace

from tek.app.status_window import _monitor_label
from tek.runtime.runtime_status import TEKStatusSnapshot


class StatusMonitorLabelTests(unittest.TestCase):
    def test_absent_telemetry_is_not_reported_as_no_alert(self):
        self.assertEqual(_monitor_label(TEKStatusSnapshot.stopped()), "当前信号未提供此监控")

    def test_reported_monitor_flags_still_have_labels(self):
        snapshot = replace(TEKStatusSnapshot.stopped(), last_target_casting=True,
                           last_target_interruptible=True, last_player_health_critical=True)
        self.assertEqual(_monitor_label(snapshot), "目标读条 / 可打断 / 低血预警")

    def test_zero_flags_do_not_claim_an_observed_clear_state(self):
        snapshot = replace(TEKStatusSnapshot.stopped(), last_target_casting=False,
                           last_target_interruptible=False, last_player_health_critical=False)
        self.assertNotIn("无监控告警", _monitor_label(snapshot))
