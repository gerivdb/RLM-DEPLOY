import pytest
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


def test_status(client):
    resp = client.get("/status")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "deployments" in data
