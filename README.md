# SpendLens

SpendLens is a **personal finance web app for India**. Upload bank and card statements, track spending, manage investments, and prepare for income tax filing — with an **AI assistant (Savvy)** powered by [Ollama](https://ollama.com) running locally on your machine.

Built with **Rails 8**, **React (Inertia.js)**, **PostgreSQL**, and **Tailwind CSS**.

## What it does

| Area | Capabilities |
|------|----------------|
| **Statements** | Upload CSV/PDF bank statements; hybrid regex + AI parsing; duplicate detection |
| **Spending** | Auto-categorization (rules + AI), budgets, insights, recurring detection, bulk edits |
| **AI (Savvy)** | Chat about spending, credit cards, ITR readiness; context from your real transactions |
| **Credit cards** | Rewards lookup, “best card for purchase”, portfolio comparison |
| **Investments** | Portfolio, broker/MF imports, bank-to-investment suggestions, net worth |
| **ITR prep** | FY dashboard (Apr–Mar), Form 16 / AIS / 26AS upload, AI extraction, AIS reconciliation, regime compare, tax pack ZIP |
| **Settings** | Per-user preferences, notification toggles, custom investment detection rules |

**Privacy note:** AI features call **your local Ollama instance** by default — statement text is not sent to a cloud LLM unless you point `OLLAMA_URL` elsewhere.

Public overview for end users: visit `/` while signed out (marketing landing page).

## Tech stack

- **Backend:** Ruby on Rails 8, Devise, Active Storage, Solid Queue (optional background jobs)
- **Frontend:** Inertia.js, React 19, Vite, Tailwind CSS 4, Recharts
- **Database:** PostgreSQL
- **AI:** Ollama HTTP API (`ollama-ai` gem)

## Prerequisites

- **Ruby** 3.3+ (project uses `.ruby-version`; [asdf](https://asdf-vm.com) recommended)
- **Node.js** 18+ and npm
- **PostgreSQL** 14+
- **Ollama** (optional but required for AI features)
- **poppler** (`pdftotext`) — optional, improves PDF parsing: `brew install poppler`

## Quick start (local)

```bash
git clone <repo-url>
cd spend_lens

cp .env.example .env   # optional

bundle install
npm install

bin/rails db:create db:migrate
```

Start the app (two processes):

```bash
# Terminal 1 — Vite (frontend assets)
bin/vite dev

# Terminal 2 — Rails
bin/rails s
```

Open **http://localhost:3000**

First-time setup in one command:

```bash
bin/setup   # bundle, db:prepare, then starts bin/dev (Rails only)
```

If you use `bin/setup`, still run `bin/vite dev` in another terminal for hot reload.

### AI providers

SpendLens supports three providers, switched via `AI_PROVIDER` in `.env`:

| `AI_PROVIDER` | Use case | Agentic tool calls |
|---|---|---|
| `ollama` (default) | Local, private, free; offline | No (falls back to single-shot) |
| `gemini` | Hosted; great for agent mode; free tier available | Yes |
| `openai` | Hosted; great for agent mode | Yes |

**Local (Ollama):**

```bash
brew install ollama
ollama serve
ollama pull llama3.1:8b
```

```env
AI_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.1:8b
```

**Gemini (dev: free tier, prod: paid):**

Get a key from [Google AI Studio](https://aistudio.google.com/apikey). In dev you can use the free tier — but note that **free-tier prompts may be used for model training**, so do not point it at real bank data. In production switch to the paid tier (same SDK, just a paid key) for the no-training guarantee.

```env
AI_PROVIDER=gemini
GEMINI_API_KEY=AIza...
GEMINI_MODEL=gemini-1.5-flash
```

**OpenAI:**

```env
AI_PROVIDER=openai
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
```

Per-user AI toggles live under **Settings** after sign-in (enable AI, agentic mode, agent-proposed writes).

### Agentic mode (Stage 1 + 2)

When `AI_PROVIDER` is `gemini` or `openai`, Savvy runs in **agentic mode**: instead of stuffing a giant context blob into one prompt, it calls **tools** in a bounded loop.

- **Stage 1 (read tools):** `search_transactions`, `monthly_summary`, `top_merchants`, `recurring_transactions`, `credit_card_summary`, `best_card_for_purchase`, `budget_status`, `net_worth`, `holdings_snapshot`, `list_categories`, `uncategorized_transactions`, `itr_readiness`, `ais_reconciliation`, `regime_compare`, `capital_gains`.
- **Stage 2 (write tools, propose-only):** `propose_recategorize`, `propose_create_budget`, `propose_create_category_rule`, `propose_create_category`. These **never mutate state**; they return a signed proposal token that the UI shows with Apply / Reject buttons. The mutation only happens after you click Apply (via `POST /ai/proposals/apply` which re-verifies ownership).

Controls:

| Env var | Default | Meaning |
|---|---|---|
| `AI_AGENTIC_ENABLED` | `true` | Global kill switch. |
| `AI_AGENTIC_MAX_STEPS` | `6` | Max tool-call iterations per question (1–12). |
| `GEMINI_MODEL` | `gemini-1.5-flash` | Gemini model. |
| `OPENAI_MODEL` | `gpt-4o-mini` | OpenAI model. |

Per-user `ai_agentic_enabled` and `ai_agentic_writes` toggles in `/settings`. Ollama always uses the legacy single-shot path because small local models do not handle tool calling reliably.

## Docker

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```bash
cp .env.example .env
docker compose build
docker compose up
```

- App: http://localhost:3000  
- Postgres: `localhost:5432` (`postgres` / `postgres`)  
- Run Ollama on the host; Compose defaults to `http://host.docker.internal:11434`

Migrations:

```bash
docker compose run --rm web bin/rails db:migrate
```

Production image: root `Dockerfile` (not `docker-compose.yml`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `AI_PROVIDER` | `ollama`, `gemini`, or `openai` |
| `AI_AGENTIC_ENABLED` | Global agentic kill switch (`true`/`false`) |
| `AI_AGENTIC_MAX_STEPS` | Max tool-call iterations per question (1–12, default 6) |
| `OLLAMA_URL` / `OLLAMA_MODEL` | Ollama endpoint and model |
| `GEMINI_API_KEY` / `GEMINI_MODEL` | Gemini auth and model |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | OpenAI auth and model |
| `SOLID_QUEUE_IN_PUMA` | Run background jobs inside Puma (`1` to enable) |
| `LARGE_IMPORT_BYTES` / `LARGE_IMPORT_ROWS` | Thresholds for async investment imports |
| `SPEND_LENS_DATABASE_PASSWORD` | Production DB password |

See `.env.example` for the full list.

## Development

```bash
bundle exec rubocop          # if configured
bin/rails console
bin/rails test               # or rspec, per project setup
bin/rails routes
```

**Background jobs:** Statement parsing, tax document extraction, and large investment imports use Active Job. In development the default adapter is often `:inline` (runs immediately). For async behavior, enable Solid Queue (`SOLID_QUEUE_IN_PUMA=1` in `.env`) and ensure the DB queue tables are migrated.

**Monthly digest email:**

```bash
bin/rails runner "MonthlyDigestJob.perform_now"
```

Schedule via cron on the 1st of each month in production.

## Project layout (high level)

```
app/
  controllers/     # Inertia controllers
  frontend/Pages/  # React pages (Inertia)
  jobs/            # ParseStatementJob, ExtractTaxDocumentJob, etc.
  models/
  services/        # Parsers, ITR, AI, investments
config/
  routes.rb
  database.yml
db/migrate/
docs/superpowers/specs/   # Feature design notes
```

## Statement parsing pipeline

1. Extract text from PDF/CSV (`pdf-reader`, `pdftotext` fallback)  
2. Regex parser for common Indian bank layouts  
3. AI extraction via Ollama when regex is incomplete  
4. Validate, dedupe, merge (regex preferred on conflicts)  
5. Categorize and save; optional investment detection from debits/credits  

## Production

- Use PostgreSQL; set `DATABASE_URL` or `SPEND_LENS_DATABASE_PASSWORD` in `config/database.yml`
- Precompile assets: `bin/rails assets:precompile`
- Run a job worker or `SOLID_QUEUE_IN_PUMA=1`
- Configure mailer for digests and Devise

## Disclaimer

SpendLens provides **assistive** tax and finance insights, not professional tax advice. Users should verify figures with a CA before filing.

## License

See repository license file (if present).
