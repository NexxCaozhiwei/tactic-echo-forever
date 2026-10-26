import unittest

from tek.src.input_planner import InputPlanError, plan_binding
import ctypes

from tek.src.windows_sendinput import INPUT, VIRTUAL_KEYS, WindowsSendInputDispatcher


class WindowsSendInputTests(unittest.TestCase):
    def test_partial_main_key_is_released_but_physical_hold_defers_cleanup(self):
        class Native:
            def __init__(self): self.calls = []
            def SendInput(self, count, inputs, size):
                self.calls.append([(int(inputs[i].union.ki.wVk), int(inputs[i].union.ki.dwFlags)) for i in range(count)])
                return 1 if len(self.calls) == 1 else count
            def GetLastError(self): return 5
        native = Native(); held = {"2"}
        dispatcher = WindowsSendInputDispatcher(user32=native, kernel32=native, physical_key_checker=lambda key: key in held)
        self.assertFalse(dispatcher.dispatch(plan_binding("2")).sent)
        self.assertEqual(dispatcher.release_modifiers().reason, "input_recovery_wait_physical_release")
        self.assertFalse(dispatcher.dispatch(plan_binding("3")).sent)
        self.assertEqual(len(native.calls), 1)
        held.clear()
        self.assertEqual(dispatcher.dispatch(plan_binding("3")).reason, "input_recovery_completed_wait_fresh_frame")
        self.assertEqual(native.calls[-1], [(0x32, 2)])
        self.assertTrue(dispatcher.dispatch(plan_binding("3")).sent)

    def test_every_partial_modifier_plan_prefix_cleans_only_unreleased_keys(self):
        for cut in range(4):
            class Native:
                calls = 0
                def SendInput(self, count, inputs, size):
                    self.calls += 1
                    return cut if self.calls == 1 else count
                def GetLastError(self): return 5
            native = Native()
            dispatcher = WindowsSendInputDispatcher(user32=native, kernel32=native, physical_key_checker=lambda key: False)
            dispatcher.dispatch(plan_binding("SHIFT+Z"))
            self.assertTrue(dispatcher.release_modifiers().sent)
            self.assertEqual(dispatcher._unreleased_keys, [])

    def test_recovery_rechecks_ownership_after_building_release_plan(self):
        class Native:
            calls = 0
            def SendInput(self, count, inputs, size): self.calls += 1; return 1
            def GetLastError(self): return 5
        native = Native(); readings = iter((False, True))
        dispatcher = WindowsSendInputDispatcher(user32=native, kernel32=native,
            physical_key_checker=lambda key: next(readings))
        dispatcher.dispatch(plan_binding("2"))
        self.assertEqual(dispatcher.release_modifiers().reason, "input_recovery_wait_physical_release")
        self.assertEqual(native.calls, 1)
        self.assertEqual(dispatcher._unreleased_keys, ["2"])

    def test_required_p0_keys_have_virtual_key_codes(self):
        for key in ["SHIFT", "Z", "X", "C", "G", "H", "N", "R", "T", "Y", "0", "-", "="]:
            self.assertIn(key, VIRTUAL_KEYS)

    def test_windows_input_structure_has_expected_size(self):
        self.assertIn(ctypes.sizeof(INPUT), (28, 40))

    def test_laptop_binding_can_be_planned_for_sendinput_backend(self):
        plan = plan_binding("SHIFT+Z")

        self.assertEqual(
            [event.key for event in plan.events],
            ["SHIFT", "Z", "Z", "SHIFT"],
        )

    def test_digit_binding_can_be_planned_for_sendinput_backend(self):
        plan = plan_binding("SHIFT+0")

        self.assertEqual(
            [event.key for event in plan.events],
            ["SHIFT", "0", "0", "SHIFT"],
        )

    def test_oem_bindings_can_be_planned_for_sendinput_backend(self):
        for binding, key in (("SHIFT+-", "-"), ("SHIFT+=", "=")):
            with self.subTest(binding=binding):
                plan = plan_binding(binding)
                self.assertEqual(
                    [event.key for event in plan.events],
                    ["SHIFT", key, key, "SHIFT"],
                )

    def test_input_plan_rejects_duplicate_modifier(self):
        with self.assertRaisesRegex(InputPlanError, "duplicate_modifier:SHIFT"):
            plan_binding("SHIFT+SHIFT+Z")

    def test_input_plan_rejects_unknown_key(self):
        with self.assertRaisesRegex(InputPlanError, "unsupported_key:NUMPAD1"):
            plan_binding("CTRL+NUMPAD1")

    def test_input_plan_rejects_multiple_main_keys(self):
        with self.assertRaisesRegex(InputPlanError, "invalid_main_key_count:2"):
            plan_binding("SHIFT+Z+X")

    def test_sendinput_fake_backend_reports_partial_with_last_error(self):
        class FakeKernel32:
            def GetLastError(self):
                return 5

        class FakeSendInput:
            def __call__(self, count, inputs, size):
                return count - 1

        class FakeUser32:
            SendInput = FakeSendInput()

        dispatcher = WindowsSendInputDispatcher(user32=FakeUser32(), kernel32=FakeKernel32())
        result = dispatcher.dispatch(plan_binding("SHIFT+Z"))

        self.assertFalse(result.sent)
        self.assertIn("sendinput_partial:3:4:last_error:5", result.reason)


if __name__ == "__main__":
    unittest.main()
