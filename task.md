# ContextForge — Task Tracker & Architecture Roadmap

> **Repository:** https://github.com/roopakv-glithub/contexter  
> **Application:** ContextForge (Flutter Windows Desktop)  
> **Status:** Production Release v1.5.0  
> **Database & Functions:** Supabase (`tociitdxzqcdkfjacchs.supabase.co`)  
> **AI Inference:** NVIDIA NIM (`nvidia/nemotron-3.5-lightning-30b-a3b`)  
> **GitHub Converter:** Repo-to-Markdown (`https://repo-to-markdown.com/`)  

---

## 🚀 Overview & Current State

ContextForge evolves the desktop application into a repository-aware analysis and AI prompt generation workspace.
It analyzes local and GitHub codebases, identifies architecture and dependencies, preserves environment variables and secrets, and compiles production-ready prompts for AI coding agents.

---

## ✅ Completed Tasks

### 1. Application Rebranding
- [x] Application display name renamed to **ContextForge** across metadata, windows runners, window title bars, UI headers, and companion cards.
- [x] Fixed legacy labels (e.g. replaced "Moscowt" with "ContextForge" / "Companion").

### 2. GitHub Repository Analysis via Repo-to-Markdown (v1.5.0)
- [x] Inspected `https://repo-to-markdown.com/`: client-side conversion engine using GitHub Git trees API and Raw content endpoints with glob filtering and license stripping.
- [x] Identified why earlier implementation analyzed only README: unauthenticated GitHub API rate limits (60 req/hr) caused public tree requests to fail silently or truncate to README only.
- [x] Created isolated `lib/services/github_repo_analyzer.dart` adhering strictly to Repo-to-Markdown protocol:
  - URL normalization and branch/subdirectory resolution.
  - Tree retrieval with authenticated PAT support.
  - Filtering with Repo-to-Markdown skip patterns and binary extensions.
  - Automated license header removal and secret redaction.
  - Unified `# Repository Overview`, `# Repository Structure` tree, and `// File: <path>` sections.
  - Verification that Markdown contains real source files beyond README.
- [x] Added `scripts/repo_to_markdown.js` automation runner.
- [x] Full chunked semantic AI analysis using NVIDIA Nemotron model.
- [x] Live progress indicators during repository conversion and analysis.

### 3. Strictly Protected Local Folder Analysis
- [x] Local folder scanner (`repository_scanner.dart`) left 100% untouched.
- [x] Local folder analysis pipeline (`analyzeFolder`) strictly preserved with offline fallback.
- [x] Local history persistence (`local_history.dart`) completely preserved.

### 4. Supabase Cloud Setup & Functions Deployment
- [x] Connected to user's Supabase project: `https://tociitdxzqcdkfjacchs.supabase.co`.
- [x] Database migrations applied (`analysis_reports`, `prompt_history`, `ai_request_limits`, `consume_ai_request` RPC).
- [x] Edge Functions deployed & ACTIVE (`analyze-project`, `enhance-prompt`).

### 5. NVIDIA API Key Configuration & Integration
- [x] Settings page NVIDIA API key input with show/hide toggle, local persistent storage (`nvidia_key.txt`), and live connection testing.
- [x] Upgraded model to `nvidia/nemotron-3.5-lightning-30b-a3b` with reasoning parameters (`enable_thinking`, `reasoning_budget`).

### 6. Automated Testing & Verification
- [x] All 13 unit and widget tests passing (`flutter test` 13/13).
- [x] Flutter static analysis passes cleanly (`0 issues`).

---

## 📋 Next Phases / Roadmap

- [ ] Support private GitHub repositories via personal access tokens in Settings.
- [ ] Offline local LLM backend option (Ollama / llama.cpp local endpoint).
- [ ] Direct export of generated prompts to `.cursorrules` or `.windsurfrules`.
