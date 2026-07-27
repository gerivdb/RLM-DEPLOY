# RLM-DEPLOY

Blue-green deployment orchestrator for the RLM ecosystem.

- Port: `8795`
- Dependencies: `KIX` (port `8800`) for runner management
- Stack: Flask + SQLite (future state persistence)

## Endpoints

| Method | Path       | Purpose                       |
|--------|------------|-------------------------------|
| GET    | /health    | Liveness check                |
| GET    | /metrics   | Deployment counts             |
| POST   | /vote      | Record a vote                 |
| POST   | /deploy    | Deploy a service via KIX      |
| POST   | /rollback  | Rollback a deployment         |
| GET    | /status    | List deployments              |

## Run

```powershell
python src/app.py
```

## Test

```powershell
pytest tests/test_app.py -q
```

## Archi notes

- MVP: in-memory deployments dict
- Next: SQLite persistence and blue-green switch logic
- Cross-service: `/deploy` calls `KIX_BASE_URL` (default `http://localhost:8800`)
