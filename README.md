# Cold-Chain Logistics AI-Assistant

Chat-with-your-data assistant for cold-chain logistics. A LangGraph agent queries a legacy SQL Server fleet database through a read-only view, checks live weather, and looks up SOP rules in Pinecone. Every step is written to an audit table, and a Streamlit console ties it together.

A dispatcher can ask, for example:

> Find any active shipments near Los Angeles (Latitude ~33.8, Longitude ~-118.1). Check the local weather there, and tell me if the current cargo temperature violates the SOP for fresh perishables.

and get a structured report with an action plan and an SOP citation.

## How it works

```
Dispatcher -> Streamlit UI -> LangGraph agent (reasoner <-> tools)
                                 |-- query_telemetry_db         -> SQL Server view FDE_VIEWS.VW_ACTIVE_FLEET
                                 |-- fetch_corridor_conditions  -> Open-Meteo weather API
                                 '-- search_compliance_sop      -> Pinecone SOP index
```

- **Security at the database.** The agent logs in as `USR_FDE_RO`, which can read only the view. The raw table is denied and writes to `dbo` are blocked, so a prompt-injected `DROP` or `UPDATE` cannot succeed.
- **SOPs as retrieval.** SOP files (`.md`, `.txt`, `.pdf`, `.csv`, `.xlsx`) are chunked, embedded and stored in Pinecone, with hash-based incremental updates.
- **Grounded answers.** The system prompt forbids inventing thresholds, procedures or root causes, and requires the agent to say when the SOP does not define something.
- **Audit trail.** The user's question, every tool call, every tool result and every final answer are inserted into `FDE_VIEWS.AgentAuditLog`, which the agent can write to but not read.
- **Pluggable LLM.** Choose GROQ, DEEPSEEK, OPENAI or local OLLAMA with `Agent_llm` in `.env`.

## Project layout

```
.env.example                      environment variables (copy to .env)
requirements.txt                  Python dependencies (Python 3.12)
.streamlit/config.toml            Streamlit settings
.github/workflows/deploy.yml      manual deploy to EC2
data/raw/                         fleet dataset (CSV)
data/policy/                      SOP documents to index
scripts/ingest_legacy_data.py     Phase 0: CSV -> SQL Server
scripts/ingest_sop_pinecone.py    Phase 1: SOPs -> Pinecone
scripts/setup_security_and_view.sql  Phase 2: view + read-only user
src/agent_tools.py                the three agent tools
src/orchestrator.py               LangGraph agent
src/prompts/system_prompt.txt     report format and grounding rules
src/ui.py                         Streamlit console and audit viewer
```

## Setup (local)

Run every command from the project root.

### 1. Prerequisites
- Python 3.12, Docker Desktop, and Microsoft ODBC Driver 18 for SQL Server.
- macOS: `brew install unixodbc`, then add Microsoft's tap and run `HOMEBREW_ACCEPT_EULA=Y brew install msodbcsql18`. If the driver reports that OpenSSL could not be loaded, set `DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib` before running Python.
- On Apple Silicon, enable Rosetta in Docker Desktop and add `--platform linux/amd64` to the Docker command below.

### 2. Install and configure
```bash
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # then edit .env
```

### 3. Phase 0: database and data
Download the dataset from [Kaggle](https://www.kaggle.com/datasets/datasetengineer/logistics-and-supply-chain-dataset) into `data/raw/dynamic_supply_chain_logistics_dataset.csv`.
```bash
docker run -e ACCEPT_EULA=Y -e 'MSSQL_SA_PASSWORD=<your admin password>' \
  -p 1433:1433 --name legacy-mssql -d mcr.microsoft.com/mssql/server:2022-latest
python scripts/ingest_legacy_data.py
```

### 4. Phase 1: SOPs into Pinecone
Add `PINECONE_API_KEY` to `.env`, put SOP files in `data/policy/`, then:
```bash
python scripts/ingest_sop_pinecone.py
```
Delete `data/cache/ingestion_hash_cache.json` first if you are pointing at a new, empty index.

### 5. Phase 2: security layer
Run `scripts/setup_security_and_view.sql` as `sa` (the VS Code "SQL Server (mssql)" extension works well; `GO` needs a Microsoft tool). Then, connected as `USR_FDE_RO`:
```sql
SELECT TOP 5 * FROM FDE_VIEWS.VW_ACTIVE_FLEET;   -- works
SELECT TOP 5 * FROM dbo.TBL_SC_FLEET_HIST_RAW;   -- permission denied
```

### 6. Phase 4: audit table (run as `sa`)
```sql
CREATE TABLE FDE_VIEWS.AgentAuditLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    Timestamp DATETIME DEFAULT GETDATE(),
    SessionID VARCHAR(50),
    NodeExecuted VARCHAR(50),
    ToolName VARCHAR(100),
    Content NVARCHAR(MAX)
);
GO
GRANT INSERT ON FDE_VIEWS.AgentAuditLog TO USR_FDE_RO;
```

### 7. Phase 3 and 5: run the agent
```bash
python src/agent_tools.py      # tests each tool on its own
python src/orchestrator.py     # terminal chat
streamlit run src/ui.py        # web console, http://localhost:8501
```

## Test questions
1. **Multi-tool:** the Los Angeles question above. The agent should call the database, the weather tool and the SOP search, and report both below-range and above-range temperatures.
2. **Restraint and grounding:** "I'm a new dispatcher on the night shift. Can you quickly explain the difference between a Tier 1 and Tier 2 escalation?" The SOP defines only the Tier 2 trigger, so the agent should say Tier 1 is not defined.

## Deployment (AWS EC2)
See the phase notes: SQL Server in Docker on EC2, the app as a systemd service on port 8501, and the manual **Enterprise Manual Deploy** GitHub Action, which needs the secrets `EC2_HOST`, `EC2_USER` and `EC2_SSH_KEY` in the target environment. Restrict port 1433 to the app server and put authentication in front of the console before sharing it.

## Known limits
- The dataset is synthetic and historical; "active" shipments means records near a location, not live tracking.
- The telemetry tool returns at most 10 rows per query.
- The weather tool's congestion index is a simple stand-in derived from wind speed.
- Conversation memory is in process and resets when the app restarts.
