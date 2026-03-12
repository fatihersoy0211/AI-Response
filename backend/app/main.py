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
    AIChatRequest,
    AIRespondRequest,
    AppleAuthRequest,
    AudioAssetResponse,
    AuthResponse,
    ChatTurnResponse,
    ImportAudioAssetRequest,
    ImportAudioAssetResponse,
    LoginRequest,
    ProjectContextResponse,
    ProjectContextSnapshotResponse,
    ProjectCreateRequest,
    ProjectDocumentResponse,
    ProjectResponse,
    ProjectTranscriptResponse,
    RegisterRequest,
    SaveAudioAssetRequest,
    SaveChatTurnRequest,
    SaveSummaryRequest,
    SourceResponse,
    SummaryResponse,
    TextSourceUploadRequest,
    TranscriptSaveRequest,
    UserProfileResponse,
)
from .store import JsonStore, UserRecord

load_dotenv()

app = FastAPI(title="AI Response API", version="0.5.0")

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


def get_openai_client(
    x_openai_api_key: str | None = Header(default=None),
) -> OpenAI:
    # Client-supplied key (from iOS Keychain) takes priority over server .env
    api_key = (x_openai_api_key or os.getenv("OPENAI_API_KEY", "")).strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "OPENAI_API_KEY is missing. Add your key in the app under "
                "Settings → Privacy & Security → Custom OpenAI API Key, "
                "or set OPENAI_API_KEY in the backend .env file. "
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


def build_respond_input_layered(
    project_name: str,
    document_context: str,
    stored_transcript_history: str,
    session_transcript_history: str | None,
    live_transcript: str,
) -> str:
    """
    Assemble AI prompt in strict 4-layer order:
    1. Project name (header)
    2. Project documents & extracted text (uploaded files, text sources)
    3. Historical transcripts (stored in DB + current session history)
    4. Current live transcript (freshest — highest priority)
    """
    parts = [f"# Project: {project_name}"]

    # Layer 2: documents
    if document_context.strip():
        parts += ["", "## Project Knowledge Base (Documents & Uploaded Text)", document_context[:_MAX_CONTEXT_CHARS]]
    else:
        parts += ["", "## Project Knowledge Base", "(No documents uploaded yet — use live transcript only)"]

    # Layer 3a: stored transcript history from DB
    if stored_transcript_history.strip():
        parts += ["", "## Historical Meeting Transcripts (from project)", stored_transcript_history[:_MAX_SESSION_CHARS // 2]]

    # Layer 3b: current session history (from client)
    if session_transcript_history and session_transcript_history.strip():
        sess = session_transcript_history.strip()
        if len(sess) > _MAX_SESSION_CHARS // 2:
            sess = "...(earlier truncated)\n" + sess[-_MAX_SESSION_CHARS // 2:]
        parts += ["", "## Current Session History", sess]

    # Layer 4: live transcript (always last — freshest context)
    live = live_transcript.strip()
    parts += [
        "",
        "## Current Live Transcript (Freshest — Use As Primary Context)" if live
        else "## Current Request",
        live if live else "(No live transcript — respond from project knowledge base)",
    ]

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


@app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
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
    client: OpenAI = Depends(get_openai_client),
) -> SourceResponse:
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

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
    client: OpenAI = Depends(get_openai_client),
) -> SourceResponse:
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

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
    client: OpenAI = Depends(get_openai_client),
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


@app.get("/projects/{project_id}/context/snapshot", response_model=ProjectContextSnapshotResponse)
def get_project_context_snapshot(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> ProjectContextSnapshotResponse:
    try:
        ctx = store.project_context_layered(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    def to_source_response(s: dict) -> SourceResponse:
        return SourceResponse(
            sourceId=s["source_id"],
            sourceType=s["source_type"],
            title=s["title"],
            analysis=s["analysis"],
            createdAtISO8601=s["created_at"],
        )

    return ProjectContextSnapshotResponse(
        projectId=ctx["project_id"],
        projectName=ctx["project_name"],
        documentContext=ctx["document_context"],
        transcriptHistory=ctx["transcript_history"],
        chatHistory=ctx["chat_history"],
        mergedText=ctx["merged_text"],
        documents=[to_source_response(d) for d in ctx["documents"]],
        transcripts=[to_source_response(t) for t in ctx["transcripts"]],
        lastUpdatedISO8601=ctx["last_updated"],
    )


@app.post("/projects/{project_id}/audio_assets", response_model=AudioAssetResponse)
def save_audio_asset(
    project_id: str,
    payload: SaveAudioAssetRequest,
    user: UserRecord = Depends(get_current_user),
) -> AudioAssetResponse:
    try:
        asset = store.save_audio_asset(
            user_id=user.user_id,
            project_id=project_id,
            title=payload.title,
            mime_type=payload.mimeType,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return AudioAssetResponse(
        assetId=asset["asset_id"],
        title=asset["title"],
        mimeType=asset["mime_type"],
        createdAtISO8601=asset["created_at"],
    )


@app.post("/projects/{project_id}/audio_assets/import", response_model=ImportAudioAssetResponse)
def import_audio_asset(
    project_id: str,
    payload: ImportAudioAssetRequest,
    user: UserRecord = Depends(get_current_user),
    client: OpenAI = Depends(get_openai_client),
) -> ImportAudioAssetResponse:
    """
    Import an audio asset with optional transcript.
    If a transcript is provided it is automatically saved as a project source,
    making it available in all future AI context builds for this project.
    """
    project = store.get_project(user.user_id, project_id)
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

    # If transcript provided, index it for better AI context
    indexed_transcript = payload.transcript
    if payload.transcript and payload.transcript.strip():
        indexed_transcript = index_transcript(client, payload.transcript)

    transcript_status = (
        "completed" if payload.transcript and payload.transcript.strip() else "pending"
    )

    try:
        asset = store.import_audio_asset(
            user_id=user.user_id,
            project_id=project_id,
            file_name=payload.fileName,
            mime_type=payload.mimeType,
            source_type=payload.sourceType,
            duration_seconds=payload.durationSeconds,
            transcript=indexed_transcript,
            transcript_status=transcript_status,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return ImportAudioAssetResponse(
        assetId=asset["asset_id"],
        projectId=project_id,
        title=asset["title"],
        sourceType=asset["source_type"],
        mimeType=asset["mime_type"],
        durationSeconds=asset["duration_seconds"],
        transcriptionStatus=asset["transcription_status"],
        createdAtISO8601=asset["created_at"],
    )


@app.get("/projects/{project_id}/documents", response_model=list[ProjectDocumentResponse])
def list_project_documents(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> list[ProjectDocumentResponse]:
    try:
        docs = store.list_project_documents(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return [
        ProjectDocumentResponse(
            sourceId=d["source_id"],
            projectId=project_id,
            fileName=d["title"],
            fileType=d.get("source_type", "file"),
            extractedText=d.get("raw_text", d.get("analysis", "")),
            extractionStatus="completed",
            createdAtISO8601=d["created_at"],
            updatedAtISO8601=d["created_at"],
        )
        for d in docs
    ]


@app.get("/projects/{project_id}/transcripts", response_model=list[ProjectTranscriptResponse])
def list_project_transcripts(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> list[ProjectTranscriptResponse]:
    try:
        transcripts = store.list_project_transcripts(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return [
        ProjectTranscriptResponse(
            sourceId=t["source_id"],
            projectId=project_id,
            title=t["title"],
            analysis=t.get("analysis", ""),
            sourceType=t.get("audio_source_type", t.get("source_type", "liveListening")),
            createdAtISO8601=t["created_at"],
        )
        for t in transcripts
    ]


# ---------------------------------------------------------------------------
# Chat turn persistence
# ---------------------------------------------------------------------------

@app.get("/projects/{project_id}/chat", response_model=list[ChatTurnResponse])
def list_chat_turns(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> list[ChatTurnResponse]:
    try:
        turns = store.list_chat_turns(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return [
        ChatTurnResponse(
            turnId=t["turn_id"],
            projectId=t["project_id"],
            role=t["role"],
            content=t["content"],
            createdAtISO8601=t["created_at"],
            turnIndex=t["turn_index"],
        )
        for t in turns
    ]


@app.post("/projects/{project_id}/chat", response_model=ChatTurnResponse, status_code=status.HTTP_201_CREATED)
def save_chat_turn(
    project_id: str,
    payload: SaveChatTurnRequest,
    user: UserRecord = Depends(get_current_user),
) -> ChatTurnResponse:
    try:
        turn = store.save_chat_turn(
            user_id=user.user_id,
            project_id=project_id,
            role=payload.role,
            content=payload.content,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return ChatTurnResponse(
        turnId=turn["turn_id"],
        projectId=turn["project_id"],
        role=turn["role"],
        content=turn["content"],
        createdAtISO8601=turn["created_at"],
        turnIndex=turn["turn_index"],
    )


@app.delete("/projects/{project_id}/chat", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
def clear_chat_turns(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> None:
    try:
        store.clear_chat_turns(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@app.get("/projects/{project_id}/summaries", response_model=list[SummaryResponse])
def list_summaries(
    project_id: str,
    user: UserRecord = Depends(get_current_user),
) -> list[SummaryResponse]:
    try:
        summaries = store.list_project_summaries(user.user_id, project_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return [
        SummaryResponse(
            summaryId=s["summary_id"],
            style=s["style"],
            content=s["content"],
            generatedAtISO8601=s["generated_at"],
        )
        for s in summaries
    ]


@app.post("/projects/{project_id}/summaries", response_model=SummaryResponse)
def save_summary(
    project_id: str,
    payload: SaveSummaryRequest,
    user: UserRecord = Depends(get_current_user),
) -> SummaryResponse:
    try:
        summary = store.save_project_summary(
            user_id=user.user_id,
            project_id=project_id,
            style=payload.style,
            content=payload.content,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return SummaryResponse(
        summaryId=summary["summary_id"],
        style=summary["style"],
        content=summary["content"],
        generatedAtISO8601=summary["generated_at"],
    )


@app.post("/ai/respond")
def ai_respond(
    payload: AIRespondRequest,
    user: UserRecord = Depends(get_current_user),
    client: OpenAI = Depends(get_openai_client),
):
    try:
        ctx = store.project_context_layered(user.user_id, payload.projectId)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    model = _respond_model()
    user_display = (payload.userName or "").strip() or "the user"

    user_input = build_respond_input_layered(
        project_name=ctx["project_name"],
        document_context=ctx["document_context"],
        stored_transcript_history=ctx["transcript_history"],
        session_transcript_history=payload.transcriptHistory,
        live_transcript=payload.liveTranscript,
    )

    # System instructions — personalised with the user's name when available
    system_instructions = (
        f"You are a personal AI meeting assistant dedicated to {user_display}. "
        f"You know everything about {user_display}'s projects and act as their expert advisor. "
        "Answer using only the project knowledge base and the meeting context provided. "
        "Give short, clear, actionable answers (max 5 sentences or 5 bullet points). "
        "If the knowledge base has no relevant information, say so clearly; never fabricate. "
        "If no transcript is provided, summarise the most important insights from the project knowledge base. "
        "Respond in the same language as the transcript (default to English if no transcript)."
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


@app.post("/ai/chat")
def ai_chat(
    payload: AIChatRequest,
    user: UserRecord = Depends(get_current_user),
    client: OpenAI = Depends(get_openai_client),
):
    """
    Multi-turn AI chat grounded strictly in the selected project's knowledge base.
    Each call receives the full conversation history so the model stays context-aware.
    """
    try:
        ctx = store.project_context_layered(user.user_id, payload.projectId)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    model = _respond_model()

    user_display = (payload.userName or "").strip() or "the user"
    system_instructions = (
        f"You are a personal AI meeting assistant dedicated to {user_display}. "
        f"You know {user_display}'s project context thoroughly and act as their trusted advisor. "
        "Answer ONLY from the project knowledge base provided. Never fabricate. "
        "Be concise, clear, and actionable (max 5 sentences or 5 bullet points unless more depth is needed). "
        "Respond in the same language as the user's latest message."
    )

    # Build user input: layered project context + conversation history + current question
    doc_ctx = ctx["document_context"][:_MAX_CONTEXT_CHARS]
    transcript_ctx = ctx["transcript_history"][:_MAX_SESSION_CHARS // 2]

    history_lines = []
    for msg in payload.messages[:-1]:   # all but the latest
        prefix = user_display if msg.role == "user" else "Assistant"
        history_lines.append(f"{prefix}: {msg.content}")

    current_message = payload.messages[-1].content if payload.messages else ""

    user_input = f"# Project: {ctx['project_name']}\n\n"

    if doc_ctx:
        user_input += f"## Project Knowledge Base (Documents)\n{doc_ctx}\n\n"
    else:
        user_input += "## Project Knowledge Base\n(No documents uploaded yet)\n\n"

    if transcript_ctx:
        user_input += f"## Historical Meeting Transcripts\n{transcript_ctx}\n\n"

    if history_lines:
        user_input += "## Conversation History\n" + "\n\n".join(history_lines) + "\n\n"

    user_input += f"## Current Message\n{current_message}"

    def event_stream():
        try:
            with client.responses.stream(
                model=model,
                instructions=system_instructions,
                input=user_input,
                temperature=0.3,
                max_output_tokens=800,
            ) as stream:
                for delta in stream.text_deltas:
                    if delta:
                        yield f"data: {json.dumps({'delta': delta}, ensure_ascii=False)}\n\n"
            yield 'data: {"done": true}\n\n'
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)}, ensure_ascii=False)}\n\n"
            yield 'data: {"done": true}\n\n'

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
