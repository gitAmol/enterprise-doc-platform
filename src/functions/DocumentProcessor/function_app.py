import json
import logging
import os
import uuid
from datetime import datetime, timezone, timedelta
import azure.functions as func
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from models.document import DocumentMetadata, DocumentStatus
from services.cosmos_service import CosmosService
from services.document_intelligence_service import DocumentIntelligenceService
from services.openai_service import OpenAIService
from services.search_service import SearchService

app    = func.FunctionApp()
logger = logging.getLogger(__name__)

# ============================================================================
# FUNCTION 1: Blob Trigger - Fires when document uploaded to storage
# ============================================================================
@app.blob_trigger(
    arg_name="blob",
    path="incoming-documents/{name}",
    connection="BlobStorageConnection"
)
def on_document_uploaded(blob: func.InputStream):
    """Triggered when a document is uploaded to blob storage."""
    logger.info("Document uploaded: %s (%d bytes)", blob.name, blob.length)

    # On Linux, blob.name is just the path within the container: "tenant1/uuid/file.txt"
    blob_path = blob.name
    parts     = blob_path.split("/")
    tenant_id = parts[0] if len(parts) >= 3 else "default-tenant"
    account   = "sthl45ya2j"
    blob_url  = f"https://{account}.blob.core.windows.net/incoming-documents/{blob_path}"
    doc_id    = str(uuid.uuid4())

    doc = DocumentMetadata(
        id=doc_id,
        tenantId=tenant_id,
        fileName=blob_path,
        blobUrl=blob_url
    )

    cosmos = CosmosService()
    cosmos.upsert(doc)

    # Send to processing queue via Service Bus SDK directly
    try:
        sb_conn = os.environ["ServiceBusConnection"]
        with ServiceBusClient.from_connection_string(sb_conn) as sb_client:
            sender = sb_client.get_queue_sender("document-processing")
            msg    = ServiceBusMessage(json.dumps({"documentId": doc_id, "tenantId": tenant_id, "blobUrl": blob_url, "blobPath": blob_path}))
            sender.send_messages(msg)
    except Exception as ex:
        logger.error("Failed to send Service Bus message: %s", ex)

    logger.info("Document %s queued for processing", doc_id)


# ============================================================================
# FUNCTION 2: Service Bus Trigger - AI Processing Pipeline
# ============================================================================
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="document-processing",
    connection="ServiceBusConnection"
)
def process_document(msg: func.ServiceBusMessage):
    """Processes document through AI pipeline: Extract → Summarize → Index."""
    payload   = json.loads(msg.get_body().decode("utf-8"))
    doc_id    = payload["documentId"]
    tenant_id = payload["tenantId"]
    blob_url  = payload["blobUrl"]

    logger.info("Processing document %s", doc_id)

    cosmos = CosmosService()
    cosmos.update_status(doc_id, tenant_id, DocumentStatus.PROCESSING)

    try:
        # Generate SAS URL so Document Intelligence can download the private blob
        blob_path = payload.get("blobPath", blob_url.split("/incoming-documents/", 1)[-1])
        conn_str  = os.environ["AzureWebJobsStorage"]
        bsc       = BlobServiceClient.from_connection_string(conn_str)
        acct      = bsc.account_name
        acct_key  = bsc.credential.account_key
        sas_token = generate_blob_sas(
            account_name=acct,
            container_name="incoming-documents",
            blob_name=blob_path,
            account_key=acct_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.now(timezone.utc) + timedelta(hours=1)
        )
        sas_url = f"https://{acct}.blob.core.windows.net/incoming-documents/{blob_path}?{sas_token}"

        # Step 1: Extract text and fields using Document Intelligence
        doc_intel = DocumentIntelligenceService()
        extraction = doc_intel.analyze(sas_url, blob_path)

        # Step 2: Summarize + embed via Azure OpenAI (falls back gracefully if not configured)
        openai_svc = OpenAIService()
        try:
            summary   = openai_svc.summarize(extraction["full_text"], extraction["document_type"])
            embedding = openai_svc.get_embedding(extraction["full_text"])
            logger.info("OpenAI summary and embedding generated for %s", doc_id)
        except Exception as oai_ex:
            logger.warning("OpenAI unavailable, using fallback: %s", oai_ex)
            summary   = f"Extracted {extraction['page_count']} page(s) of type {extraction['document_type']}."
            embedding = None

        # Step 3: Index in AI Search (with vector if embedding available)
        search_svc = SearchService()
        doc        = cosmos.get(doc_id, tenant_id)
        search_svc.index_document(
            doc_id=doc_id,
            tenant_id=tenant_id,
            doc_type=extraction["document_type"],
            file_name=doc["fileName"],
            summary=summary,
            full_text=extraction["full_text"],
            created_at=doc["createdAt"],
            embedding=embedding
        )

        # Step 4: Update Cosmos DB with results
        doc["status"]          = DocumentStatus.COMPLETED
        doc["summary"]         = summary
        doc["documentType"]    = extraction["document_type"]
        doc["extractedFields"] = [vars(f) for f in extraction["extracted_fields"]]
        doc["pageCount"]       = extraction["page_count"]
        cosmos.upsert(DocumentMetadata(**{k: doc[k] for k in DocumentMetadata.__dataclass_fields__
                                          if k in doc}))

        logger.info("Document %s processed successfully", doc_id)

    except Exception as ex:
        logger.error("Failed to process document %s: %s", doc_id, str(ex))
        cosmos.update_status(doc_id, tenant_id, DocumentStatus.FAILED, str(ex))
        raise  # Re-raise to trigger dead-letter queue


# ============================================================================
# FUNCTION 3: HTTP Trigger - Get Document Status
# ============================================================================
@app.route(route="documents/{documentId}/status", methods=["GET"],
           auth_level=func.AuthLevel.FUNCTION)
def get_document_status(req: func.HttpRequest) -> func.HttpResponse:
    doc_id    = req.route_params.get("documentId")
    tenant_id = req.params.get("tenantId", "default-tenant")

    try:
        cosmos = CosmosService()
        doc    = cosmos.get(doc_id, tenant_id)
        return func.HttpResponse(
            json.dumps({
                "documentId":   doc["id"],
                "status":       doc["status"],
                "documentType": doc.get("documentType"),
                "summary":      doc.get("summary"),
                "pageCount":    doc.get("pageCount"),
                "createdAt":    doc.get("createdAt"),
                "updatedAt":    doc.get("updatedAt")
            }),
            mimetype="application/json",
            status_code=200
        )
    except Exception:
        return func.HttpResponse(
            json.dumps({"error": "Document not found"}),
            mimetype="application/json",
            status_code=404
        )


# ============================================================================
# FUNCTION 4: HTTP Trigger - Search Documents
# ============================================================================
@app.route(route="documents/search", methods=["POST"],
           auth_level=func.AuthLevel.FUNCTION)
def search_documents(req: func.HttpRequest) -> func.HttpResponse:
    body      = req.get_json()
    query     = body.get("query", "")
    tenant_id = body.get("tenantId", "default-tenant")

    if not query:
        return func.HttpResponse(
            json.dumps({"error": "query is required"}),
            mimetype="application/json",
            status_code=400
        )

    try:
        # Vector search if OpenAI is configured, else keyword-only
        query_vector = None
        try:
            openai_svc   = OpenAIService()
            query_vector = openai_svc.get_embedding(query)
            logger.info("Query embedding generated for vector search")
        except Exception as oai_ex:
            logger.warning("OpenAI unavailable, falling back to keyword search: %s", oai_ex)

        search_svc = SearchService()
        results    = search_svc.search(query, tenant_id, query_vector=query_vector)

        return func.HttpResponse(
            json.dumps({"results": results, "count": len(results)}),
            mimetype="application/json",
            status_code=200
        )
    except Exception as ex:
        logger.error("Search failed: %s", str(ex))
        return func.HttpResponse(
            json.dumps({"error": "Search failed"}),
            mimetype="application/json",
            status_code=500
        )


# ============================================================================
# FUNCTION 5: HTTP Trigger - Upload Document
# ============================================================================
@app.route(route="documents/upload", methods=["POST"],
           auth_level=func.AuthLevel.FUNCTION)
def upload_document(req: func.HttpRequest) -> func.HttpResponse:
    import cgi, io

    # Try req.files first; fall back to manual multipart parse
    if req.files.get("file"):
        file_obj  = req.files["file"]
        file_data = file_obj.stream.read()
        filename  = file_obj.filename
        tenant_id = req.form.get("tenantId") or req.form.get("tenant_id", "default-tenant")
    else:
        content_type = req.headers.get("Content-Type", "")
        environ = {"REQUEST_METHOD": "POST", "CONTENT_TYPE": content_type,
                   "CONTENT_LENGTH": str(len(req.get_body()))}
        form = cgi.FieldStorage(fp=io.BytesIO(req.get_body()), environ=environ, keep_blank_values=True)
        if "file" not in form:
            return func.HttpResponse(
                json.dumps({"error": "No file provided"}),
                mimetype="application/json", status_code=400
            )
        file_item = form["file"]
        file_data = file_item.file.read()
        filename  = file_item.filename or "upload"
        tenant_id = form.getvalue("tenantId") or form.getvalue("tenant_id") or "default-tenant"

    blob_name = f"{tenant_id}/{uuid.uuid4()}/{filename}"

    try:
        conn_str = os.environ.get("AzureWebJobsStorage")
        blob_service = BlobServiceClient.from_connection_string(conn_str)
        container = blob_service.get_container_client("incoming-documents")
        container.upload_blob(name=blob_name, data=file_data, overwrite=True)

        return func.HttpResponse(
            json.dumps({"message": "Document uploaded", "blobName": blob_name}),
            mimetype="application/json",
            status_code=202
        )
    except Exception as ex:
        logger.error("Upload failed: %s", str(ex))
        return func.HttpResponse(
            json.dumps({"error": "Upload failed"}),
            mimetype="application/json",
            status_code=500
        )
