from __future__ import annotations

import io
from pathlib import Path

from docx import Document
from pypdf import PdfReader


SUPPORTED_EXTENSIONS = {".pdf", ".docx"}


def extract_text_from_file(filename: str, data: bytes) -> str:
    suffix = Path(filename).suffix.lower()

    if suffix not in SUPPORTED_EXTENSIONS:
        raise ValueError("Unsupported file type. Only .pdf and .docx are supported.")

    if suffix == ".pdf":
        reader = PdfReader(io.BytesIO(data))
        text_parts = [(page.extract_text() or "") for page in reader.pages]
        return "\n".join(text_parts).strip()

    doc = Document(io.BytesIO(data))
    text_parts = [p.text for p in doc.paragraphs]
    return "\n".join(text_parts).strip()
