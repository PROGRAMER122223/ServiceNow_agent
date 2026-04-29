# ServiceNow Agent 🤖

A natural-language SQL agent for an IT Service Management (ITSM) database modelled on ServiceNow. Ask questions in plain English — the agent inspects the schema, writes the SQL, executes it, and returns a human-readable answer.

Built with **LangGraph**, **LangChain SQL Toolkit**, **Google Gemini 2.5 Flash**, and **PostgreSQL 16**, with **pgAdmin 4** for browser-based database exploration.

---

## Table of Contents

- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Database Schema](#database-schema)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Running the Agent](#running-the-agent)
- [Example Questions](#example-questions)
- [pgAdmin Access](#pgadmin-access)
- [Configuration](#configuration)
- [How It Works](#how-it-works)

---

## Architecture

```
User Question (plain English)
        │
        ▼
  ┌─────────────┐       system prompt +        ┌──────────────────────┐
  │  LangGraph  │  ──── conversation ────────▶ │  Gemini 2.5 Flash    │
  │   Agent     │ ◀──── tool calls / answer ── │  (via Vertex AI)     │
  └──────┬──────┘                              └──────────────────────┘
         │ tool calls
         ▼
  ┌─────────────────────────────┐
  │   LangChain SQL Toolkit     │
  │  • list_tables              │
  │  • get_schema               │
  │  • query_sql                │
  │  • query_checker            │
  └──────────────┬──────────────┘
                 │ SQL
                 ▼
        ┌────────────────┐
        │  PostgreSQL 16 │  (Docker)
        │  servicenow DB │
        └────────────────┘
```

The graph loops — the LLM can call tools multiple times (e.g. list tables → get schema → run query → refine) before returning a final answer.

---

## Project Structure

```
servicenow-db/
├── docker-compose.yml          # Postgres + pgAdmin containers
├── sample.py                   # LangGraph agent entry point
├── README.md
├── initdb/
│   ├── 01_schema.sql           # Tables, indexes, and summary view
│   └── 02_seed.sql             # Sample incidents, products, resolutions
└── pgadmin/
    ├── servers.json            # Auto-registers Postgres in pgAdmin
    └── pgpass                  # Passwordless connection for pgAdmin
```

---

## Database Schema

| Table | Description |
|---|---|
| `incidents` | ServiceNow-style INC tickets — state, priority, SLA, assignment |
| `resolutions` | Root cause, steps taken, KB article linked per resolved incident |
| `work_notes` | Journal entries (agent work notes + customer updates) |
| `users` | Customers, support agents, and managers |
| `products` | Electronics catalogue — laptops, phones, printers, networking gear, etc. |
| `categories` | Hierarchical category tree (Electronics → Laptops, Mobile, Networking …) |
| `kb_articles` | Knowledge Base articles with view and helpful-vote counts |
| `v_incident_summary` | Convenience view joining all tables above |

**Priority scale:** 1 = Critical · 2 = High · 3 = Medium · 4 = Low

**Incident states:** `New` · `In Progress` · `On Hold` · `Resolved` · `Closed` · `Cancelled`

The seed data includes **15 realistic electronics incidents** covering Dell, Apple, Samsung, Cisco, Sony, LG, Xbox, Google Pixel, and Amazon Echo devices, complete with work notes, resolutions, and linked KB articles.

---

## Prerequisites

| Requirement | Version |
|---|---|
| Python | 3.10 + |
| Docker & Docker Compose | 24 + |
| Google Cloud project | with Vertex AI API enabled |

---

## Quick Start

### 1. Clone / copy the project

```bash
cd servicenow-db
```

### 2. Start the database containers

```bash
docker compose up -d
```

This starts:
- **Postgres 16** on `localhost:5432` — auto-seeded from `initdb/` on first run
- **pgAdmin 4** on `http://localhost:5050` — pre-connected to Postgres

Wait ~10 seconds for the seed scripts to complete, then verify:

```bash
docker compose logs postgres | tail -20
# Should end with: database system is ready to accept connections
```

### 3. Create a Python virtual environment

```bash
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
```

### 4. Install dependencies

```bash
pip install \
  langchain \
  langchain-community \
  langchain-google-genai \
  langgraph \
  psycopg2-binary \
  sqlalchemy \
  python-dotenv
```

### 5. Configure environment

Create a `.env` file in the project root:

```env
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
```

Ensure your environment is authenticated with Google Cloud:

```bash
gcloud auth application-default login
```

---

## Running the Agent

```bash
python sample.py
```

The script runs 10 pre-written ServiceNow questions and prints answers. To ask your own question interactively, import the `ask()` helper:

```python
from sample import ask

print(ask("Which agent has the most unresolved tickets?"))
print(ask("Show me all P1 incidents and their SLA breach status."))
print(ask("How many Sony incidents have been raised this month?"))
```

---

## Example Questions

The agent handles any natural-language question about the ITSM data. Here are the 10 included in `sample.py`:

| # | Question |
|---|---|
| 1 | How many incidents are currently open or in-progress? |
| 2 | List all Critical (P1) and High (P2) incidents with their assigned agent and current state. |
| 3 | Which electronics product has the highest number of incidents raised against it? |
| 4 | Which support agent has resolved the most incidents, and what is their resolution rate? |
---
![alt text](image.png)
---

## pgAdmin Access

| Field | Value |
|---|---|
| URL | http://localhost:5050 |
| Email | admin@servicenow.local |
| Password | admin |

The **ServiceNow DB (Local)** server is pre-registered — no manual connection setup needed. Expand **Servers → ServiceNow DB (Local) → Databases → servicenow → Schemas → public → Tables** to browse the schema and data.

---

## Configuration

| Variable | File | Default | Description |
|---|---|---|---|
| `DB_URL` | `sample.py` | `postgresql://snuser:snpassword@localhost:5432/servicenow` | Postgres connection string |
| `GOOGLE_CLOUD_PROJECT` | `.env` | _(required)_ | GCP project for Vertex AI |
| `POSTGRES_USER` | `docker-compose.yml` | `snuser` | DB username |
| `POSTGRES_PASSWORD` | `docker-compose.yml` | `snpassword` | DB password |
| `PGADMIN_DEFAULT_EMAIL` | `docker-compose.yml` | `admin@servicenow.local` | pgAdmin login |
| `PGADMIN_DEFAULT_PASSWORD` | `docker-compose.yml` | `admin` | pgAdmin password |

---

## How It Works

1. **User question** is wrapped in a `HumanMessage` and passed to the LangGraph agent.
2. The **agent node** prepends the ITSM-aware system prompt and calls Gemini with the SQL tools bound.
3. Gemini decides which tools to call — typically: `list_tables` → `get_schema` → `query_checker` → `query_sql`.
4. The **ToolNode** executes the tool calls against Postgres and returns results.
5. The graph loops back to the agent until Gemini returns a plain-text answer (no further tool calls).
6. The final message content is returned from `ask()`.

```
START → agent → [tool calls?] → tools → agent → ... → END
                     │ no
                     ▼
                   answer
```

---

## Stopping the Stack

```bash
docker compose down          # stop containers, keep data
docker compose down -v       # stop containers AND delete all data
```