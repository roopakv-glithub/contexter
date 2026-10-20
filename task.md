# ContextForge — Task Tracker & Architecture Roadmap

> **Repository:** https://github.com/roopakv-glithub/contexter  
> **Application:** ContextForge (Flutter Windows Desktop)  
> **Status:** Production Release v1.6.0  
> **Database & Functions:** Supabase (`tociitdxzqcdkfjacchs.supabase.co`)  
> **AI Inference:** NVIDIA NIM (`nvidia/nemotron-3.5-lightning-30b-a3b`)  
> **GitHub Converter:** Repo-to-Markdown (`https://repo-to-markdown.com/`)  

---

## 🚀 Overview & Current State

ContextForge evolves the desktop application into a repository-aware analysis and AI prompt generation workspace.
It analyzes local and GitHub codebases, identifies architecture and dependencies, preserves environment variables and secrets, and compiles production-ready Next-Step Development (NNSD) prompts for AI coding agents.

---

## ✅ Completed Tasks

### 1. Application Branding & Mascot Image Integration (v1.6.0)
- [x] Application logo added and rendered in Home heading and Sidebar using the new attached infinity circuit logo (`assets/images/app_logo.png`).
- [x] Mascot emojis replaced with high-resolution companion robot avatars:
  - Momo: Friendly purple robot with headset (`assets/images/mascot_momo.png`)
  - Byte: Blue companion with laptop (`assets/images/mascot_byte.png`)
  - Pixel: Focused mint creature with checklist (`assets/images/mascot_pixel.png`)
- [x] Home page header explicitly branded as **ContextForge**.
- [x] All mascot views in Home, Setup, My Agents, Review, and Companion updated to render mascot image assets with graceful fallback.

### 2. NNSD Prompt Generation Pipeline & Structure (v1.6.0)
- [x] **Strict 3-Section Output Format Enforced:**
  - **SECTION A — NNSD IMPLEMENTATION PROMPT** (Always appears FIRST).
    Structured into the required 10 numbered subsections:
    1. Objective
    2. Existing Functionality
    3. Required Changes
    4. Relevant Files to Inspect or Modify
    5. Dependencies and Technologies
    6. Implementation Instructions
    7. Environment and Configuration Constraints
    8. Compatibility and Preservation Requirements
    9. Acceptance Criteria
    10. Verification
  - **SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT** (Always appears SECOND).
    Displays project structure, architecture, identified technologies, dependencies, and analyzed files.
    Displays explicit notice if local analysis is unavailable.
  - **SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT** (Always appears THIRD).
    Displays remote repository structure, architecture, dependencies, key source files, and recommendations.
    Displays explicit notice if GitHub analysis is unavailable.
- [x] **Prompt Reasoning & Grounding:**
  - AI reasoning (NVIDIA Nemotron `nvidia/nemotron-3.5-lightning-30b-a3b`) is dedicated 100% to Section A, preventing token truncation or prompt deviation.
  - Grounded file matching prevents hallucinated file paths.
  - Full deterministic fallback generates the complete 10-subsection Section A offline or when API is unconfigured.
  - Secret redaction runs across user requests, context summaries, and generated prompts.

### 3. GitHub Repository Analysis via Repo-to-Markdown (v1.5.0)
- [x] Full repository conversion using Repo-to-Markdown protocol (`lib/services/github_repo_analyzer.dart` and `scripts/repo_to_markdown.js`).
- [x] Overcomes unauthenticated GitHub API rate limits.
- [x] Automated license header removal and secret redaction.
- [x] Semantic AI summarization with NVIDIA Nemotron.

### 4. Protected Core Features
- [x] Local folder scanner (`repository_scanner.dart`) preserved with secret redaction.
- [x] Local folder analysis pipeline (`analyzeFolder`) preserved.
- [x] Local history persistence (`local_history.dart`) preserved.
- [x] Settings & NVIDIA API key storage preserved.

### 5. Automated Testing & Verification
- [x] 20 unit and widget tests passing (`flutter test` 20/20):
  - Section ordering (A then B then C)
  - All 10 numbered subsections in Section A
  - User task and explicit constraints preservation
  - Grounded file inspection without hallucination
  - Missing summary handling (local and remote)
  - Secret redaction in prompt and outputs
  - Large context handling without truncation
  - NVIDIA API key caching and persistence
  - Full 3-step project setup flow
- [x] Flutter static analysis passes with 0 issues (`flutter analyze`).

---

## 📋 Next Phases / Roadmap

- [ ] Support private GitHub repositories via personal access tokens in Settings.
- [ ] Offline local LLM backend option (Ollama / llama.cpp local endpoint).
- [ ] Direct export of generated prompts to `.cursorrules` or `.windsurfrules`.
