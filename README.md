# AI-Response

iOS 17+ SwiftUI app + FastAPI backend.

## What is implemented
- Login/register
- Project-based topic separation (user-defined project names)
- Text input upload and AI analysis
- PDF/DOCX upload and AI analysis
- Voice listen -> ask AI -> instant streamed answer (SSE)
- Answers use analyzed project knowledge + live transcript

## Important
`ChatGPT Plus/Pro` uyeligi API yerine gecmez.
Backend icin `OPENAI_API_KEY` zorunlu.

## Backend Run
1. `cd /Users/fatihersoy/Repo/AI-Response/backend`
2. `cp .env.example .env`
3. `.env` icine `OPENAI_API_KEY` ekle
4. `./run.sh`

Backend URL: `http://127.0.0.1:8080`

## iOS Run
1. Full Xcode kurulu olsun.
2. Gerekirse sec:
   - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. Ac:
   - `open /Users/fatihersoy/Repo/AI-Response/AIResponse.xcodeproj`
4. Simulator sec ve Run.

## API Contract
- `backend-contract/openapi.yaml`
