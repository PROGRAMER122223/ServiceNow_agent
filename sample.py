import os
from typing import Annotated

from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits import SQLDatabaseToolkit
from langchain_google_genai import ChatGoogleGenerativeAI
from langgraph.graph import StateGraph, START
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from typing_extensions import TypedDict
from dotenv import load_dotenv

os.environ["LANGCHAIN_TRACING_V2"] = "false"
os.environ["LANGCHAIN_API_KEY"] = ""
os.environ["LANGSMITH_API_KEY"] = ""


# ── 1. Connect to the ServiceNow Postgres container ──────────────────────────
DB_URL = "postgresql://snuser:snpassword@localhost:5432/servicenow"
db = SQLDatabase.from_uri(DB_URL)


# ── 2. LLM ───────────────────────────────────────────────────────────────────
load_dotenv()
project = os.getenv("GOOGLE_CLOUD_PROJECT")

llm = ChatGoogleGenerativeAI(
    model="gemini-2.5-flash-lite",
    vertexai=True,
    project=project,
)


# ── 3. SQL toolkit ───────────────────────────────────────────────────────────
toolkit = SQLDatabaseToolkit(db=db, llm=llm)
tools = toolkit.get_tools()        # list_tables, get_schema, query_sql, query_checker
llm_with_tools = llm.bind_tools(tools)


# ── 4. LangGraph state ───────────────────────────────────────────────────────
class AgentState(TypedDict):
    messages: Annotated[list, add_messages]


# ── 5. Agent node ─────────────────────────────────────────────────────────────
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


def call_agent(state: AgentState) -> AgentState:
    from langchain_core.messages import SystemMessage
    messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]
    response = llm_with_tools.invoke(messages)
    return {"messages": [response]}


# ── 6. Build the graph ───────────────────────────────────────────────────────
graph_builder = StateGraph(AgentState)

graph_builder.add_node("agent", call_agent)
graph_builder.add_node("tools", ToolNode(tools))

graph_builder.add_edge(START, "agent")

# Tool calls → execute → loop back to agent; no tool calls → done
graph_builder.add_conditional_edges("agent", tools_condition)
graph_builder.add_edge("tools", "agent")

agent = graph_builder.compile()


# ── 7. Helper ────────────────────────────────────────────────────────────────
def ask(question: str) -> str:
    from langchain_core.messages import HumanMessage
    result = agent.invoke({"messages": [HumanMessage(content=question)]})
    return result["messages"][-1].content


# ── 8. Example ServiceNow queries ────────────────────────────────────────────
if __name__ == "__main__":
    questions = [
        # Incident overview
        "How many incidents are currently open or in-progress?",

        # SLA / priority
        "List all Critical (P1) and High (P2) incidents with their assigned agent and current state.",

        # Product / electronics focus
        "Which electronics product has the highest number of incidents raised against it?",

        # Agent performance
        "Which support agent has resolved the most incidents, and what is their resolution rate?",

        # Resolution quality
        "What are the most common resolution codes used across all resolved incidents?",

        # Knowledge Base
        "Which KB article has the most helpful votes, and what incident type does it address?",

        # SLA breach
        "Are there any incidents where the SLA due date has already passed and the ticket is not yet resolved?",

        # Category breakdown
        "Break down the number of incidents by product category (e.g. Laptops, Mobile Devices, Networking).",

        # Work notes activity
        "Which incident has the most work notes logged, and what is its current state?",

        # Resolution turnaround
        "What is the average time (in hours) between an incident being opened and resolved?",
    ]

    for q in questions:
        print(f"\n{'='*60}")
        print(f"Q: {q}")
        print(f"A: {ask(q)}")