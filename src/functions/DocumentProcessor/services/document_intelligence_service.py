import logging
import os
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest
from azure.core.credentials import AzureKeyCredential
from models.document import ExtractedField, DocumentType

logger = logging.getLogger(__name__)


class DocumentIntelligenceService:
    def __init__(self):
        endpoint = os.environ["AI_SERVICES_ENDPOINT"]
        api_key  = os.environ["AI_SERVICES_KEY"]
        self._client = DocumentIntelligenceClient(endpoint, AzureKeyCredential(api_key))

    def analyze(self, blob_url: str, blob_name: str = "") -> dict:
        logger.info("Analyzing document: %s", blob_url)

        # Plain text files are not supported by Document Intelligence — read directly
        if blob_name.lower().endswith(".txt"):
            import urllib.request
            with urllib.request.urlopen(blob_url) as r:
                full_text = r.read().decode("utf-8", errors="ignore").lower()
            extracted_fields = []
            doc_type  = DocumentType.UNKNOWN
            page_count = 1
        else:
            poller = self._client.begin_analyze_document(
                "prebuilt-read",
                AnalyzeDocumentRequest(url_source=blob_url)
            )
            result = poller.result()

            extracted_fields = []
            doc_type   = DocumentType.UNKNOWN
            page_count = len(result.pages) if result.pages else 0

            full_text = " ".join(
                [line.content for page in (result.pages or []) for line in (page.lines or [])]
            ).lower()

        if any(w in full_text for w in ["invoice", "bill to", "amount due"]):
            doc_type = DocumentType.INVOICE
        elif any(w in full_text for w in ["receipt", "total paid", "thank you"]):
            doc_type = DocumentType.RECEIPT
        elif any(w in full_text for w in ["agreement", "contract", "terms"]):
            doc_type = DocumentType.CONTRACT

        logger.info("Extracted %d fields, type: %s, pages: %d",
                    len(extracted_fields), doc_type, page_count)

        return {
            "extracted_fields": extracted_fields,
            "document_type": doc_type,
            "page_count": page_count,
            "full_text": full_text[:5000]  # Limit for OpenAI summarization
        }
