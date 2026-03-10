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
                "created_at": self._now(),
            }
            db["users"].append(user)
            db["projects"][user["user_id"]] = []
            self._write(db)
            return UserRecord(**user)

    def authenticate_user(self, email: str, password: str) -> UserRecord | None:
        with self._lock:
            db = self._read()
            normalized = email.strip().lower()
            for user in db["users"]:
                if user["email"] == normalized and self._verify_password(password, user["password_hash"]):
                    return UserRecord(**user)
            return None

    def create_session(self, user_id: str) -> str:
        with self._lock:
            db = self._read()
            token = secrets.token_urlsafe(48)
            db["sessions"][token] = {"user_id": user_id, "created_at": self._now()}
            self._write(db)
            return token

    def get_user_by_token(self, token: str) -> UserRecord | None:
        with self._lock:
            db = self._read()
            session = db["sessions"].get(token)
            if not session:
                return None
            for user in db["users"]:
                if user["user_id"] == session["user_id"]:
                    return UserRecord(**user)
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
                project.setdefault("sources", []).append(source)
                project["updated_at"] = now
                self._write(db)
                return source

        raise ValueError("Project not found")

    def project_context(self, user_id: str, project_id: str) -> tuple[str, list[dict[str, Any]], str]:
        project = self.get_project(user_id, project_id)
        if not project:
            raise ValueError("Project not found")

        sources = project.get("sources", [])
        if not sources:
            return (
                "Bu projeye henuz veri eklenmedi. Sorulari yalnizca canli konusma metnine gore cevapla.",
                [],
                project["updated_at"],
            )

        pieces = []
        for src in sources[-20:]:
            pieces.append(f"Kaynak: {src['title']} ({src['source_type']})\nAnaliz: {src['analysis']}")
        summary = "\n\n".join(pieces)
        return summary[:12000], sources[-20:], project["updated_at"]
