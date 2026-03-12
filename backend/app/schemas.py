from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)


class VerificationRequiredResponse(BaseModel):
    email: str
    message: str = "verification_required"


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class VerifyResetRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)
    newPassword: str = Field(min_length=8, max_length=256)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)


class AuthResponse(BaseModel):
    userId: str
    name: str
    email: str
    accessToken: str
    refreshToken: str | None = None


class UserProfileResponse(BaseModel):
    userId: str
    name: str
    email: str
    createdAtISO8601: str


class ProjectCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class ProjectNotesUpdateRequest(BaseModel):
    manualText: str = Field(default="", max_length=50_000)


class ProjectResponse(BaseModel):
    projectId: str
    name: str
    manualText: str = ""
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


class AppleAuthRequest(BaseModel):
    identityToken: str          # JWT from Apple
    userIdentifier: str         # Apple's stable user ID (sub)
    name: str | None = None     # Only provided on first sign-in
    email: str | None = None    # Only provided on first sign-in
    nonce: str | None = None    # Raw nonce; backend verifies sha256(nonce) == JWT nonce claim


class ChatMessageSchema(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(min_length=1, max_length=5_000)


class AIChatRequest(BaseModel):
    projectId: str = Field(min_length=1)
    messages: list[ChatMessageSchema] = Field(min_length=1, max_length=30)
    userName: str | None = Field(default=None, max_length=120)


class AIRespondRequest(BaseModel):
    projectId: str = Field(min_length=1)
    liveTranscript: str = Field(default="", max_length=10_000)
    transcriptHistory: str | None = Field(default=None, max_length=30_000)
    userName: str | None = Field(default=None, max_length=120)


# ---------------------------------------------------------------------------
# New typed response models
# ---------------------------------------------------------------------------

class AudioAssetResponse(BaseModel):
    assetId: str
    title: str
    mimeType: str
    createdAtISO8601: str


class SaveAudioAssetRequest(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    mimeType: str = Field(min_length=1, max_length=100)


class SummaryResponse(BaseModel):
    summaryId: str
    style: str
    content: str
    generatedAtISO8601: str


class SaveSummaryRequest(BaseModel):
    style: str = Field(min_length=1, max_length=60)
    content: str = Field(min_length=1, max_length=50_000)


class ProjectContextSnapshotResponse(BaseModel):
    projectId: str
    projectName: str
    manualText: str = ""
    documentContext: str
    transcriptHistory: str
    chatHistory: str
    mergedText: str
    documents: list[SourceResponse]
    transcripts: list[SourceResponse]
    lastUpdatedISO8601: str


# ---------------------------------------------------------------------------
# Audio asset import
# ---------------------------------------------------------------------------

class ImportAudioAssetRequest(BaseModel):
    fileName: str = Field(min_length=1, max_length=255)
    mimeType: str = Field(min_length=1, max_length=100)
    sourceType: str = Field(default="uploadedAudio", max_length=60)
    durationSeconds: float | None = None
    transcript: str | None = Field(default=None, max_length=100_000)


class ImportAudioAssetResponse(BaseModel):
    assetId: str
    projectId: str
    title: str
    sourceType: str
    mimeType: str
    durationSeconds: float | None
    transcriptionStatus: str
    createdAtISO8601: str


# ---------------------------------------------------------------------------
# Chat turn persistence
# ---------------------------------------------------------------------------

class SaveChatTurnRequest(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(min_length=1, max_length=10_000)


class ChatTurnResponse(BaseModel):
    turnId: str
    projectId: str
    role: str
    content: str
    createdAtISO8601: str
    turnIndex: int


# ---------------------------------------------------------------------------
# Project listing responses
# ---------------------------------------------------------------------------

class ProjectDocumentResponse(BaseModel):
    sourceId: str
    projectId: str
    fileName: str
    fileType: str
    extractedText: str
    extractionStatus: str
    createdAtISO8601: str
    updatedAtISO8601: str


class ProjectTranscriptResponse(BaseModel):
    sourceId: str
    projectId: str
    title: str
    analysis: str
    sourceType: str
    createdAtISO8601: str
