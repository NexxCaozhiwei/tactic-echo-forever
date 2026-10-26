import importlib.util
from pathlib import Path

import pytest


spec = importlib.util.spec_from_file_location(
    "tef_delivery_target", Path(__file__).resolve().parents[1] / "Tactic Echo Forever/scripts/deliver.py"
)
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


def test_explicit_deployment_target_requires_existing_addons_parent(tmp_path):
    addons = tmp_path / "client/Interface/AddOns"
    addons.mkdir(parents=True)
    target = addons / "Tactic Echo Forever"
    assert delivery.deployment_target(target) == target.resolve()
    for invalid in (Path("relative/Interface/AddOns/Tactic Echo Forever"),
                    tmp_path / "other/Tactic Echo Forever", addons / "Other Addon"):
        with pytest.raises(ValueError):
            delivery.deployment_target(invalid)


def test_parent_traversal_cannot_bypass_resolved_target_validation(tmp_path):
    addons = tmp_path / "client/Interface/AddOns"
    addons.mkdir(parents=True)
    with pytest.raises(ValueError):
        delivery.deployment_target(addons / "../Tactic Echo Forever")
