"""Integration tests for RLM-DEPLOY API."""

from __future__ import annotations

import pytest
from unittest.mock import patch

from src.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


class TestHealthzIntegration:
    """Integration tests for /healthz endpoint (used by KIX orchestrator)."""

    def test_healthz_for_kix(self, client):
        """Healthz endpoint returns simple OK for KIX probing."""
        resp = client.get("/healthz")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["status"] == "ok"


class TestDeployIntegration:
    """Integration tests for /deploy endpoint with KIX."""

    def test_deploy_flow(self, client):
        """Full deploy flow: health → deploy → status → rollback."""
        # 1. Health check
        health = client.get("/health")
        assert health.status_code == 200

        # 2. Deploy a service (mocked KIX call)
        with patch("src.app.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            deploy_resp = client.post("/deploy", json={"service": "RLM-SECURE"})
            assert deploy_resp.status_code == 201
            deploy_id = deploy_resp.get_json()["id"]
            assert "deploy-" in deploy_id

        # 3. Check status
        status_resp = client.get("/status")
        assert status_resp.status_code == 200
        deployments = status_resp.get_json()["deployments"]
        assert deploy_id in deployments

        # 4. Rollback
        with patch("src.app.requests.post") as mock_post:
            rollback_resp = client.post("/rollback", json={"id": deploy_id})
            assert rollback_resp.status_code == 200
            assert rollback_resp.get_json()["status"] == "rolled_back"

    def test_deploy_missing_service(self, client):
        """Deploy requires service parameter."""
        resp = client.post("/deploy", json={})
        assert resp.status_code == 400
        assert "error" in resp.get_json()


class TestMetricsIntegration:
    """Integration tests for /metrics endpoint."""

    def test_metrics_counts(self, client):
        """Metrics should reflect deployment counts."""
        resp = client.get("/metrics")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "deployments" in data
        assert "pending" in data
        assert "running" in data