# AI-Response Backend

FastAPI backend for project-based AI memory + real-time voice Q&A.

## Important
`ChatGPT Plus/Pro` uyeligi API anahtari degildir.
Bu backend icin `OPENAI_API_KEY` gerekir (OpenAI Platform).

## Features
- Project-based separation (`/projects`)
- Text source upload + AI analysis
- PDF/DOCX upload + text extraction + AI analysis
- Project context retrieval
- Real-time SSE answer stream (`/ai/respond`)

## Setup
1. `cd backend`
2. `cp .env.example .env`
3. `.env` icine `OPENAI_API_KEY` yaz
4. `./run.sh`

## Main Endpoints
- `POST /auth/register`
- `POST /auth/login`
- `GET /projects`
- `POST /projects`
- `POST /projects/{project_id}/sources/text`
- `POST /projects/{project_id}/sources/file` (PDF/DOCX)
- `GET /projects/{project_id}/context`
- `POST /ai/respond` (SSE)
