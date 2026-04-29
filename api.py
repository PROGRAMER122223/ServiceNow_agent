"""
ServiceNow Agent – FastAPI Backend
Exposes the LangGraph SQL agent as a REST + SSE API.

Endpoints:
  POST /ask          – single question → JSON answer
  GET  /history      – conversation history
  DELETE /history    – clear history
  GET  /suggestions  – pre-built example questions
  GET  /health       – liveness check
"""

import os
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits import SQLDatabaseToolkit
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from langgraph.graph import StateGraph, START
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from typing_extensions import TypedDict
from dotenv import load_dotenv
import time

os.environ["LANGCHAIN_TRACING_V2"] = "false"
os.environ["LANGCHAIN_API_KEY"] = ""
os.environ["LANGSMITH_API_KEY"] = ""

load_dotenv()

# ── Globals ──────────────────────────────────────────────────────────────────
agent = None
conversation_history: list[dict] = []

SYSTEM_PROMPT = """You are an expert SQL agent for a ServiceNow-style IT Service Management (ITSM) database.

The database contains the following key tables:
  • incidents       – ServiceNow INC tickets (number, state, priority, impact, urgency, SLA due)
  • resolutions     – Resolution details, root cause, steps taken, KB article linked
  • work_notes      – Journal entries per incident (work notes and customer updates)
  • users           – Customers, agents, and managers
  • products        – Electronics product catalogue (laptops, phones, printers, etc.)
  • categories      – Hierarchical category tree (Electronics > Laptops, Mobile Devices, etc.)
  • kb_articles     – Knowledge Base articles with view/helpful vote counts
  • v_incident_summary – Convenience view joining all the above

Priority scale: 1=Critical, 2=High, 3=Medium, 4=Low
States: New | In Progress | On Hold | Resolved | Closed | Cancelled

Always:
  1. Check available tables first if uncertain.
  2. Inspect the relevant schema before writing SQL.
  3. Use the v_incident_summary view for quick cross-table answers.
  4. Return a clear, concise answer in plain English."""

EXAMPLE_QUESTIONS = [
    "How many incidents are currently open or in-progress?",
    "List all Critical (P1) and High (P2) incidents with their assigned agent and current state.",
    "Which electronics product has the highest number of incidents raised against it?",
    "Which support agent has resolved the most incidents, and what is their resolution rate?",
    
]
# ── LangGraph Agent ───────────────────────────────────────────────────────────
class AgentState(TypedDict):
    messages: Annotated[list, add_messages]


def build_agent():
    DB_URL = os.getenv("DB_URL", "postgresql://snuser:snpassword@localhost:5432/servicenow")
    db = SQLDatabase.from_uri(DB_URL)

    llm = ChatGoogleGenerativeAI(
        model="gemini-2.5-flash-lite",
        vertexai=True,
        project=os.getenv("GOOGLE_CLOUD_PROJECT"),
    )

    toolkit = SQLDatabaseToolkit(db=db, llm=llm)
    tools = toolkit.get_tools()
    llm_with_tools = llm.bind_tools(tools)

    def call_agent(state: AgentState) -> AgentState:
        messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]
        response = llm_with_tools.invoke(messages)
        return {"messages": [response]}

    graph_builder = StateGraph(AgentState)
    graph_builder.add_node("agent", call_agent)
    graph_builder.add_node("tools", ToolNode(tools))
    graph_builder.add_edge(START, "agent")
    graph_builder.add_conditional_edges("agent", tools_condition)
    graph_builder.add_edge("tools", "agent")

    return graph_builder.compile()


# ── Lifespan ──────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global agent
    print("Initialising ServiceNow agent…")
    agent = build_agent()
    print("Agent ready.")
    yield
    print("Shutting down.")


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="ServiceNow Agent API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Schemas ───────────────────────────────────────────────────────────────────
class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    answer: str
    elapsed_ms: int
    id: int


# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/docs")
def root():
    return {"message": "ServiceNow Agent API is running"}

@app.get("/health")
def health():
    return {"status": "ok", "agent_ready": agent is not None}


@app.get("/suggestions")
def suggestions():
    return {"questions": EXAMPLE_QUESTIONS}


@app.get("/history")
def get_history():
    return {"history": conversation_history}


@app.delete("/history")
def clear_history():
    conversation_history.clear()
    return {"cleared": True}


@app.post("/ask", response_model=AskResponse)
def ask(req: AskRequest):
    if agent is None:
        raise HTTPException(status_code=503, detail="Agent not ready")
    if not req.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty")

    t0 = time.time()
    try:
        result = agent.invoke({"messages": [HumanMessage(content=req.question)]})
        answer = result["messages"][-1].content
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    elapsed = int((time.time() - t0) * 1000)
    entry = {
        "id": len(conversation_history) + 1,
        "question": req.question,
        "answer": answer,
        "elapsed_ms": elapsed,
    }
    conversation_history.append(entry)
    return AskResponse(**entry)