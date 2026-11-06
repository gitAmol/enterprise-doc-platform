from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


class DocumentStatus(str, Enum):
    UPLOADED   = "uploaded"
    PROCESSING = "processing"
    COMPLETED  = "completed"
    FAILED     = "failed"


class DocumentType(str, Enum):
    INVOICE    = "invoice"
    RECEIPT    = "receipt"
    CONTRACT   = "contract"
    REPORT     = "report"
    UNKNOWN    = "unknown"


@dataclass
class ExtractedField:
    name: str
    value: str
    confidence: float


@dataclass
class DocumentMetadata:
    id: str
    tenantId: str
    fileName: str
    blobUrl: str
    status: DocumentStatus         = DocumentStatus.UPLOADED
    documentType: DocumentType     = DocumentType.UNKNOWN
    extractedFields: list          = field(default_factory=list)
    summary: str                   = ""
    pageCount: int                 = 0
    language: str                  = "en"
    errorMessage: Optional[str]    = None
    createdAt: str                 = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updatedAt: str                 = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self) -> dict:
        return asdict(self)

    def update_status(self, status: DocumentStatus, error: str = None):
        self.status = status
        self.errorMessage = error
        self.updatedAt = datetime.now(timezone.utc).isoformat()
