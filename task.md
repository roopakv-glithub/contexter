# ContextForge — Task Tracker & Architecture Roadmap

> **Repository:** https://github.com/roopakv-glithub/contexter  
> **Application:** ContextForge (Flutter Windows Desktop)  
> **Status:** Production Release v1.4.1  
> **Database & Functions:** Supabase (`tociitdxzqcdkfjacchs.supabase.co`)  
> **AI Inference:** NVIDIA NIM (`nvidia/nemotron-3.5-lightning-30b-a3b`)  

---

## 🚀 Overview & Current State

ContextForge evolves the desktop application into a repository-aware analysis and AI prompt generation workspace.
It analyzes local and GitHub codebases, identifies architecture and dependencies, preserves environment variables and secrets, and compiles production-ready prompts for AI coding agents.

---

## ✅ Completed Tasks

### 1. Application Rebranding
- [x] Application display name renamed to **ContextForge** across metadata, windows runners, window title bars, UI headers, and companion cards.
- [x] Fixed legacy labels (e.g. replaced "Moscowt" with "ContextForge" / "Companion").

### 2. Supabase Cloud Setup & Functions Deployment
- [x] Connected to user's Supabase project: `https://tociitdxzqcdkfjacchs.supabase.co`.
- [x] Database migrations applied:
  - `analysis_reports` table & RLS policies.
  - `prompt_history` table & RLS policies.
  - `ai_request_limits` & `consume_ai_request` rate-limiting RPC.
- [x] Edge Functions deployed & ACTIVE:
  - `analyze-project`: handles GitHub tree fetching and project analysis.
  - `enhance-prompt`: handles contextual AI prompt synthesis.
- [x] Updated `lib/config.dart` with project URL and publishable anon key.

### 3. Local Repository Analysis & Resilient Fallback
- [x] `RepositoryScanner` recursively scans directories, extracting supported files and manifests.
- [x] Automatically detects dependencies (`pubspec.yaml`, `package.json`, `requirements.txt`, `cargo.toml`, `go.mod`, `pom.xml`, etc.).
- [x] Automatic secret redaction for API keys, private keys, JWTs, and `.env` credentials before any network transmission.
- [x] Resilient local fallback: if Supabase is unreachable or unconfigured, local folder analysis completes offline without failing or throwing 404 errors.

### 4. NVIDIA API Key Configuration & Integration
- [x] Settings page NVIDIA API key input with show/hide toggle, local persistent storage (`nvidia_key.txt`), and live connection testing.
- [x] Upgraded model to `nvidia/nemotron-3.5-lightning-30b-a3b` with reasoning parameters (`enable_thinking`, `reasoning_budget`).
- [x] Pass client `nvidiaApiKey` securely in analysis requests.

### 5. Setup Project Workflow (3-Step Pipeline)
- [x] **Step 1: Project Details**
  - Enter project name & optional description.
  - Browse local project folder or enter public GitHub repository URL.
  - Dual independent status indicators with progress counters and real-time tick marks.
- [x] **Step 2: Create Agent**
  - 3 agent companions with distinct specializations (Architect, Security Auditor, Feature Crafter).
  - Preserves agent selection throughout review and final prompt generation.
- [x] **Step 3: Review & Finalize**
  - Synthesizes local and GitHub analysis reports, tech stack, architecture, and files.
  - User task input field with Markdown prompt generator.
  - Direct copy-to-clipboard for feeding downstream coding agents.

### 6. Automated Testing & Verification
- [x] All 7 automated test suites passing (`flutter test` 7/7).
- [x] Flutter static analysis passes cleanly (`0 issues`).

---

## 📋 Next Phases / Roadmap

- [ ] Support private GitHub repositories via personal access tokens in Settings.
- [ ] Offline local LLM backend option (Ollama / llama.cpp local endpoint).
- [ ] Direct export of generated prompts to `.cursorrules` or `.windsurfrules`.
