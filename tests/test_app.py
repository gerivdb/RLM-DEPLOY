import pytest
from unittest.mock import patch
from src.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "ok"
    assert data["service"] == "rlm-deploy"


def test_metrics(client):
    resp = client.get("/metrics")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "deployments" in data
    assert "pending" in data
    assert "running" in data


def test_vote_success(client):
    resp = client.post("/vote", json={"choice": "yes"})
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["choice"] == "yes"
    assert data["count"] == 1


def test_vote_missing_choice(client):
    resp = client.post("/vote", json={})
    assert resp.status_code == 400


def test_deploy_missing_service(client):
    resp = client.post("/deploy", json={})
    assert resp.status_code == 400


def test_rollback_missing_id(client):
    resp = client.post("/rollback", json={})
    assert resp.status_code == 400


def test_rollback_not_found(client):
    resp = client.post("/rollback", json={"id": "deploy-999"})
    assert resp.status_code == 404


def test_rollback_calls_kix_stop(client):
    with patch("src.app.requests.post") as mock_post:
        deploy_resp = client.post("/deploy", json={"service": "RLM-GRAPH"})
        assert deploy_resp.status_code == 201
        deploy_id = deploy_resp.get_json()["id"]

        rollback_resp = client.post("/rollback", json={"id": deploy_id})
        assert rollback_resp.status_code == 200
        assert rollback_resp.get_json()["status"] == "rolled_back"

        stop_calls = [c for c in mock_post.call_args_list if "/runners/RLM-GRAPH/stop" in str(c)]
        assert len(stop_calls) >= 1


def test_status(client):
    resp = client.get("/status")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "deployments" in data
