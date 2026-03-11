from __future__ import annotations

import json
import secrets
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import scrypt
from pathlib import Path
from typing import Any
from uuid import uuid4


@dataclass
class UserRecord:
    user_id: str
    name: str
    email: str
    password_hash: str
    created_at: str
    apple_id: str = ""


class JsonStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write({"users": [], "sessions": {}, "projects": {}})

    def _read(self) -> dict[str, Any]:
        db = json.loads(self.path.read_text(encoding="utf-8"))
        db.setdefault("users", [])
        db.setdefault("sessions", {})
        db.setdefault("projects", {})
        return db

    def _write(self, payload: dict[str, Any]) -> None:
        self.path.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _hash_password(password: str, salt_hex: str | None = None) -> str:
        salt = bytes.fromhex(salt_hex) if salt_hex else secrets.token_bytes(16)
        key = scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
        return f"{salt.hex()}:{key.hex()}"

    @staticmethod
    def _verify_password(password: str, combined: str) -> bool:
        salt_hex, expected_hex = combined.split(":", 1)
        candidate = JsonStore._hash_password(password, salt_hex)
        return secrets.compare_digest(candidate.split(":", 1)[1], expected_hex)

    @staticmethod
    def _to_record(user: dict[str, Any]) -> "UserRecord":
        return UserRecord(
            user_id=user["user_id"],
            name=user["name"],
            email=user["email"],
            password_hash=user.get("password_hash", ""),
            created_at=user["created_at"],
            apple_id=user.get("apple_id", ""),
        )

    def register_user(self, name: str, email: str, password: str) -> UserRecord:
        with self._lock:
            db = self._read()
            normalized = email.strip().lower()
            if any(u["email"] == normalized for u in db["users"]):
                raise ValueError("Email already registered")

            user = {
                "user_id": str(uuid4()),
                "name": name.strip(),
                "email": normalized,
                "password_hash": self._hash_password(password),
                "apple_id": "",
                "created_at": self._now(),
            }
            db["users"].append(user)
            db["projects"][user["user_id"]] = []
            self._write(db)
            return self._to_record(user)

    def authenticate_user(self, email: str, password: str) -> UserRecord | None:
        with self._lock:
            db = self._read()
            normalized = email.strip().lower()
            for user in db["users"]:
                ph = user.get("password_hash", "")
                if user["email"] == normalized and ph and self._verify_password(password, ph):
                    return self._to_record(user)
            return None

    def find_or_create_apple_user(self, apple_id: str, email: str, name: str) -> UserRecord:
        with self._lock:
            db = self._read()
            normalized_email = email.strip().lower() if email else ""

            # 1. Look up by apple_id
            for user in db["users"]:
                if user.get("apple_id") == apple_id:
                    # Update name/email if we got fresh data from Apple
                    if name and user["name"] != name:
                        user["name"] = name
                    if normalized_email and user["email"] != normalized_email:
                        user["email"] = normalized_email
                    self._write(db)
                    return self._to_record(user)

            # 2. Link existing email account
            if normalized_email:
                for user in db["users"]:
                    if user["email"] == normalized_email:
                        user["apple_id"] = apple_id
                        self._write(db)
                        return self._to_record(user)

            # 3. Create new Apple user
            user = {
                "user_id": str(uuid4()),
                "name": name or "Apple User",
                "email": normalized_email or f"apple_{apple_id[:8]}@privaterelay.appleid.com",
                "password_hash": "",
                "apple_id": apple_id,
                "created_at": self._now(),
            }
            db["users"].append(user)
            db["projects"][user["user_id"]] = []
            self._write(db)
            return self._to_record(user)

    def create_session(self, user_id: str) -> str:
        with self._lock:
            db = self._read()
            token = secrets.token_urlsafe(48)
            db["sessions"][token] = {"user_id": user_id, "created_at": self._now()}
            self._write(db)
            return token

    def delete_session(self, token: str) -> None:
        with self._lock:
            db = self._read()
            db["sessions"].pop(token, None)
            self._write(db)

    def get_user_by_token(self, token: str) -> UserRecord | None:
        with self._lock:
            db = self._read()
            session = db["sessions"].get(token)
            if not session:
                return None
            for user in db["users"]:
                if user["user_id"] == session["user_id"]:
                    return self._to_record(user)
            return None

    def list_projects(self, user_id: str) -> list[dict[str, Any]]:
        with self._lock:
            db = self._read()
            projects = db["projects"].get(user_id, [])
            return sorted(projects, key=lambda x: x["updated_at"], reverse=True)

    def create_project(self, user_id: str, name: str) -> dict[str, Any]:
        with self._lock:
            db = self._read()
            projects = db["projects"].setdefault(user_id, [])
            now = self._now()
            project = {
                "project_id": str(uuid4()),
                "name": name.strip(),
                "created_at": now,
                "updated_at": now,
                "sources": [],
                "documents": [],
                "transcripts": [],
                "audio_assets": [],
                "summaries": [],
            }
            projects.append(project)
            self._write(db)
            return project

    def get_project(self, user_id: str, project_id: str) -> dict[str, Any] | None:
        with self._lock:
            db = self._read()
            for project in db["projects"].get(user_id, []):
                if project["project_id"] == project_id:
                    return project
            return None

    @staticmethod
    def _split_sources(project: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        """
        Return (docs, transcripts) from typed subcollections.
        Falls back to migrating old flat `sources` list for backward compatibility.
        """
        docs = project.get("documents", [])
        transcripts = project.get("transcripts", [])

        # Backward migration: classify any items still in the flat sources list
        legacy_sources = project.get("sources", [])
        if legacy_sources:
            for src in legacy_sources:
                src_type = src.get("source_type", "text")
                if src_type == "transcript":
                    transcripts = transcripts + [src]
                else:
                    docs = docs + [src]

        return docs, transcripts

    def add_project_source(
        self,
        user_id: str,
        project_id: str,
        source_type: str,
        title: str,
        raw_text: str,
        analysis: str,
    ) -> dict[str, Any]:
        with self._lock:
            db = self._read()
            projects = db["projects"].get(user_id, [])
            for project in projects:
                if project["project_id"] != project_id:
                    continue

                now = self._now()
                source = {
                    "source_id": str(uuid4()),
                    "source_type": source_type,
                    "title": title.strip(),
                    "raw_text": raw_text[:20000],
                    "analysis": analysis[:5000],
                    "created_at": now,
                }

                # Route to typed subcollection
                if source_type == "transcript":
                    project.setdefault("transcripts", []).append(source)
                else:
                    # "text" or "file" → documents
                    project.setdefault("documents", []).append(source)

                # Keep legacy sources list in sync for backward compatibility
                project.setdefault("sources", []).append(source)

                project["updated_at"] = now
                self._write(db)
                return source

        raise ValueError("Project not found")

    def project_context(self, user_id: str, project_id: str) -> tuple[str, list[dict[str, Any]], str]:
        project = self.get_project(user_id, project_id)
        if not project:
            raise ValueError("Project not found")

        docs, transcripts = self._split_sources(project)
        all_sources = docs + transcripts

        if not all_sources:
            return (
                "No data has been added to this project yet. Respond based on the live transcript only.",
                [],
                project["updated_at"],
            )

        pieces = []
        for src in all_sources[-20:]:
            pieces.append(f"Source: {src['title']} ({src['source_type']})\nAnalysis: {src['analysis']}")
        summary = "\n\n".join(pieces)
        return summary[:12000], all_sources[-20:], project["updated_at"]

    def project_context_layered(self, user_id: str, project_id: str) -> dict[str, Any]:
        """
        Return a typed, layered context snapshot for AI prompt assembly.

        Returns a dict with keys:
          project_name, document_context, transcript_history,
          documents, transcripts, all_sources, last_updated
        """
        project = self.get_project(user_id, project_id)
        if not project:
            raise ValueError("Project not found")

        docs, transcripts = self._split_sources(project)

        # Layer 2: document analyses joined
        doc_pieces = [
            f"Document: {d['title']}\n{d['analysis']}"
            for d in docs[-20:]
        ]
        document_context = "\n\n".join(doc_pieces)

        # Layer 3: transcript analyses joined
        transcript_pieces = [
            f"Transcript: {t['title']}\n{t['analysis']}"
            for t in transcripts[-20:]
        ]
        transcript_history = "\n\n".join(transcript_pieces)

        all_sources = docs + transcripts

        return {
            "project_name": project["name"],
            "document_context": document_context,
            "transcript_history": transcript_history,
            "documents": docs,
            "transcripts": transcripts,
            "all_sources": all_sources,
            "last_updated": project["updated_at"],
        }

    def save_audio_asset(
        self,
        user_id: str,
        project_id: str,
        title: str,
        mime_type: str,
    ) -> dict[str, Any]:
        with self._lock:
            db = self._read()
            projects = db["projects"].get(user_id, [])
            for project in projects:
                if project["project_id"] != project_id:
                    continue

                now = self._now()
                asset = {
                    "asset_id": str(uuid4()),
                    "title": title.strip(),
                    "mime_type": mime_type.strip(),
                    "created_at": now,
                }
                project.setdefault("audio_assets", []).append(asset)
                project["updated_at"] = now
                self._write(db)
                return asset

        raise ValueError("Project not found")

    def save_project_summary(
        self,
        user_id: str,
        project_id: str,
        style: str,
        content: str,
    ) -> dict[str, Any]:
        with self._lock:
            db = self._read()
            projects = db["projects"].get(user_id, [])
            for project in projects:
                if project["project_id"] != project_id:
                    continue

                now = self._now()
                summary = {
                    "summary_id": str(uuid4()),
                    "style": style.strip(),
                    "content": content,
                    "generated_at": now,
                }
                project.setdefault("summaries", []).append(summary)
                project["updated_at"] = now
                self._write(db)
                return summary

        raise ValueError("Project not found")

    def list_project_summaries(self, user_id: str, project_id: str) -> list[dict[str, Any]]:
        project = self.get_project(user_id, project_id)
        if not project:
            raise ValueError("Project not found")
        return project.get("summaries", [])
