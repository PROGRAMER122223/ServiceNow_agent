# ServiceNow Agent 🤖

A natural-language SQL agent for an IT Service Management (ITSM) database modelled on ServiceNow. Ask questions in plain English — the agent inspects the schema, writes the SQL, executes it, and returns a human-readable answer.

Built with **LangGraph**, **LangChain SQL Toolkit**, **Google Gemini 2.5 Flash**, and **PostgreSQL 16**, with **pgAdmin 4** for browser-based database exploration. A **FastAPI** backend exposes the agent as a REST API, and a single-file **HTML/JS** chat frontend provides a dark command-centre UI — no build step required.

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Running the Agent](#running-the-agent)
- [Backend API](#backend-api)
- [Frontend UI](#frontend-ui)
- [Example Questions](#example-questions)
- [How It Works](#how-it-works)

---

## Architecture

```
Browser (ui.html :3000)
        │  HTTP POST /ask
        ▼
  ┌─────────────────┐      system prompt +        ┌──────────────────────┐
  │  FastAPI         │ ──── conversation ────────▶ │  Gemini 2.5 Flash    │
  │  api.py :8000    │ ◀─── tool calls / answer ── │  (via Vertex AI)     │
  └────────┬─────────┘                             └──────────────────────┘
           │ invokes
           ▼
  ┌─────────────────────────────┐
  │   LangGraph Agent           │
  │   LangChain SQL Toolkit     │
  │   • list_tables             │
  │   • get_schema              │
  │   • query_sql               │
  │   • query_checker           │
  └──────────────┬──────────────┘
                 │ SQL
                 ▼
        ┌────────────────┐       ┌──────────────┐
        │  PostgreSQL 16 │       │  pgAdmin 4   │
        │  :5432         │       │  :5050       │
        └────────────────┘       └──────────────┘
              (Docker)                (Docker)
```

The LangGraph loop runs entirely inside the FastAPI request — the LLM calls tools multiple times (list tables → get schema → run query → refine) before returning a final plain-English answer to the UI.

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

The agent handles any natural-language question about the ITSM data. Here are the questions included in `sample.py`:

| # | Question |
|---|---|
| 1 | How many incidents are currently open or in-progress? |
| 2 | List all Critical (P1) and High (P2) incidents with their assigned agent and current state. |
| 3 | Which electronics product has the highest number of incidents raised against it? |
| 4 | Which support agent has resolved the most incidents, and what is their resolution rate? |

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