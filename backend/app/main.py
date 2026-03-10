from __future__ import annotations

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
    AuthResponse,
    LoginRequest,
    ProjectContextResponse,
    ProjectCreateRequest,
    ProjectResponse,
    RegisterRequest,
    SourceResponse,
    TextSourceUploadRequest,
)
from .store import JsonStore, UserRecord

load_dotenv()

app = FastAPI(title="AI Response API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

store = JsonStore(Path(__file__).resolve().parent.parent / "data" / "store.json")


def get_openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "OPENAI_API_KEY missing. ChatGPT uyeligi dogrudan API olarak kullanilamaz; "
                "OpenAI API key gerekli."
            ),
        )
    return OpenAI(api_key=api_key)


def get_current_user(authorization: str | None = Header(default=None)) -> UserRecord:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = authorization.removeprefix("Bearer ").strip()
    user = store.get_user_by_token(token)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return user


def analyze_source_text(client: OpenAI, model: str, project_name: str, title: str, text: str) -> str:
    prompt = (
        "You are extracting actionable memory for a voice assistant. "
        "Create a compact factual summary in Turkish. Include key entities, constraints, and instructions. "
        "Do not invent information.\n\n"
        f"Project: {project_name}\n"
        f"Source title: {title}\n"
        f"Source text:\n{text[:18000]}"
    )

    response = client.responses.create(
        model=model,
        input=prompt,
        temperature=0.1,
        max_output_tokens=450,
    )
    summary = (response.output_text or "").strip()
    return summary if summary else "Kaynak analiz edildi, ancak ozet cikarilamadi."


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/auth/register", response_model=AuthResponse)
def register(payload: RegisterRequest) -> AuthResponse:
    try:
        user = store.register_user(payload.name, payload.email, payload.password)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    token = store.create_session(user.user_id)
    return AuthResponse(userId=user.user_id, accessToken=token, refreshToken=None)


@app.post("/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest) -> AuthResponse:
    user = store.authenticate_user(payload.email, payload.password)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    token = store.create_session(user.user_id)
    return AuthResponse(userId=user.user_id, accessToken=token, refreshToken=None)


@app.get("/projects", response_model=list[ProjectResponse])
def list_projects(user: UserRecord = Depends(get_current_user)) -> list[ProjectResponse]:
    projects = store.list_projects(user.user_id)
    return [
        ProjectResponse(
            projectId=p["project_id"],
            name=p["name"],
            createdAtISO8601=p["created_at"],
            updatedAtISO8601=p["updated_at"],
        )
        for p in projects
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
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

    try:
        analysis = analyze_source_text(client, model, project["name"], payload.title, payload.text)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=f"Source analysis failed: {exc}") from exc

    source = store.add_project_source(
        user.user_id,
        project_id,
        source_type="text",
        title=payload.title,
        raw_text=payload.text,
        analysis=analysis,
    )
    return SourceResponse(
        sourceId=source["source_id"],
        sourceType=source["source_type"],
        title=source["title"],
        analysis=source["analysis"],
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

    if not extracted:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Could not extract readable text from file")

    client = get_openai_client()
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

    try:
        analysis = analyze_source_text(client, model, project["name"], filename, extracted)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=f"File analysis failed: {exc}") from exc

    source = store.add_project_source(
        user.user_id,
        project_id,
        source_type="file",
        title=filename,
        raw_text=extracted,
        analysis=analysis,
    )
    return SourceResponse(
        sourceId=source["source_id"],
        sourceType=source["source_type"],
        title=source["title"],
        analysis=source["analysis"],
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
                sourceId=s["source_id"],
                sourceType=s["source_type"],
                title=s["title"],
                analysis=s["analysis"],
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
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

    prompt = (
        "Sen proje bazli calisan bir sesli asistanin beyni olarak yanit veriyorsun. "
        "Asagidaki proje bilgisini birincil kaynak kabul et. "
        "Kisa, dogru ve uygulanabilir cevap ver. Bilgi yoksa bunu acikca soyle.\n\n"
        f"Proje bilgi ozeti:\n{context_summary}\n\n"
        f"Kullanicinin anlik sorusu (transkript):\n{payload.transcript}"
    )

    def event_stream():
        try:
            with client.responses.stream(
                model=model,
                input=prompt,
                temperature=0.2,
                max_output_tokens=500,
            ) as stream:
                for event in stream:
                    if getattr(event, "type", None) == "response.output_text.delta":
                        delta = getattr(event, "delta", "")
                        if delta:
                            yield f"data: {json.dumps({'delta': delta}, ensure_ascii=False)}\n\n"

                yield "data: {\"done\": true}\n\n"
        except Exception as exc:
            payload = {"error": f"Model request failed: {exc}"}
            yield f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
