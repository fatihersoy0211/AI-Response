from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)


class AuthResponse(BaseModel):
    userId: str
    accessToken: str
    refreshToken: str | None = None


class ProjectCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class ProjectResponse(BaseModel):
    projectId: str
    name: str
    createdAtISO8601: str
    updatedAtISO8601: str


class TextSourceUploadRequest(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    text: str = Field(min_length=1, max_length=100_000)


class TranscriptSaveRequest(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    transcript: str = Field(min_length=1, max_length=100_000)


class SourceResponse(BaseModel):
    sourceId: str
    sourceType: str
    title: str
    analysis: str
    createdAtISO8601: str


class ProjectContextResponse(BaseModel):
    summary: str
    sources: list[SourceResponse]
    lastUpdatedISO8601: str


class AIRespondRequest(BaseModel):
    projectId: str = Field(min_length=1)
    transcript: str = Field(min_length=1, max_length=10_000)
    # Accumulated transcript from the entire session (all previous rounds)
    sessionTranscript: str | None = Field(default=None, max_length=30_000)
