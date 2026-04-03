# KYC Platform — Docker Compose Environment

Full-stack Know Your Customer (KYC) verification platform for local development and AWS integration testing.

```
┌──────────┐     ┌───────────┐     ┌──────────────┐
│  Vue.js  │────▶│   Nginx   │────▶│   FastAPI    │
│ Frontend │     │  :80      │     │   Backend    │
└──────────┘     └───────────┘     └──────┬───────┘
                                          │
                              ┌───────────┼───────────┐
                              ▼           ▼           ▼
                          ┌───────┐  ┌───────┐  ┌─────────┐
                          │ Mongo │  │ Redis │  │  AWS S3 │
                          │ :27017│  │ :6379 │  │ (ext.)  │
                          └───────┘  └───────┘  └─────────┘
                              │
                        (swap for)
                              │
                        ┌─────────────────────────┐
                        │  AWS Aurora PostgreSQL   │
                        │  (external, AWS-hosted)  │
                        └─────────────────────────┘
```

## Services

| Service       | Port  | Purpose                              |
|---------------|-------|--------------------------------------|
| nginx         | 80    | Reverse proxy (routes `/api` & `/`)  |
| frontend      | 3000  | Vue.js SPA (served by Nginx)         |
| backend       | 8000  | FastAPI — REST API + Swagger docs    |
| mongo         | 27017 | MongoDB (local replacement for Aurora)|
| mongo-express | 8081  | MongoDB admin UI (dev only)          |
| redis         | 6379  | Session cache / task queue           |

---

## Prerequisites — Ubuntu Setup

### 1. Install Docker Engine

```bash
# Remove old versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Install dependencies
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine + Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

### 2. Post-install — Run Docker without sudo

```bash
sudo usermod -aG docker $USER
newgrp docker          # apply group immediately (or log out/in)
docker run hello-world # verify
```

### 3. Verify versions

```bash
docker --version        # Docker version 26+
docker compose version  # Docker Compose version v2+
```

---

## Quick Start

### Step 1 — Clone / copy the project

```bash
git clone <your-repo-url> kyc-environment
cd kyc-environment
```

### Step 2 — Create your .env file

```bash
cp .env.example .env
# Edit .env if you need custom passwords or AWS keys
nano .env
```

### Step 3 — Start the stack

```bash
# Using the management script (recommended)
chmod +x scripts/manage.sh
./scripts/manage.sh up

# OR directly with docker compose
docker compose up --build -d
```

### Step 4 — Access the platform

| URL                            | What                        |
|--------------------------------|-----------------------------|
| http://localhost               | KYC Web Application         |
| http://localhost:8000/api/docs | FastAPI Swagger UI          |
| http://localhost:8000/api/redoc| FastAPI ReDoc               |
| http://localhost:8081          | MongoDB Admin (Mongo Express)|

**Default credentials:**

| Role    | Email                | Password    |
|---------|----------------------|-------------|
| Admin   | admin@kyc.local      | admin123    |
| Officer | officer@kyc.local    | officer123  |
| Mongo   | admin (ME_USER)      | admin123    |

---

## Management Commands

```bash
./scripts/manage.sh up           # Build & start all services
./scripts/manage.sh down         # Stop all services
./scripts/manage.sh logs         # Tail all logs
./scripts/manage.sh logs-be      # Backend logs only
./scripts/manage.sh status       # Show container health
./scripts/manage.sh shell-be     # Shell into backend container
./scripts/manage.sh shell-mongo  # Open MongoDB shell
./scripts/manage.sh reset-db     # Drop & re-seed database
./scripts/manage.sh gen-secret   # Generate a SECRET_KEY
./scripts/manage.sh clean        # Remove everything (containers + volumes)
```

---

## Switching from MongoDB to AWS Aurora

The backend database layer is fully abstracted in `backend/app/core/database.py`.

### Step 1 — Provision Aurora (PostgreSQL-compatible)

```bash
# Via AWS CLI
aws rds create-db-cluster \
  --db-cluster-identifier kyc-cluster \
  --engine aurora-postgresql \
  --master-username kycuser \
  --master-user-password <password> \
  --db-subnet-group-name <your-subnet-group> \
  --vpc-security-group-ids <your-sg-id>
```

### Step 2 — Update .env

```bash
# Comment out MongoDB, uncomment Aurora
AURORA_HOST=kyc-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
AURORA_PORT=5432
AURORA_DB=kycdb
AURORA_USER=kycuser
AURORA_PASSWORD=yourpassword
```

### Step 3 — Update docker-compose.yml

In the `backend.environment` section:

```yaml
# Disable MongoDB URI:
# DB_URI: mongodb://...

# Enable Aurora URI:
DB_URI: postgresql+asyncpg://${AURORA_USER}:${AURORA_PASSWORD}@${AURORA_HOST}:5432/${AURORA_DB}
```

### Step 4 — Enable SQLAlchemy in backend

In `backend/requirements.txt`, uncomment:
```
asyncpg==0.29.0
sqlalchemy[asyncio]==2.0.30
alembic==1.13.1
```

In `backend/app/core/database.py`, swap the commented SQLAlchemy block for the Motor block.

### Step 5 — Run migrations

```bash
./scripts/manage.sh shell-be
alembic upgrade head
```

---

## AWS External Services

### S3 Document Storage

Documents upload to S3 when `AWS_ACCESS_KEY_ID` is set in `.env`. Without it, the backend stores the path metadata only (useful for local dev).

```bash
# Create bucket
aws s3 mb s3://kyc-documents --region us-east-1

# Set lifecycle policy for compliance (90-day retention example)
aws s3api put-bucket-lifecycle-configuration \
  --bucket kyc-documents \
  --lifecycle-configuration file://scripts/s3-lifecycle.json
```

### Recommended IAM Policy for the backend

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::kyc-documents/*"
    },
    {
      "Effect": "Allow",
      "Action": ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement"],
      "Resource": "arn:aws:rds:us-east-1:*:cluster:kyc-cluster"
    }
  ]
}
```

---

## Project Structure

```
kyc-environment/
├── docker-compose.yml          # Orchestration
├── .env.example                # Environment template
├── nginx/
│   └── nginx.conf              # Reverse proxy config
├── mongo-init/
│   └── init.js                 # DB schema + seed data
├── scripts/
│   └── manage.sh               # Management CLI
├── backend/                    # FastAPI application
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py             # App entrypoint + CORS
│       ├── core/
│       │   ├── config.py       # Pydantic settings
│       │   └── database.py     # DB abstraction (Mongo ↔ Aurora)
│       ├── models/
│       │   └── schemas.py      # Pydantic request/response models
│       └── routers/
│           ├── auth.py         # JWT authentication
│           ├── customers.py    # Customer CRUD
│           ├── documents.py    # Document upload (S3)
│           └── verifications.py# KYC verification workflow
└── frontend/                   # Vue.js SPA
    ├── Dockerfile              # Multi-stage build
    ├── nginx.conf              # SPA routing
    ├── index.html
    ├── vite.config.js
    ├── package.json
    └── src/
        ├── main.js
        ├── App.vue             # Layout + sidebar
        ├── assets/main.css     # Design system
        ├── router/index.js     # Vue Router
        ├── store/
        │   ├── auth.js         # Pinia auth store
        │   └── api.js          # Axios client + resource helpers
        └── views/
            ├── LoginView.vue
            ├── DashboardView.vue
            ├── CustomersView.vue
            ├── CustomerDetailView.vue
            ├── VerificationsView.vue
            └── DocumentsView.vue
```

---

## Troubleshooting

**Port already in use:**
```bash
sudo lsof -i :80 -i :8000 -i :27017
sudo kill -9 <PID>
```

**Backend can't connect to MongoDB:**
```bash
docker compose logs mongo        # check if Mongo is healthy
./scripts/manage.sh shell-be
curl http://mongo:27017          # test internal DNS
```

**Frontend build fails (node_modules):**
```bash
docker compose build --no-cache frontend
```

**Reset everything and start fresh:**
```bash
./scripts/manage.sh clean
./scripts/manage.sh up
```

**Check all container health:**
```bash
docker compose ps
docker inspect kyc-backend | grep -A5 Health
```
