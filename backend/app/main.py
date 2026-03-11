from __future__ import annotations

import base64
import json
import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from openai import OpenAI

from .extractors import extract_text_from_file
from .schemas import (
    AIRespondRequest,
    AppleAuthRequest,
    AuthResponse,
    LoginRequest,
    ProjectContextResponse,
    ProjectCreateRequest,
    ProjectResponse,
    RegisterRequest,
    SourceResponse,
    TextSourceUploadRequest,
    TranscriptSaveRequest,
    UserProfileResponse,
)
from .store import JsonStore, UserRecord

load_dotenv()

app = FastAPI(title="AI Response API", version="0.4.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

store = JsonStore(Path(__file__).resolve().parent.parent / "data" / "store.json")

# ---------------------------------------------------------------------------
# Model config
# OPENAI_MODEL        – used for source analysis + transcript indexing (cheap)
# OPENAI_RESPOND_MODEL – used for live AI respond (can be more capable)
# ---------------------------------------------------------------------------
_DEFAULT_ANALYZE_MODEL = "gpt-4.1-mini"
_DEFAULT_RESPOND_MODEL = "gpt-4.1-mini"

# Maximum characters allowed per section of the AI prompt.
# gpt-4.1-mini has a 1M token context window; these limits keep cost/latency low.
_MAX_CONTEXT_CHARS = 12_000
_MAX_SESSION_CHARS = 8_000
_MAX_TRANSCRIPT_CHARS = 4_000


def _analyze_model() -> str:
    return os.getenv("OPENAI_MODEL", _DEFAULT_ANALYZE_MODEL).strip()


def _respond_model() -> str:
    return os.getenv("OPENAI_RESPOND_MODEL", os.getenv("OPENAI_MODEL", _DEFAULT_RESPOND_MODEL)).strip()


def get_openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "OPENAI_API_KEY is missing. A ChatGPT subscription is not an API key; "
                "Get your API key at: https://platform.openai.com/api-keys"
            ),
        )
    # 60-second timeout — prevents hanging when OpenAI is slow
    return OpenAI(api_key=api_key, timeout=60.0)


def get_current_user(authorization: str | None = Header(default=None)) -> UserRecord:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = authorization.removeprefix("Bearer ").strip()
    user = store.get_user_by_token(token)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return user


# ---------------------------------------------------------------------------
# AI helpers
# ---------------------------------------------------------------------------

def analyze_source_text(client: OpenAI, project_name: str, title: str, text: str) -> str:
    """
    Extract a compact, actionable memory chunk from a source document.
    Uses the Responses API with a separate instructions field (system role)
    for clean prompt separation.
    """
    model = _analyze_model()

    try:
        response = client.responses.create(
            model=model,
            instructions=(
                "You are a knowledge extractor for a meeting assistant memory engine. "
                "Your task: extract a short, bullet-point, actionable summary from the given source. "
                "Only use information present in the source. Never fabricate. "
                "Format: bullet points (•). Max 400 words. Match the language of the source text."
            ),
            input=(
                f"Project: {project_name}\n"
                f"Source title: {title}\n\n"
                f"Source content:\n{text[:18_000]}"
            ),
            temperature=0.1,
            max_output_tokens=500,
        )
        summary = (response.output_text or "").strip()
        return summary if summary else "Source analyzed; no summary could be generated."
    except Exception as exc:
        # Non-fatal — we store the source without analysis rather than blocking upload
        return f"Analysis failed: {exc}"


def index_transcript(client: OpenAI, transcript: str) -> str:
    """
    Lightweight indexing of a meeting transcript (cheap, fast).
    Extracts key points, decisions and action items only.
    """
    model = _analyze_model()

    try:
        response = client.responses.create(
            model=model,
            instructions=(
                "Extract only the following from the meeting transcript: "
                "key points, decisions made, action items (who, when). "
                "Write with bullet points (•). Max 250 words. Match the language of the transcript."
            ),
            input=f"Transcript:\n{transcript[:12_000]}",
            temperature=0.1,
            max_output_tokens=350,
        )
        result = (response.output_text or "").strip()
        return result if result else "Transcript saved."
    except Exception:
        return "Transcript saved (indexing failed)."


def build_respond_input(
    context_summary: str,
    session_transcript: str | None,
    current_transcript: str,
) -> str:
    """
    Build the user-turn input for /ai/respond.
    System instructions are passed separately via the `instructions` parameter.
    Each section is clearly delimited and length-capped.
    """
    ctx = context_summary[:_MAX_CONTEXT_CHARS]
    cur = current_transcript.strip()[:_MAX_TRANSCRIPT_CHARS]

    parts: list[str] = [
        "## Project Knowledge Base",
        ctx if ctx else "(No sources uploaded for this project yet.)",
    ]

    if session_transcript and session_transcript.strip():
        sess = session_transcript.strip()
        # Keep only the most recent part if too long
        if len(sess) > _MAX_SESSION_CHARS:
            sess = "...(earlier conversation truncated)\n" + sess[-_MAX_SESSION_CHARS:]
        parts += ["", "## Previous Conversation History This Meeting", sess]

    parts += ["", "## Current Question / Transcript", cur]

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "version": app.version}


@app.post("/auth/register", response_model=AuthResponse)
def register(payload: RegisterRequest) -> AuthResponse:
    try:
        user = store.register_user(payload.name, payload.email, payload.password)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    token = store.create_session(user.user_id)
    return AuthResponse(userId=user.user_id, name=user.name, email=user.email, accessToken=token, refreshToken=None)


@app.post("/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest) -> AuthResponse:
    user = store.authenticate_user(payload.email, payload.password)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    token = store.create_session(user.user_id)
    return AuthResponse(userId=user.user_id, name=user.name, email=user.email, accessToken=token, refreshToken=None)


@app.get("/auth/me", response_model=UserProfileResponse)
def get_me(user: UserRecord = Depends(get_current_user)) -> UserProfileResponse:
    return UserProfileResponse(
        userId=user.user_id,
        name=user.name,
        email=user.email,
        createdAtISO8601=user.created_at,
    )


@app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(user: UserRecord = Depends(get_current_user), authorization: str | None = Header(default=None)):
    if authorization:
        token = authorization.removeprefix("Bearer ").strip()
        store.delete_session(token)


@app.post("/auth/apple", response_model=AuthResponse)
def apple_sign_in(payload: AppleAuthRequest) -> AuthResponse:
    """
    Apple Sign In endpoint.
    Decodes the identity token JWT to verify the sub claim matches userIdentifier,
    then creates or retrieves the user account.
    """
    # Decode the JWT payload (middle section) without signature verification.
    # In production, verify with Apple's JWKS at https://appleid.apple.com/auth/keys.
    try:
        parts = payload.identityToken.split(".")
        if len(parts) != 3:
            raise ValueError("Invalid JWT format")
        # Add padding for base64 decoding
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Identity token could not be decoded: {exc}",
        ) from exc

    jwt_sub = claims.get("sub", "")
    if jwt_sub != payload.userIdentifier:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identity token could not be verified",
        )

    # Prefer email from JWT claims (more reliable than client-sent email)
    email = claims.get("email") or payload.email or ""
    name = (payload.name or "").strip() or (email.split("@")[0] if email else "Apple User")

    user = store.find_or_create_apple_user(
        apple_id=payload.userIdentifier,
        email=email,
        name=name,
    )
    token = store.create_session(user.user_id)
    return AuthResponse(userId=user.user_id, name=user.name, email=user.email, accessToken=token, refreshToken=None)


@app.get("/projects", response_model=list[ProjectResponse])
def list_projects(user: UserRecord = Depends(get_current_user)) -> list[ProjectResponse]:
    return [
        ProjectResponse(
            projectId=p["project_id"],
            name=p["name"],
            createdAtISO8601=p["created_at"],
            updatedAtISO8601=p["updated_at"],
        )
        for p in store.list_projects(user.user_id)
    ]


@app.post("/projects", response_model=ProjectResponse)
def create_project(payload: ProjectCreateRequest, user: UserRecord = Depends(get_current_user)) -> ProjectResponse:
    project = store.create_project(user.user_id, payload.name)
    return ProjectResponse(
        projectId=project["project_id"],
        name=project["name"],
        createdAtISO8601=project["created_at"],
        updatedAtISO8601=project["updated_at"],
    )


@app.post("/projects/{project_id}/sources/text", response_model=SourceResponse)
def upload_text_source(
    project_id: str,
    payload: TextSourceUploadRequest,
    user: UserRecord = Depends(get_current_user),
) -> SourceResponse:
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

    client = get_openai_client()
    analysis = analyze_source_text(client, project["name"], payload.title, payload.text)

    source = store.add_project_source(
        user.user_id, project_id,
        source_type="text", title=payload.title,
        raw_text=payload.text, analysis=analysis,
    )
    return SourceResponse(
        sourceId=source["source_id"], sourceType=source["source_type"],
        title=source["title"], analysis=source["analysis"],
        createdAtISO8601=source["created_at"],
    )


@app.post("/projects/{project_id}/sources/transcript", response_model=SourceResponse)
def save_transcript_source(
    project_id: str,
    payload: TranscriptSaveRequest,
    user: UserRecord = Depends(get_current_user),
) -> SourceResponse:
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

    client = get_openai_client()
    analysis = index_transcript(client, payload.transcript)

    source = store.add_project_source(
        user.user_id, project_id,
        source_type="transcript", title=payload.title,
        raw_text=payload.transcript, analysis=analysis,
    )
    return SourceResponse(
        sourceId=source["source_id"], sourceType=source["source_type"],
        title=source["title"], analysis=source["analysis"],
        createdAtISO8601=source["created_at"],
    )


@app.post("/projects/{project_id}/sources/file", response_model=SourceResponse)
async def upload_file_source(
    project_id: str,
    file: UploadFile = File(...),
    user: UserRecord = Depends(get_current_user),
) -> SourceResponse:
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

    filename = file.filename or "uploaded-file"
    data = await file.read()

    try:
        extracted = extract_text_from_file(filename, data)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    if not extracted.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not extract readable text from file",
        )

    client = get_openai_client()
    analysis = analyze_source_text(client, project["name"], filename, extracted)

    source = store.add_project_source(
        user.user_id, project_id,
        source_type="file", title=filename,
        raw_text=extracted, analysis=analysis,
    )
    return SourceResponse(
        sourceId=source["source_id"], sourceType=source["source_type"],
        title=source["title"], analysis=source["analysis"],
        createdAtISO8601=source["created_at"],
    )


@app.get("/projects/{project_id}/context", response_model=ProjectContextResponse)
def get_project_context(project_id: str, user: UserRecord = Depends(get_current_user)) -> ProjectContextResponse:
    try:
        summary, sources, last_updated = store.project_context(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return ProjectContextResponse(
        summary=summary,
        sources=[
            SourceResponse(
                sourceId=s["source_id"], sourceType=s["source_type"],
                title=s["title"], analysis=s["analysis"],
                createdAtISO8601=s["created_at"],
            )
            for s in sources
        ],
        lastUpdatedISO8601=last_updated,
    )


@app.post("/ai/respond")
def ai_respond(payload: AIRespondRequest, user: UserRecord = Depends(get_current_user)):
    try:
        context_summary, _, _ = store.project_context(user.user_id, payload.projectId)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    client = get_openai_client()
    model = _respond_model()

    user_input = build_respond_input(
        context_summary=context_summary,
        session_transcript=payload.sessionTranscript,
        current_transcript=payload.transcript,
    )

    # System instructions — separated from user content for better model behavior
    system_instructions = (
        "You are a real-time meeting assistant. "
        "Answer using only the project knowledge base and the context of this meeting. "
        "Give short, clear, actionable answers (max 5 sentences or 5 bullet points). "
        "If the knowledge base has no relevant information, say so clearly; never fabricate. "
        "Respond in the same language as the transcript."
    )

    def event_stream():
        try:
            # Use text_deltas iterator — cleaner than raw event loop,
            # automatically handles all delta event types.
            with client.responses.stream(
                model=model,
                instructions=system_instructions,
                input=user_input,
                temperature=0.2,
                max_output_tokens=600,
            ) as stream:
                for delta in stream.text_deltas:
                    if delta:
                        yield f"data: {json.dumps({'delta': delta}, ensure_ascii=False)}\n\n"

            # Always send done — even if the loop body raised no items
            yield 'data: {"done": true}\n\n'

        except Exception as exc:
            # Send error as a proper SSE event, then close with done
            err_payload = {"error": str(exc)}
            yield f"data: {json.dumps(err_payload, ensure_ascii=False)}\n\n"
            yield 'data: {"done": true}\n\n'

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",   # disable nginx buffering
        },
    )
