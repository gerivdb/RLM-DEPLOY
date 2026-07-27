from flask import Flask, jsonify, request
import os
import requests

app = Flask(__name__)

KIX_BASE_URL = os.environ.get("KIX_BASE_URL", "http://localhost:8800")
DEPLOYMENTS: dict = {}
NEXT_ID = 1


@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": "rlm-deploy"}), 200


@app.get("/metrics")
def metrics():
    return jsonify({
        "deployments": len(DEPLOYMENTS),
        "pending": sum(1 for d in DEPLOYMENTS.values() if d["status"] == "pending"),
        "running": sum(1 for d in DEPLOYMENTS.values() if d["status"] == "running"),
    }), 200


@app.post("/vote")
def vote():
    data = request.get_json(silent=True) or {}
    choice = data.get("choice")
    if not choice:
        return jsonify({"error": "missing choice"}), 400
    return jsonify({"choice": choice, "count": 1}), 200


@app.post("/deploy")
def deploy():
    global NEXT_ID
    data = request.get_json(silent=True) or {}
    service_name = data.get("service")
    if not service_name:
        return jsonify({"error": "missing service"}), 400

    deploy_id = f"deploy-{NEXT_ID}"
    NEXT_ID += 1
    DEPLOYMENTS[deploy_id] = {
        "service": service_name,
        "status": "pending",
    }

    try:
        requests.post(f"{KIX_BASE_URL}/runners/start", json={"service": service_name}, timeout=5)
        DEPLOYMENTS[deploy_id]["status"] = "running"
    except requests.RequestException:
        DEPLOYMENTS[deploy_id]["status"] = "failed"

    return jsonify({"id": deploy_id, "status": DEPLOYMENTS[deploy_id]["status"]}), 201


@app.post("/rollback")
def rollback():
    data = request.get_json(silent=True) or {}
    deploy_id = data.get("id")
    if not deploy_id:
        return jsonify({"error": "missing id"}), 400

    deployment = DEPLOYMENTS.get(deploy_id)
    if not deployment:
        return jsonify({"error": "deployment not found"}), 404

    service_name = deployment.get("service")
    try:
        requests.post(f"{KIX_BASE_URL}/runners/{service_name}/stop", timeout=5)
    except requests.RequestException:
        pass

    deployment["status"] = "rolled_back"
    return jsonify({"id": deploy_id, "status": deployment["status"]}), 200


@app.get("/status")
def status():
    return jsonify({"deployments": DEPLOYMENTS}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8795)))
