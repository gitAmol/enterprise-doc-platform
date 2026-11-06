# Enterprise AI Document Processing Platform — Complete Beginner's Tutorial

## Table of Contents
1. [What Are We Building and Why?](#1-what-are-we-building-and-why)
2. [Cloud Architecture Fundamentals](#2-cloud-architecture-fundamentals)
3. [Azure Services Explained](#3-azure-services-explained)
4. [Architecture Deep Dive](#4-architecture-deep-dive)
5. [Prerequisites and Setup](#5-prerequisites-and-setup)
6. [Project Structure](#6-project-structure)
7. [Infrastructure as Code with Bicep](#7-infrastructure-as-code-with-bicep)
8. [Application Code Walkthrough](#8-application-code-walkthrough)
9. [Deployment Step by Step](#9-deployment-step-by-step)
10. [Testing the Platform](#10-testing-the-platform)
11. [Troubleshooting Guide](#11-troubleshooting-guide)
12. [Key Lessons Learned](#12-key-lessons-learned)
13. [Next Steps](#13-next-steps)

---

## 1. What Are We Building and Why?

### The Business Problem

Imagine a large company — a law firm, a bank, or a hospital. Every day they receive hundreds of documents: invoices, contracts, receipts, medical forms. Today, employees manually open each document, read it, extract key information, and type it into a system. This is:

- **Slow** — a person can process maybe 50 documents per day
- **Error-prone** — humans make mistakes when copying data
- **Expensive** — you need many people to handle volume
- **Not searchable** — documents sit in folders, hard to find later

### The Solution: An AI-Powered Document Platform

We are building a system that:

1. **Accepts** any document upload (PDF, image, Word, text)
2. **Automatically extracts** text and key fields using AI (no human needed)
3. **Understands** what type of document it is (invoice, contract, receipt)
4. **Summarizes** the document in plain English using GPT
5. **Makes it searchable** — you can ask "find all invoices over $1000 from January"
6. **Stores everything** in a database with full audit trail
7. **Scales automatically** — handles 10 documents or 10,000 documents the same way

### Why Azure?

Azure provides all the AI services we need as managed APIs — we don't need to train our own AI models. We just call their APIs and get results. This is called **AI as a Service**.

### What You Will Learn

By the end of this tutorial you will understand:
- How event-driven cloud architectures work
- How to use Azure AI services (Document Intelligence, OpenAI, AI Search)
- How serverless computing works with Azure Functions
- How to store data in Cosmos DB and Blob Storage
- How to use Infrastructure as Code (Bicep) to create cloud resources
- How to debug and troubleshoot real cloud applications
- Common pitfalls and how to avoid them

---

## 2. Cloud Architecture Fundamentals

Before writing any code, you need to understand the architectural patterns we use. These are industry-standard patterns used by enterprise architects worldwide.

### 2.1 Monolithic vs Microservices

**Monolithic architecture** (old way):
```
┌─────────────────────────────────────┐
│           ONE BIG APPLICATION       │
│  Upload + Process + Store + Search  │
│  All in one process, one server     │
└─────────────────────────────────────┘
```
Problem: If the "process" part crashes, everything crashes. If you need more capacity for uploads, you have to scale the entire application.

**Microservices architecture** (what we build):
```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│  Upload  │   │ Process  │   │  Store   │   │  Search  │
│ Service  │   │ Service  │   │ Service  │   │ Service  │
└──────────┘   └──────────┘   └──────────┘   └──────────┘
```
Each service does one thing. They communicate via messages. If one crashes, others keep running.

### 2.2 Event-Driven Architecture

This is the most important concept in our platform. Instead of services calling each other directly, they communicate through **events** and **messages**.

**Direct call (tight coupling — bad for scale):**
```
Upload Service ──calls──▶ Process Service ──calls──▶ Store Service
```
Problem: If Process Service is slow, Upload Service waits. If Process Service is down, Upload fails.

**Event-driven (loose coupling — what we use):**
```
Upload Service ──puts message──▶ [Queue] ──picks up──▶ Process Service
```
Benefits:
- Upload Service doesn't wait — it just drops a message and returns immediately
- If Process Service is down, messages wait in the queue safely
- You can add more Process Service instances to handle load
- Services don't need to know about each other

In our platform:
- A document upload triggers a **blob event**
- That event creates a **Service Bus message**
- The message triggers the **processing function**
- Processing results are stored in **Cosmos DB** and **AI Search**

### 2.3 Serverless Computing

Traditional servers run 24/7 even when idle — you pay for them constantly. **Serverless** means:

- Your code runs only when triggered (upload, message, HTTP request)
- Azure automatically starts your code, runs it, stops it
- You pay only for the milliseconds your code actually runs
- Azure handles scaling — 1 request or 1 million requests, same code

**Azure Functions** is Azure's serverless platform. Each function is triggered by something:

| Trigger Type | When it fires |
|---|---|
| HTTP Trigger | When someone calls a URL |
| Blob Trigger | When a file is uploaded to storage |
| Service Bus Trigger | When a message arrives in a queue |
| Timer Trigger | On a schedule (like a cron job) |

### 2.4 The Queue Pattern (Async Processing)

Documents take time to process (OCR, AI analysis). We never make the user wait. Instead:

```
User uploads doc
      │
      ▼
Function returns "202 Accepted" immediately  ◀── User gets response in <1 second
      │
      ▼
Message placed in Service Bus queue
      │
      ▼ (happens in background, takes 10-30 seconds)
Processing function picks up message
      │
      ▼
AI analysis, summarization, indexing
      │
      ▼
Cosmos DB updated to "completed"
      │
      ▼
User polls status endpoint to check when done
```

This pattern is called **asynchronous processing**. The user experience is: "Your document is being processed. Check back in a moment."

### 2.5 Multi-Tenancy

Our platform is designed for multiple companies (tenants) to use simultaneously. Each tenant's data is isolated from others. We achieve this by:

- Storing all documents under a `tenantId` prefix: `tenant1/uuid/file.pdf`
- Using `tenantId` as the partition key in Cosmos DB
- Filtering all search queries by `tenantId`

This is how SaaS (Software as a Service) products work — one platform, many customers, data isolation.

---

## 3. Azure Services Explained

Here is every Azure service we use, explained from first principles.

### 3.1 Azure Blob Storage — The File System

**What it is**: A massively scalable file storage service. Think of it as a hard drive in the cloud that can hold petabytes of data.

**Key concepts**:
- **Storage Account**: The top-level container (like a hard drive)
- **Container**: A folder inside the storage account
- **Blob**: An individual file

**In our platform**: We store uploaded documents in a container called `incoming-documents`. Files are organized as `{tenantId}/{documentId}/{filename}`.

**Why not just use a regular file server?**
- Blob Storage scales to unlimited size automatically
- It's globally redundant (your files are copied to multiple data centers)
- It integrates natively with Azure Functions blob triggers
- It's extremely cheap (~$0.02 per GB per month)

**Access control**: Blobs can be private (default) or public. We keep them private and generate **SAS (Shared Access Signature) URLs** when external services (like Document Intelligence) need temporary access.

```
Private blob URL:  https://sthl45ya2j.blob.core.windows.net/incoming-documents/tenant1/uuid/file.pdf
                   ← This returns 403 Forbidden to anyone

SAS URL:           https://sthl45ya2j.blob.core.windows.net/incoming-documents/tenant1/uuid/file.pdf?sv=2021-06-08&se=2024-01-15T10%3A00%3A00Z&sr=b&sp=r&sig=abc123...
                   ← This works for 1 hour, then expires automatically
```

### 3.2 Azure Service Bus — The Message Queue

**What it is**: A fully managed enterprise message broker. Think of it as a post office — senders drop off messages, receivers pick them up, the post office guarantees delivery.

**Key concepts**:
- **Namespace**: The Service Bus account (like a post office building)
- **Queue**: A named channel for messages (like a mailbox)
- **Message**: A JSON payload sent between services
- **Dead-letter queue**: A special queue where failed messages go after too many retries

**Why not just call the processing function directly?**
- If processing fails, the message stays in the queue and retries automatically
- You can process messages at your own pace (rate limiting)
- Messages survive if your processing service crashes
- You can have multiple consumers processing in parallel

**Message lifecycle in our platform**:
```
1. on_document_uploaded sends message to "document-processing" queue
2. process_document picks up the message (locks it for 5 minutes)
3. If processing succeeds → message is deleted from queue
4. If processing fails → message is unlocked, retried up to 5 times
5. After 5 failures → message moves to dead-letter queue
```

**Dead-letter queue**: This is your safety net. Any message that couldn't be processed after N retries lands here. You can inspect it to understand what went wrong. In our debugging, we used this extensively.

### 3.3 Azure Cosmos DB — The NoSQL Database

**What it is**: A globally distributed, multi-model NoSQL database. Unlike SQL databases with fixed schemas, Cosmos DB stores JSON documents — each document can have different fields.

**Key concepts**:
- **Database**: A logical grouping (we use `DocumentPlatformDB`)
- **Container**: A collection of JSON documents (we use `Documents`)
- **Partition Key**: A field used to distribute data across servers (we use `tenantId`)
- **Serverless mode**: Pay per request unit (RU), not per hour

**Why Cosmos DB instead of SQL?**
- Our documents have varying fields (invoices have different fields than contracts)
- JSON storage matches our Python dataclasses naturally
- Serverless mode is very cheap for development
- Built-in support for partition-based multi-tenancy

**Partition key importance**: When you query Cosmos DB, always include the partition key. Without it, Cosmos DB scans all partitions (expensive and slow). With it, it goes directly to the right partition (fast and cheap).

```python
# Good - includes partition key (tenantId)
container.read_item(item=doc_id, partition_key="tenant1")

# Bad - cross-partition query (slow, expensive)
container.query_items("SELECT * FROM c WHERE c.id = 'abc'")
```

**Document structure** in our platform:
```json
{
  "id": "d4bd3ae1-3e15-46c6-a605-65c054bf487d",
  "tenantId": "tenant1",
  "fileName": "tenant1/d4bd3ae1.../invoice.pdf",
  "blobUrl": "https://sthl45ya2j.blob.core.windows.net/...",
  "status": "completed",
  "documentType": "invoice",
  "summary": "Invoice #12345 from Acme Corp for $1,500...",
  "pageCount": 1,
  "createdAt": "2026-11-05T10:09:14Z",
  "updatedAt": "2026-11-05T10:17:05Z"
}
```

### 3.4 Azure AI Document Intelligence — The OCR Engine

**What it is**: An AI service that reads documents and extracts structured information. It uses computer vision and machine learning trained on millions of documents.

**What it can do**:
- Extract all text from PDFs, images, Word documents
- Identify tables and their structure
- Extract key-value pairs (e.g., "Invoice Number: 12345")
- Detect document layout (headers, paragraphs, columns)

**Models available**:
| Model | What it does | Supported formats |
|---|---|---|
| `prebuilt-read` | Extracts text only | PDF, images, Office, **plain text** |
| `prebuilt-document` | Text + key-value pairs + tables | PDF, images, Office (NOT plain text) |
| `prebuilt-invoice` | Invoice-specific fields (vendor, amount, date) | PDF, images |
| `prebuilt-receipt` | Receipt-specific fields | PDF, images |

**Important lesson learned**: `prebuilt-document` rejects plain `.txt` files with `InvalidContent` error. Use `prebuilt-read` for testing, or use real PDFs with `prebuilt-document`.

**How it works in our code**:
```python
# Document Intelligence needs a URL to download the file
# Since our blobs are private, we generate a SAS URL first
sas_url = generate_sas_url(blob_path)

# Then call the API
poller = client.begin_analyze_document("prebuilt-read", 
    AnalyzeDocumentRequest(url_source=sas_url))
result = poller.result()  # This waits for the async operation to complete

# Extract text from all pages
full_text = " ".join([
    line.content 
    for page in result.pages 
    for line in page.lines
])
```

### 3.5 Azure OpenAI — The Language Model

**What it is**: Access to OpenAI's GPT models (GPT-4o, GPT-3.5) and embedding models hosted on Azure infrastructure. Same models as ChatGPT, but via API, in your own Azure environment.

**Two capabilities we use**:

**1. Chat Completions (Summarization)**:
Send text to GPT, get a summary back. We use this to generate human-readable summaries of extracted document text.

```python
response = client.chat.completions.create(
    model="gpt-4o-1",  # deployment name, not model name
    messages=[
        {"role": "system", "content": "You are a document analyst..."},
        {"role": "user", "content": f"Summarize this invoice:\n{text}"}
    ]
)
summary = response.choices[0].message.content
```

Real output from our platform for a test invoice:
```
Invoice Summary
- Invoice Number: #12345
- Date Issued: January 15, 2024
- Billed To: Acme Corporation
- Item: Cloud Services (January 2024)
- Amount Due: $1,500.00
```

**2. Embeddings (Vector Search)**:
Convert text into a list of 1536 numbers (a vector) that captures the semantic meaning. Similar texts have similar vectors. This enables semantic search — finding documents by meaning, not just keywords.

```python
response = client.embeddings.create(
    model="text-embedding-ada-002",
    input="invoice for cloud services January 2024"
)
vector = response.data[0].embedding  # List of 1536 floats
```

**Important**: Azure OpenAI requires you to **deploy models** before using them. Just having an Azure OpenAI resource is not enough — you must go to Azure AI Foundry portal and create a deployment for each model you want to use.

**Azure AI Foundry vs Classic Azure OpenAI**: If your Cognitive Services resource is of kind `AIServices` (created via Azure AI Foundry), the endpoint format is `https://<name>.services.ai.azure.com` and requires API version `2024-12-01-preview` or later. Classic Azure OpenAI resources use `https://<name>.openai.azure.com` with `2024-02-01`.

### 3.6 Azure AI Search — The Search Engine

**What it is**: A fully managed search service that supports both keyword search and vector (semantic) search. Think of it as Elasticsearch, but managed by Azure.

**Two types of search**:

**Keyword search**: Traditional text matching. Query "invoice" finds documents containing the word "invoice".

**Vector search**: Semantic matching. Query "bill for services" finds documents about invoices even if they don't contain the exact word "invoice", because the vectors are similar.

**Hybrid search**: Combines both for best results.

**Index**: Like a database table optimized for search. We define fields, their types, and which ones are searchable/filterable.

**In our platform**: We index each document with its full text, summary, and embedding vector. Users can search across all their documents with natural language queries.

### 3.7 Azure Functions — The Serverless Compute

**What it is**: A platform for running small pieces of code (functions) in response to events, without managing servers.

**The programming model**:
```python
app = func.FunctionApp()

@app.route(route="documents/upload", methods=["POST"])
def upload_document(req: func.HttpRequest) -> func.HttpResponse:
    # This runs when someone POSTs to /api/documents/upload
    ...

@app.blob_trigger(path="incoming-documents/{name}", connection="BlobStorageConnection")
def on_document_uploaded(blob: func.InputStream):
    # This runs when a file is uploaded to the blob container
    ...

@app.service_bus_queue_trigger(queue_name="document-processing", connection="ServiceBusConnection")
def process_document(msg: func.ServiceBusMessage):
    # This runs when a message arrives in the Service Bus queue
    ...
```

**Consumption Plan vs Premium Plan**:
- **Consumption**: Scales to zero when idle (cheapest, cold start delay of 1-3 seconds)
- **Premium**: Always warm, faster, more expensive

We use Consumption for this tutorial.

**Cold start**: When a function hasn't run recently, Azure needs to start a new instance. This takes 1-5 seconds. For production, use Premium plan or keep-warm pings.

**Blob trigger polling delay**: On Consumption plan, blob triggers don't fire instantly. Azure polls the storage account every few minutes. This can cause up to 10-minute delays. For production, use Event Grid-based blob triggers which fire in seconds.

---

## 4. Architecture Deep Dive

### 4.1 Complete Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPLETE DATA FLOW                               │
│                                                                     │
│  1. CLIENT UPLOADS DOCUMENT                                         │
│     POST /api/documents/upload                                      │
│     (multipart form with file + tenantId)                           │
│              │                                                      │
│              ▼                                                      │
│  2. upload_document FUNCTION (HTTP Trigger)                         │
│     - Validates file exists                                         │
│     - Generates blob path: tenant1/uuid/filename                    │
│     - Uploads to Blob Storage container "incoming-documents"        │
│     - Returns 202 Accepted + blobName                               │
│              │                                                      │
│              ▼                                                      │
│  3. BLOB STORAGE                                                    │
│     File stored at:                                                 │
│     sthl45ya2j/incoming-documents/tenant1/uuid/file.pdf             │
│              │                                                      │
│              ▼ (blob trigger fires — up to 10 min on Consumption)   │
│  4. on_document_uploaded FUNCTION (Blob Trigger)                    │
│     - Parses tenantId from blob path                                │
│     - Creates DocumentMetadata record in Cosmos DB (status=uploaded)│
│     - Sends message to Service Bus queue                            │
│              │                                                      │
│              ▼                                                      │
│  5. SERVICE BUS QUEUE "document-processing"                         │
│     Message: { documentId, tenantId, blobUrl, blobPath }            │
│              │                                                      │
│              ▼ (fires within seconds of message arrival)            │
│  6. process_document FUNCTION (Service Bus Trigger)                 │
│     a. Updates Cosmos DB status → "processing"                      │
│     b. Generates SAS URL for private blob                           │
│     c. Calls Document Intelligence API → extracts text              │
│     d. Calls Azure OpenAI → generates summary                       │
│     e. Calls Azure OpenAI → generates embedding vector              │
│     f. Indexes document in AI Search                                │
│     g. Updates Cosmos DB status → "completed"                       │
│              │                                                      │
│  7. CLIENT POLLS STATUS                                             │
│     GET /api/documents/{id}/status?tenantId=tenant1                 │
│     Returns: { status: "completed", documentType: "invoice", ... }  │
│              │                                                      │
│  8. CLIENT SEARCHES                                                 │
│     POST /api/documents/search                                      │
│     Body: { query: "invoices from January", tenantId: "tenant1" }   │
│     Returns: ranked list of matching documents                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Why This Architecture?

**Separation of concerns**: Each function does exactly one thing. Upload function only uploads. Processing function only processes. This makes each piece easy to test, debug, and replace.

**Resilience**: If Document Intelligence is temporarily down, messages wait in Service Bus. When it comes back, processing resumes automatically. No data is lost.

**Scalability**: If 1000 documents are uploaded simultaneously, Service Bus queues all 1000 messages. Azure Functions automatically scales out to process them in parallel.

**Observability**: Every step updates Cosmos DB status. You can always query "what is the status of document X?" and get a precise answer.

### 4.3 Security Model

**SAS URLs**: Document Intelligence is an external service. It needs to download the blob to analyze it. We can't give it our storage account key. Instead, we generate a time-limited SAS URL that expires in 1 hour. Even if someone intercepts the URL, it becomes useless after expiry.

**Function Keys**: Our HTTP endpoints require an `x-functions-key` header. Without the key, requests return 401. This is basic API key authentication.

**Connection Strings in App Settings**: We never hardcode credentials in code. All secrets are stored in Azure Function App Settings (environment variables), which are encrypted at rest.

---

## 5. Prerequisites and Setup

### 5.1 Required Software

**Python 3.11**
Azure Functions on Linux requires Python 3.11. Install from https://www.python.org/downloads/

```bash
python --version  # Must show 3.11.x
```

**Azure Functions Core Tools v4**
This is the local development tool for Azure Functions. It lets you run functions on your machine before deploying.

```bash
npm install -g azure-functions-core-tools@4 --unsafe-perm true
func --version  # Must show 4.x
```

**Azure CLI**
Command-line tool to manage Azure resources. Download from https://docs.microsoft.com/cli/azure/install-azure-cli

```bash
az --version  # Must show 2.50+
az login      # Opens browser to authenticate
```

**Virtual Environment**
Always use a virtual environment to isolate Python dependencies:

```bash
cd src/functions/DocumentProcessor
python -m venv .venv
.venv\Scripts\activate   # Windows
source .venv/bin/activate # Linux/Mac
pip install -r requirements.txt
```

### 5.2 Azure Subscription Requirements

You need an Azure subscription with:
- Contributor role (to create resources)
- Ability to create Cognitive Services accounts
- At least $50 credit for development

### 5.3 SSL Issues on Corporate Networks

If you are behind a corporate proxy or firewall, Azure CLI may fail with SSL errors:

```bash
az config set core.verify_ssl=false
```

This disables SSL verification. Only use this in development, never in production.

---

## 6. Project Structure

```
enterprise-doc-platform/
├── infra/                          # Infrastructure as Code (Bicep)
│   ├── main.bicep                  # Creates resource group + calls all modules
│   ├── parameters.dev.json         # Environment-specific values
│   └── modules/
│       ├── storage.bicep           # Blob Storage account + containers
│       ├── cosmosdb.bicep          # Cosmos DB account + database + containers
│       ├── servicebus.bicep        # Service Bus namespace + queues
│       ├── ai-services.bicep       # Document Intelligence + AI Search
│       ├── functions.bicep         # Function App + hosting plan
│       ├── keyvault.bicep          # Key Vault for secrets
│       └── monitoring.bicep        # App Insights + Log Analytics
│
├── src/functions/DocumentProcessor/
│   ├── function_app.py             # All 5 Azure Functions defined here
│   ├── host.json                   # Function host configuration
│   ├── local.settings.json         # Local dev environment variables (never commit)
│   ├── requirements.txt            # Python package dependencies
│   ├── models/
│   │   └── document.py             # Data classes: DocumentMetadata, DocumentStatus
│   └── services/
│       ├── cosmos_service.py       # All Cosmos DB operations
│       ├── document_intelligence_service.py  # OCR and text extraction
│       ├── openai_service.py       # Summarization and embeddings
│       └── search_service.py       # Index management and search
│
└── docs/
    └── TUTORIAL.md                 # This file
```

**Why this structure?**

- `infra/` is completely separate from `src/` — infrastructure and application code are independent concerns
- `services/` contains one class per external service — easy to swap implementations or mock in tests
- `models/` contains pure data classes with no Azure dependencies — portable and testable
- `function_app.py` is thin — it only handles HTTP/trigger concerns and delegates to services

---

## 7. Infrastructure as Code with Bicep

### 7.1 What is Infrastructure as Code?

Traditionally, developers created Azure resources by clicking through the Azure Portal. This is:
- Not repeatable (hard to recreate exactly)
- Not version-controlled (no history of changes)
- Error-prone (easy to miss a setting)

**Infrastructure as Code (IaC)** means you describe your infrastructure in code files, and a tool creates the actual resources. Benefits:
- Repeatable: run the same template 100 times, get the same result
- Version-controlled: track changes in Git
- Reviewable: teammates can review infrastructure changes like code changes
- Destroyable: delete everything and recreate from scratch in minutes

**Bicep** is Azure's native IaC language. It compiles to ARM (Azure Resource Manager) templates. It is simpler than raw ARM JSON.

### 7.2 Bicep Concepts

**Resource declaration**:
```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'mystorageaccount'
  location: 'eastus'
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
  }
}
```

- `Microsoft.Storage/storageAccounts` — the resource type
- `@2023-01-01` — the API version (use latest stable)
- Everything inside `properties` is resource-specific configuration

**Parameters** (inputs to your template):
```bicep
param location string = 'eastus'  // Has a default value
param name string                  // Required, no default
```

**Variables** (computed values):
```bicep
var uniqueSuffix = take(uniqueString(subscription().id), 8)
var storageAccountName = 'st${uniqueSuffix}'  // e.g. "sthl45ya2j"
```

**Outputs** (values returned after deployment):
```bicep
output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
```

**Modules** (reusable templates):
```bicep
// In main.bicep, call a module:
module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    name: 'mystorageaccount'
    location: location
  }
}

// Use the module's output:
var blobEndpoint = storage.outputs.blobEndpoint
```

### 7.3 Deploying Infrastructure

```bash
# Deploy at subscription scope (creates resource group + all resources)
az deployment sub create \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.json

# Validate without deploying (dry run)
az deployment sub validate \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.json
```

### 7.4 Getting Connection Strings After Deployment

After Bicep creates your resources, you need their connection strings for your app settings:

```bash
RG="rg-docplatform-dev"

# Storage connection string
az storage account show-connection-string \
  --resource-group $RG \
  --name $(az storage account list -g $RG --query "[0].name" -o tsv) \
  --output tsv

# Service Bus connection string
az servicebus namespace authorization-rule keys list \
  --resource-group $RG \
  --namespace-name $(az servicebus namespace list -g $RG --query "[0].name" -o tsv) \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv

# Cosmos DB key
az cosmosdb keys list \
  --resource-group $RG \
  --name $(az cosmosdb list -g $RG --query "[0].name" -o tsv) \
  --query primaryMasterKey -o tsv

# AI Services key
az cognitiveservices account keys list \
  --resource-group $RG \
  --name $(az cognitiveservices account list -g $RG --query "[0].name" -o tsv) \
  --query key1 -o tsv

# AI Search key
az search admin-key show \
  --resource-group $RG \
  --service-name $(az search service list -g $RG --query "[0].name" -o tsv) \
  --query primaryKey -o tsv
```

---

## 8. Application Code Walkthrough

### 8.1 Data Models (models/document.py)

Data models define the shape of your data. We use Python dataclasses — they are like simple classes that automatically generate `__init__`, `__repr__`, etc.

```python
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

class DocumentStatus(str, Enum):
    UPLOADED   = "uploaded"    # File received, not yet processed
    PROCESSING = "processing"  # AI pipeline running
    COMPLETED  = "completed"   # All steps done successfully
    FAILED     = "failed"      # Something went wrong

class DocumentType(str, Enum):
    INVOICE  = "invoice"
    RECEIPT  = "receipt"
    CONTRACT = "contract"
    UNKNOWN  = "unknown"

@dataclass
class DocumentMetadata:
    id: str
    tenantId: str
    fileName: str
    blobUrl: str
    status: DocumentStatus       = DocumentStatus.UPLOADED
    documentType: DocumentType   = DocumentType.UNKNOWN
    summary: str                 = ""
    pageCount: int               = 0
    extractedFields: list        = field(default_factory=list)
    errorMessage: Optional[str]  = None
    createdAt: str               = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updatedAt: str               = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self) -> dict:
        from dataclasses import asdict
        return asdict(self)
```

**Why `str, Enum`?** Making the enum inherit from `str` means `DocumentStatus.COMPLETED == "completed"` is True. This makes JSON serialization and Cosmos DB storage seamless.

**Why `field(default_factory=...)`?** For mutable defaults (lists, dicts) and computed defaults (timestamps), you must use `field(default_factory=...)` instead of a direct value. Otherwise all instances share the same list object.

### 8.2 Cosmos DB Service (services/cosmos_service.py)

```python
import os
from azure.cosmos import CosmosClient
from models.document import DocumentMetadata

DATABASE_NAME  = "DocumentPlatformDB"
CONTAINER_NAME = "Documents"

class CosmosService:
    def __init__(self):
        endpoint = os.environ["COSMOS_ENDPOINT"]
        key      = os.environ["COSMOS_KEY"]
        self._container = (
            CosmosClient(endpoint, credential=key)
            .get_database_client(DATABASE_NAME)
            .get_container_client(CONTAINER_NAME)
        )

    def upsert(self, doc: DocumentMetadata) -> dict:
        # upsert = insert if not exists, update if exists
        return self._container.upsert_item(doc.to_dict())

    def get(self, doc_id: str, tenant_id: str) -> dict:
        # partition_key must match the container's partition key (/tenantId)
        return self._container.read_item(item=doc_id, partition_key=tenant_id)

    def update_status(self, doc_id: str, tenant_id: str, status: str, error: str = None):
        doc = self.get(doc_id, tenant_id)
        doc["status"] = status
        if error:
            doc["errorMessage"] = error
        self._container.upsert_item(doc)
```

**Key concept — partition key**: Every read/write operation includes `partition_key=tenant_id`. This tells Cosmos DB exactly which partition to look in, making the operation O(1) regardless of total data size.

### 8.3 Document Intelligence Service

```python
import os, urllib.request
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest
from azure.core.credentials import AzureKeyCredential
from models.document import DocumentType

class DocumentIntelligenceService:
    def __init__(self):
        endpoint = os.environ["AI_SERVICES_ENDPOINT"]
        key      = os.environ["AI_SERVICES_KEY"]
        self._client = DocumentIntelligenceClient(endpoint, AzureKeyCredential(key))

    def analyze(self, blob_url: str, blob_name: str = "") -> dict:
        # Plain text files are not supported by Document Intelligence
        # Read them directly instead
        if blob_name.lower().endswith(".txt"):
            with urllib.request.urlopen(blob_url) as r:
                full_text = r.read().decode("utf-8", errors="ignore").lower()
            return {
                "extracted_fields": [],
                "document_type": self._classify(full_text),
                "page_count": 1,
                "full_text": full_text[:5000]
            }

        # For PDFs and images, use Document Intelligence
        poller = self._client.begin_analyze_document(
            "prebuilt-read",
            AnalyzeDocumentRequest(url_source=blob_url)
        )
        result = poller.result()

        full_text = " ".join([
            line.content
            for page in (result.pages or [])
            for line in (page.lines or [])
        ]).lower()

        return {
            "extracted_fields": [],
            "document_type": self._classify(full_text),
            "page_count": len(result.pages) if result.pages else 0,
            "full_text": full_text[:5000]
        }

    def _classify(self, text: str) -> str:
        if any(w in text for w in ["invoice", "bill to", "amount due"]):
            return DocumentType.INVOICE
        if any(w in text for w in ["receipt", "total paid", "thank you"]):
            return DocumentType.RECEIPT
        if any(w in text for w in ["agreement", "contract", "terms"]):
            return DocumentType.CONTRACT
        return DocumentType.UNKNOWN
```

**Why `poller.result()`?** Document Intelligence is an async API. When you call `begin_analyze_document`, it starts the job and returns a poller. Calling `.result()` blocks until the job completes. This is the long-polling pattern.

**Why SAS URL?** Document Intelligence downloads the file from the URL you provide. If the blob is private, it gets a 403 error. The SAS URL grants temporary read access without exposing your storage account key.

### 8.4 OpenAI Service (services/openai_service.py)

This service wraps both GPT-4o (summarization) and text-embedding-ada-002 (vector embeddings).

```python
import logging, os
from openai import AzureOpenAI

class OpenAIService:
    def __init__(self):
        self._client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_KEY"],
            api_version="2024-12-01-preview"  # Required for *.services.ai.azure.com
        )
        self._deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")

    def summarize(self, text: str, doc_type: str) -> str:
        response = self._client.chat.completions.create(
            model=self._deployment,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an enterprise document analyst. "
                        "Summarize the document concisely, highlighting key information, "
                        "dates, amounts, and parties involved."
                    )
                },
                {
                    "role": "user",
                    "content": f"Document type: {doc_type}\n\nContent:\n{text[:3000]}"
                }
            ],
            max_tokens=500,
            temperature=0.3
        )
        return response.choices[0].message.content

    def get_embedding(self, text: str) -> list[float]:
        response = self._client.embeddings.create(
            model=os.environ.get("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "text-embedding-ada-002"),
            input=text[:8000]  # ada-002 has 8192 token limit
        )
        return response.data[0].embedding  # 1536-dimensional float list
```

**Why `temperature=0.3`?** Temperature controls randomness. 0 = deterministic, 1 = creative. For document summarization we want consistent, factual output, so we use a low value.

**Why `text[:3000]` for summarization but `text[:8000]` for embeddings?** GPT-4o has a large context window but we limit input to control cost and latency. Embeddings use a larger limit because the full text produces better semantic vectors.

**Why `api_version="2024-12-01-preview"`?** Azure AI Foundry resources (`*.services.ai.azure.com`) require this newer API version. Classic Azure OpenAI resources (`*.openai.azure.com`) use `2024-02-01`. Using the wrong version causes a `BadRequestError`.

**How it integrates in `process_document`**:
```python
openai_svc = OpenAIService()
try:
    summary   = openai_svc.summarize(extraction["full_text"], extraction["document_type"])
    embedding = openai_svc.get_embedding(extraction["full_text"])
except Exception as oai_ex:
    # Graceful fallback — pipeline continues without AI summary
    logger.warning("OpenAI unavailable, using fallback: %s", oai_ex)
    summary   = f"Extracted {extraction['page_count']} page(s) of type {extraction['document_type']}."
    embedding = None
```

The fallback means the pipeline never crashes due to OpenAI being unavailable. Documents still get indexed (keyword-only) and status is still `completed`. The trade-off: silent failures are harder to notice — always monitor the warning logs.

### 8.5 Search Service (services/search_service.py)

The search service has two responsibilities: creating the index schema, and indexing/searching documents.

```python
import os
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex, SimpleField, SearchableField, SearchField,
    SearchFieldDataType, VectorSearch, HnswAlgorithmConfiguration,
    VectorSearchProfile
)
from azure.core.credentials import AzureKeyCredential

INDEX_NAME = "documents-index"

class SearchService:
    def __init__(self):
        endpoint   = os.environ["SEARCH_ENDPOINT"]
        key        = os.environ["SEARCH_KEY"]
        credential = AzureKeyCredential(key)
        self._index_client  = SearchIndexClient(endpoint, credential)
        self._search_client = SearchClient(endpoint, INDEX_NAME, credential)
        self._ensure_index()

    def _ensure_index(self):
        try:
            self._index_client.get_index(INDEX_NAME)
        except Exception:
            self._create_index()

    def _create_index(self):
        index = SearchIndex(
            name=INDEX_NAME,
            fields=[
                SimpleField(name="id",           type=SearchFieldDataType.String, key=True),
                SimpleField(name="tenantId",      type=SearchFieldDataType.String, filterable=True),
                SimpleField(name="documentType",  type=SearchFieldDataType.String, filterable=True),
                SearchableField(name="fileName",  type=SearchFieldDataType.String),
                SearchableField(name="summary",   type=SearchFieldDataType.String),
                SearchableField(name="fullText",  type=SearchFieldDataType.String),
                SimpleField(name="createdAt",     type=SearchFieldDataType.DateTimeOffset, sortable=True),
                SearchField(
                    name="contentVector",
                    type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                    searchable=True,
                    vector_search_dimensions=1536,
                    vector_search_profile_name="vector-profile"
                )
            ],
            vector_search=VectorSearch(
                algorithms=[HnswAlgorithmConfiguration(name="hnsw-config")],
                profiles=[VectorSearchProfile(
                    name="vector-profile",
                    algorithm_configuration_name="hnsw-config"
                )]
            )
        )
        self._index_client.create_index(index)

    def index_document(self, doc_id, tenant_id, doc_type, file_name,
                       summary, full_text, created_at, embedding):
        document = {
            "id": doc_id, "tenantId": tenant_id,
            "documentType": doc_type, "fileName": file_name,
            "summary": summary, "fullText": full_text[:10000],
            "createdAt": created_at,
        }
        if embedding is not None:
            document["contentVector"] = embedding
        self._search_client.upload_documents([document])

    def search(self, query: str, tenant_id: str, query_vector=None) -> list:
        from azure.search.documents.models import VectorizedQuery
        vector_query = None
        if query_vector:
            vector_query = VectorizedQuery(
                vector=query_vector, k_nearest_neighbors=5, fields="contentVector"
            )
        results = self._search_client.search(
            search_text=query,
            vector_queries=[vector_query] if vector_query else None,
            filter=f"tenantId eq '{tenant_id}'",
            top=10
        )
        return [{"id": r["id"], "fileName": r["fileName"],
                 "summary": r["summary"], "score": r["@search.score"]}
                for r in results]
```

**Field types explained**:
- `SimpleField` — stored but not full-text searchable. Good for IDs, dates, filter values.
- `SearchableField` — full-text indexed. You can search within these fields.
- `SearchField` with vector dimensions — stores embedding vectors for semantic search.

**HNSW algorithm**: Hierarchical Navigable Small World. This is the algorithm used for approximate nearest-neighbor vector search. It builds a graph structure that allows finding similar vectors in O(log n) time instead of O(n).

**Why `embedding=None` check?** When OpenAI is not configured, we skip embedding generation. Passing `null` to a vector field in AI Search causes an error, so we simply omit the field.

### 8.6 The Main Function App (function_app.py)

```python
import json, logging, os, uuid
from datetime import datetime, timezone, timedelta
import azure.functions as func
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from models.document import DocumentMetadata, DocumentStatus
from services.cosmos_service import CosmosService
from services.document_intelligence_service import DocumentIntelligenceService
from services.search_service import SearchService

app    = func.FunctionApp()
logger = logging.getLogger(__name__)
```

**Function 1 — Blob Trigger**:
```python
@app.blob_trigger(
    arg_name="blob",
    path="incoming-documents/{name}",
    connection="BlobStorageConnection"
)
def on_document_uploaded(blob: func.InputStream):
    # blob.name on Linux = "tenant1/uuid/file.txt" (no container prefix)
    # blob.name on Windows = "incoming-documents/tenant1/uuid/file.txt"
    blob_path = blob.name
    parts     = blob_path.split("/")
    tenant_id = parts[0] if len(parts) >= 3 else "default-tenant"
    ...
```

**Critical lesson**: On Linux Azure Functions, `blob.name` does NOT include the container name. It is just the path within the container: `tenant1/uuid/file.txt`. On Windows (local dev), it may include the container prefix. Always handle both cases.

**Function 2 — Service Bus Trigger**:
```python
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="document-processing",
    connection="ServiceBusConnection"
)
def process_document(msg: func.ServiceBusMessage):
    payload   = json.loads(msg.get_body().decode("utf-8"))
    doc_id    = payload["documentId"]
    tenant_id = payload["tenantId"]
    ...
    try:
        # AI pipeline steps
        ...
    except Exception as ex:
        cosmos.update_status(doc_id, tenant_id, DocumentStatus.FAILED, str(ex))
        raise  # Re-raise so Service Bus retries, then dead-letters
```

**Why re-raise the exception?** If we catch the exception and don't re-raise, Service Bus thinks the message was processed successfully and deletes it. By re-raising, we tell Service Bus "this failed, try again". After `maxDeliveryCount` retries, the message goes to the dead-letter queue for manual inspection.

**Function 5 — Upload with multipart fallback**:
```python
@app.route(route="documents/upload", methods=["POST"])
def upload_document(req: func.HttpRequest) -> func.HttpResponse:
    import cgi, io

    # Try req.files first (works with proper HTTP clients like Python requests)
    if req.files.get("file"):
        file_obj  = req.files["file"]
        file_data = file_obj.stream.read()
        filename  = file_obj.filename
        tenant_id = req.form.get("tenantId") or req.form.get("tenant_id", "default-tenant")
    else:
        # Fallback: manually parse multipart body
        # Needed for PowerShell 5 and some HTTP clients
        content_type = req.headers.get("Content-Type", "")
        environ = {
            "REQUEST_METHOD": "POST",
            "CONTENT_TYPE": content_type,
            "CONTENT_LENGTH": str(len(req.get_body()))
        }
        form = cgi.FieldStorage(
            fp=io.BytesIO(req.get_body()),
            environ=environ,
            keep_blank_values=True
        )
        if "file" not in form:
            return func.HttpResponse(
                json.dumps({"error": "No file provided"}),
                mimetype="application/json", status_code=400
            )
        file_item = form["file"]
        file_data = file_item.file.read()
        filename  = file_item.filename or "upload"
        tenant_id = form.getvalue("tenantId") or form.getvalue("tenant_id") or "default-tenant"
    ...
```

**Why the fallback?** PowerShell 5's `Invoke-RestMethod` constructs multipart bodies differently from standard HTTP clients. The Azure Functions Python worker sometimes fails to parse them into `req.files`. The `cgi.FieldStorage` fallback parses the raw bytes directly.

---

## 9. Deployment Step by Step

### 9.1 Deploy Infrastructure

```bash
az deployment sub create \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.json
```

Note the outputs — you need the resource names to get connection strings.

### 9.2 Configure App Settings

After infrastructure is deployed, set all environment variables on the Function App:

```bash
FUNC="funchl45ya2j-linux"
RG="rg-docplatform-dev"

az functionapp config appsettings set \
  --name $FUNC --resource-group $RG \
  --settings \
    "STORAGE_CONNECTION_STRING=<storage-conn-str>" \
    "ServiceBusConnection=<servicebus-conn-str>" \
    "BlobStorageConnection=<storage-conn-str>" \
    "COSMOS_ENDPOINT=https://<cosmos>.documents.azure.com:443/" \
    "COSMOS_KEY=<cosmos-key>" \
    "AI_SERVICES_ENDPOINT=https://<ai-services>.cognitiveservices.azure.com/" \
    "AI_SERVICES_KEY=<ai-services-key>" \
    "AZURE_OPENAI_ENDPOINT=https://<ai-services>.cognitiveservices.azure.com/" \
    "AZURE_OPENAI_KEY=<ai-services-key>" \
    "AZURE_OPENAI_DEPLOYMENT=gpt-4o" \
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-ada-002" \
    "SEARCH_ENDPOINT=https://<search>.search.windows.net" \
    "SEARCH_KEY=<search-key>"
```

**Important**: If you only have one Cognitive Services account (not a dedicated Azure OpenAI resource), set both `AI_SERVICES_ENDPOINT` and `AZURE_OPENAI_ENDPOINT` to the same `cognitiveservices.azure.com` URL.

### 9.3 Deploy Function App Code

```bash
cd src/functions/DocumentProcessor

func azure functionapp publish funchl45ya2j-linux --python --build remote
```

**Why `--build remote`?** The Consumption plan runs on Linux. Some Python packages have C extensions that must be compiled for Linux. `--build remote` sends your code to Azure, which compiles it on a Linux machine. Without this flag, packages compiled on Windows will fail at runtime on Linux.

**What happens during deployment**:
1. Your code is zipped and uploaded to Azure
2. Azure runs `pip install -r requirements.txt` on a Linux build agent
3. The compiled packages + your code are deployed to the Function App
4. Azure restarts the Function App with the new code

### 9.4 Deploy OpenAI Models

Azure OpenAI requires you to explicitly deploy model instances before using them:

1. Go to https://ai.azure.com
2. Select your Azure AI resource
3. Go to **Deployments** → **Deploy model**
4. Deploy `gpt-4o` — you can name the deployment anything (e.g. `gpt-4o-1`)
5. Deploy `text-embedding-ada-002` — name it `text-embedding-ada-002`

The deployment name (not the model name) is what you put in `AZURE_OPENAI_DEPLOYMENT` and `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` app settings. Check your exact deployment names with:

```bash
az cognitiveservices account deployment list \
  --name <your-resource-name> \
  --resource-group <resource-group> \
  --query "[].{name:name, model:properties.model.name}" -o table
```

Then set the app settings using the exact names from the output:

```bash
az functionapp config appsettings set \
  --name <func-name> --resource-group <rg> \
  --settings \
    "AZURE_OPENAI_ENDPOINT=https://<resource>.services.ai.azure.com" \
    "AZURE_OPENAI_KEY=<key>" \
    "AZURE_OPENAI_DEPLOYMENT=gpt-4o-1" \
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-ada-002"
```

**Verify the key was saved correctly** — the CLI masks secrets in output. Always confirm with:
```bash
az functionapp config appsettings list --name <func-name> --resource-group <rg> \
  --query "[?contains(name,'OPENAI')].{name:name,value:value}" -o table
```
If `AZURE_OPENAI_KEY` shows as a placeholder like `<AZURE_OPENAI_KEY>`, the literal text was saved instead of the real key. Re-run the set command with the actual key value.

### 9.5 Verify Deployment

```bash
# Check all 5 functions are deployed
az functionapp function list \
  --name funchl45ya2j-linux \
  --resource-group rg-docplatform-dev \
  --query "[].name" --output table

# Expected output:
# funchl45ya2j-linux/get_document_status
# funchl45ya2j-linux/on_document_uploaded
# funchl45ya2j-linux/process_document
# funchl45ya2j-linux/search_documents
# funchl45ya2j-linux/upload_document
```

---

## 10. Testing the Platform

### 10.1 Upload a Document

**Using Python (recommended — works on all platforms)**:

```python
# upload_test.py
import requests

with open("test.txt", "rb") as f:
    resp = requests.post(
        "https://<func>.azurewebsites.net/api/documents/upload",
        headers={"x-functions-key": "<function-key>"},
        files={"file": ("test.txt", f, "text/plain")},
        data={"tenant_id": "tenant1"}
    )

print(resp.status_code, resp.json())
# Expected: 202 {"message": "Document uploaded", "blobName": "tenant1/uuid/test.txt"}
```

**Using az CLI (bypasses upload function, triggers blob trigger directly)**:

```bash
az storage blob upload \
  --account-name sthl45ya2j \
  --container-name incoming-documents \
  --name "tenant1/$(python -c 'import uuid; print(uuid.uuid4())')/test.txt" \
  --file test.txt \
  --auth-mode key
```

### 10.2 Check Document Status

```python
import requests

doc_id = "d4bd3ae1-3e15-46c6-a605-65c054bf487d"
resp = requests.get(
    f"https://<func>.azurewebsites.net/api/documents/{doc_id}/status",
    params={"tenantId": "tenant1"},
    headers={"x-functions-key": "<function-key>"}
)
print(resp.json())
```

Expected response when completed (with OpenAI enabled):
```json
{
  "documentId": "71838441-c43c-4b9c-b7c0-252e71f0ffa6",
  "status": "completed",
  "documentType": "invoice",
  "summary": "**Invoice Summary**\n\n- **Invoice Number:** #12345\n- **Date Issued:** January 15, 2024\n- **Billed To:** Acme Corporation\n- **Item:** Cloud Services (January 2024)\n- **Amount Due:** $1,500.00\n\nThank you for your business.",
  "pageCount": 1,
  "createdAt": "2026-11-05T11:48:49Z",
  "updatedAt": "2026-11-05T11:48:49Z"
}
```

If OpenAI is not configured or falls back, the summary will be the static string `"Extracted 1 page(s) of type invoice."` — this is the graceful degradation fallback.

### 10.3 Search Documents

```python
import requests

resp = requests.post(
    "https://<func>.azurewebsites.net/api/documents/search",
    headers={
        "x-functions-key": "<function-key>",
        "Content-Type": "application/json"
    },
    json={"query": "invoice cloud services", "tenantId": "tenant1"}
)
print(resp.json())
```

Expected response (with vector search enabled):
```json
{
  "results": [
    {
      "id": "71838441-c43c-4b9c-b7c0-252e71f0ffa6",
      "fileName": "tenant1/71838441-.../test.txt",
      "summary": "**Invoice Summary**\n- Invoice Number: #12345...",
      "score": 0.03333
    }
  ],
  "count": 4
}
```

The newest document (with vector embedding) ranks first. Older documents indexed without embeddings still appear via keyword search but with lower scores. This is hybrid search — both modes work simultaneously.

### 10.4 Poll Until Completed

```python
import time, requests

def wait_for_completion(doc_id, tenant_id, func_url, func_key, timeout=180):
    url = f"{func_url}/api/documents/{doc_id}/status"
    headers = {"x-functions-key": func_key}

    for _ in range(timeout // 15):
        time.sleep(15)
        try:
            resp = requests.get(url, params={"tenantId": tenant_id}, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                print(f"{time.strftime('%H:%M:%S')} status: {data['status']}")
                if data["status"] in ("completed", "failed"):
                    return data
        except Exception as e:
            print(f"{time.strftime('%H:%M:%S')} not found yet: {e}")

    return None
```

---

## 11. Troubleshooting Guide

### 11.1 Error Reference Table

| Error | Root Cause | Fix |
|---|---|---|
| `InvalidContent: file is corrupted or format is unsupported` | Sending `.txt` to `prebuilt-document` model | Switch to `prebuilt-read` model, or use a real PDF |
| `InvalidContent: Could not download the file` | Document Intelligence cannot access private blob | Generate SAS URL before passing to Document Intelligence |
| `tenantId = "incoming-documents"` in Cosmos | `blob.name` includes container prefix on some runtimes | Strip `incoming-documents/` prefix before splitting on `/` |
| `MaxDeliveryCountExceeded` in dead-letter queue | `process_document` crashed 5 times | Check App Insights exceptions for the real error |
| `No file provided` (400) from upload endpoint | `req.files` is empty — multipart not parsed | Use Python `requests` library; or add `cgi.FieldStorage` fallback |
| `DeploymentNotFound` from OpenAI | Model not deployed in Azure AI Foundry | Go to ai.azure.com, deploy `gpt-4o` and `text-embedding-ada-002` |
| `AuthenticationError 401` from OpenAI | Wrong endpoint or key | Verify endpoint matches your resource; check key was not saved as placeholder text |
| OpenAI falls back silently (static summary) | `AZURE_OPENAI_KEY` saved as literal `<AZURE_OPENAI_KEY>` | Re-run `az functionapp config appsettings set` with the actual key value |
| `api_version` mismatch error | Azure AI Foundry requires newer API version | Use `2024-12-01-preview` for `*.services.ai.azure.com` endpoints |
| Status always `not found yet` | Cosmos record not created (blob trigger not fired) | Upload directly via `az storage blob upload` and send Service Bus message manually |
| Blob trigger delay (up to 10 min) | Consumption plan uses polling, not event-driven | Expected behavior; use Event Grid trigger for production |
| `func publish` fails with native package errors | Packages compiled for wrong OS | Always use `--build remote` flag |

### 11.2 Blob Trigger Not Firing

The blob trigger on Consumption plan uses a polling mechanism. Azure checks for new blobs every few minutes. This is a known limitation.

**To confirm the trigger fired**, check the Service Bus queue message count:
```bash
az servicebus queue show \
  --resource-group rg-docplatform-dev \
  --namespace-name sbhl45ya2j \
  --name document-processing \
  --query "countDetails" --output table
```

If `deadLetterMessageCount` increases after upload, the trigger fired but processing failed.

**For production**, use Event Grid blob triggers which fire within seconds:
1. Create an Event Grid System Topic on your storage account
2. Change the blob trigger binding to use Event Grid connection

### 11.3 Reading Dead-Letter Messages

When messages fail repeatedly, they go to the dead-letter queue. The dead-letter reason is always `MaxDeliveryCountExceeded` — the actual exception is only visible in App Insights.

```python
# peek_dlq.py — inspect dead-letter messages
from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode
import json

conn = "<servicebus-connection-string>"
with ServiceBusClient.from_connection_string(conn) as sb:
    receiver = sb.get_queue_receiver(
        "document-processing",
        sub_queue="deadletter",
        receive_mode=ServiceBusReceiveMode.PEEK_LOCK,
        max_wait_time=5
    )
    with receiver:
        msgs = receiver.receive_messages(max_message_count=10)
        for msg in sorted(msgs, key=lambda m: m.enqueued_time_utc):
            # IMPORTANT: msg.body returns a generator, not bytes
            # Use raw_amqp_message.body and join the chunks
            body = json.loads(b"".join(msg.raw_amqp_message.body).decode("utf-8"))
            print("documentId:", body.get("documentId"))
            print("tenantId:", body.get("tenantId"))
            print("reason:", msg.dead_letter_reason)
            print("enqueued:", msg.enqueued_time_utc)
            print("---")
            receiver.abandon_message(msg)  # Put back, don't delete
```

**Why `raw_amqp_message.body`?** In the Azure Service Bus Python SDK, `msg.body` returns a generator object, not bytes. You must join the chunks: `b"".join(msg.raw_amqp_message.body)`. There is no `msg.get_body()` method in this SDK version.

### 11.4 Generating SAS URLs

Any external service that needs to read a private blob requires a SAS URL:

```python
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from datetime import datetime, timezone, timedelta

conn_str = os.environ["AzureWebJobsStorage"]
bsc      = BlobServiceClient.from_connection_string(conn_str)

sas_token = generate_blob_sas(
    account_name=bsc.account_name,
    container_name="incoming-documents",
    blob_name=blob_path,           # e.g. "tenant1/uuid/file.pdf"
    account_key=bsc.credential.account_key,
    permission=BlobSasPermissions(read=True),
    expiry=datetime.now(timezone.utc) + timedelta(hours=1)
)

sas_url = (
    f"https://{bsc.account_name}.blob.core.windows.net"
    f"/incoming-documents/{blob_path}?{sas_token}"
)
```

The SAS token encodes: which blob, what permissions (read-only), and when it expires. It is cryptographically signed with your storage account key, so it cannot be forged.

### 11.5 Querying App Insights for Errors

When a function fails, the exception is logged to Application Insights. Query it with:

```bash
az monitor app-insights query \
  --app <app-insights-name> \
  --resource-group rg-docplatform-dev \
  --analytics-query "exceptions | where timestamp > ago(1h) | project timestamp, innermostMessage | order by timestamp desc"
```

Or use the Azure Portal: App Insights → Logs → paste the query.

### 11.6 PowerShell 5 Multipart Upload

PowerShell 5's `curl` is an alias for `Invoke-WebRequest` and does not support `-F` (form file upload). Use Python `requests` instead:

```python
# upload_test.py
import requests

with open("path/to/file.txt", "rb") as f:
    resp = requests.post(
        "https://<func>.azurewebsites.net/api/documents/upload",
        headers={"x-functions-key": "<key>"},
        files={"file": ("file.txt", f, "text/plain")},
        data={"tenant_id": "tenant1"}
    )
print(resp.status_code, resp.json())
```

If you must use PowerShell 5, construct the multipart body as raw bytes:

```powershell
$bytes    = [System.IO.File]::ReadAllBytes("C:\path\to\file.txt")
$boundary = [System.Guid]::NewGuid().ToString()
$bodyText = "--$boundary`r`nContent-Disposition: form-data; name=`"tenant_id`"`r`n`r`ntenant1`r`n" +
            "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"file.txt`"`r`nContent-Type: text/plain`r`n`r`n"
$body = [System.Text.Encoding]::UTF8.GetBytes($bodyText) + $bytes +
        [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")

Invoke-RestMethod -Uri "https://<func>.azurewebsites.net/api/documents/upload" `
  -Method POST -Body $body `
  -ContentType "multipart/form-data; boundary=$boundary" `
  -Headers @{ "x-functions-key" = "<key>" }
```

Note: PowerShell 6+ supports `-Form` parameter which is much simpler.

---

## 12. Key Lessons Learned

These are real issues encountered while building this platform. Each one is a valuable lesson.

### Lesson 1: blob.name Behavior Differs by OS

**Problem**: `tenantId` was being set to `"incoming-documents"` instead of `"tenant1"`.

**Root cause**: On Linux Azure Functions, `blob.name` = `"tenant1/uuid/file.txt"` (no container prefix). On Windows local dev, it may = `"incoming-documents/tenant1/uuid/file.txt"`.

**Fix**: Always strip the container prefix defensively:
```python
blob_path = blob.name
if blob_path.startswith("incoming-documents/"):
    blob_path = blob_path[len("incoming-documents/"):]
parts = blob_path.split("/")
tenant_id = parts[0] if len(parts) >= 3 else "default-tenant"
```

### Lesson 2: Private Blobs Need SAS URLs

**Problem**: Document Intelligence returned `InvalidContent: Could not download the file`.

**Root cause**: The blob URL `https://storage.blob.core.windows.net/container/file.pdf` returns 403 for private blobs. Document Intelligence tried to download it and got access denied.

**Fix**: Always generate a SAS URL before passing to any external service.

### Lesson 3: prebuilt-document Rejects Plain Text

**Problem**: `InvalidContent: The file is corrupted or format is unsupported` even for a valid `.txt` file.

**Root cause**: `prebuilt-document` model only accepts PDF, images, and Office documents. Plain text files are not supported.

**Fix**: Use `prebuilt-read` for testing (accepts plain text), or use real PDFs. For `.txt` files, read the content directly with `urllib.request.urlopen`.

### Lesson 4: Dead-Letter Reason is Always Generic

**Problem**: Dead-letter messages always show `MaxDeliveryCountExceeded` with no useful description.

**Root cause**: The Service Bus runtime dead-letters after N retries. It doesn't capture the original exception — that's only in App Insights.

**Fix**: Always check App Insights exceptions, not dead-letter metadata, for the real error.

### Lesson 5: Re-raise Exceptions in Service Bus Functions

**Problem**: If you catch an exception and don't re-raise, Service Bus deletes the message thinking it succeeded. The document stays in `processing` state forever.

**Fix**: Always re-raise after updating Cosmos DB to `failed`:
```python
except Exception as ex:
    cosmos.update_status(doc_id, tenant_id, DocumentStatus.FAILED, str(ex))
    raise  # This tells Service Bus to retry / dead-letter
```

### Lesson 6: --build remote is Required for Linux

**Problem**: Function app deployed successfully but crashed at startup with import errors for packages with C extensions.

**Root cause**: Packages compiled on Windows are not compatible with Linux. The Function App runs on Linux.

**Fix**: Always use `func azure functionapp publish <name> --python --build remote`.

### Lesson 7: Cosmos DB Partition Key Must Always Be Provided

**Problem**: `CosmosException: Cross partition query is required but disabled`.

**Root cause**: Querying Cosmos DB without the partition key triggers a cross-partition scan, which is disabled by default on serverless accounts.

**Fix**: Always pass `partition_key=tenant_id` to every read/write operation.

### Lesson 8: Service Bus Message Body is a Generator

**Problem**: `b"".join(msg.body)` fails — `msg.body` is not iterable bytes.

**Root cause**: In the Azure Service Bus Python SDK, `msg.body` returns a generator. There is no `msg.get_body()` method.

**Fix**: Use `b"".join(msg.raw_amqp_message.body).decode("utf-8")`.

### Lesson 9: Blob Trigger Has Up to 10-Minute Delay on Consumption Plan

**Problem**: Uploaded a blob, waited 3 minutes, no trigger fired.

**Root cause**: Consumption plan blob triggers use polling (checks every few minutes). This is by design — it is a cost/latency tradeoff.

**Fix for production**: Use Event Grid-based blob triggers. For development: upload directly via `az storage blob upload` and send the Service Bus message manually to test the processing pipeline independently.

### Lesson 10: Azure OpenAI Requires Model Deployments

**Problem**: `DeploymentNotFound` error even though the Azure OpenAI resource exists.

**Root cause**: Creating an Azure OpenAI resource does not automatically deploy any models. You must explicitly deploy each model (GPT-4o, text-embedding-ada-002) in the Azure AI Foundry portal.

**Fix**: Go to https://ai.azure.com → your resource → Deployments → Deploy model.

### Lesson 11: App Settings Key Saved as Placeholder Text

**Problem**: OpenAI calls silently fell back to static summary even after setting app settings. Status showed `completed` but summary was `"Extracted 1 page(s) of type invoice."` — the fallback string.

**Root cause**: When the CLI command used `<AZURE_OPENAI_KEY>` as a placeholder in documentation, the literal string `<AZURE_OPENAI_KEY>` was saved as the setting value instead of the real key. The function caught the resulting `AuthenticationError` and silently fell back.

**Fix**: Always verify saved settings after setting them:
```bash
az functionapp config appsettings list --name <func> --resource-group <rg> \
  --query "[?contains(name,'OPENAI')].{name:name,value:value}" -o table
```
If the value looks like a placeholder, re-run the set command with the real value.

### Lesson 12: Azure AI Foundry Endpoints Need a Newer API Version

**Problem**: `BadRequestError: API version 2024-02-01 is not supported` when calling Azure OpenAI.

**Root cause**: Resources created via Azure AI Foundry use the `AIServices` kind with endpoint `*.services.ai.azure.com`. This endpoint requires API version `2024-12-01-preview` or later. The classic `2024-02-01` version only works with `*.openai.azure.com` endpoints.

**Fix**: Set `api_version="2024-12-01-preview"` in the `AzureOpenAI` client constructor when using an Azure AI Foundry resource.

### Lesson 13: Graceful Degradation Makes Bugs Invisible

**Problem**: The pipeline reported `completed` even when OpenAI was broken, making it hard to notice the failure.

**Root cause**: The `try/except` around OpenAI calls catches all exceptions and falls back to a static summary. This is good for resilience but bad for debugging — silent failures are the hardest to find.

**Lesson**: In production, always emit a metric or alert when a fallback is triggered. A warning log is not enough — it gets lost in noise. Use Application Insights custom events:
```python
logger.warning("OpenAI unavailable, using fallback: %s", oai_ex)
# In production, also emit a custom metric:
# telemetry_client.track_metric("openai_fallback", 1)
```

---

## 13. Next Steps

Now that you have a working end-to-end platform, here are the natural extensions:

### Immediate Improvements

**1. ✅ OpenAI Summarization — COMPLETED**
GPT-4o summarization and `text-embedding-ada-002` vector embeddings are fully integrated. The pipeline now produces real AI-generated summaries and hybrid vector+keyword search. Deployment names: `gpt-4o-1` (GPT) and `text-embedding-ada-002` (embeddings) on resource `amol0405-5253-resource`.

**2. Fix Blob Trigger Latency
Switch from polling-based blob trigger to Event Grid:
- Create an Event Grid System Topic on your storage account
- Subscribe to `BlobCreated` events
- Change the blob trigger binding to use Event Grid

**3. Fix Upload via HTTP**
The `upload_document` function works with Python `requests` (confirmed working, returns 202). For a production frontend, use the JavaScript `fetch` API with `FormData` — it handles multipart correctly.

### Architecture Enhancements

**4. Add Authentication**
Currently any request with the function key can access any tenant's data. Add Azure AD authentication so each user can only access their own tenant.

**5. Use Managed Identity**
Replace all connection strings and API keys with Managed Identity. The Function App gets an identity, and you grant it RBAC roles on each service. No secrets to rotate or leak.

**6. Add API Management**
Put Azure API Management in front of your functions for:
- Rate limiting (prevent abuse)
- API versioning
- Developer portal
- OAuth 2.0 authentication

**7. Add a Frontend**
Build a React or Vue.js frontend deployed to Azure Static Web Apps. It calls your Function App APIs to upload documents, show status, and search.

### Production Readiness

**8. Switch to Premium Plan**
Eliminate cold starts and blob trigger delays. Required for VNet integration (private endpoints).

**9. Add Private Endpoints**
In production, all services (Cosmos DB, Service Bus, Storage) should be on a private VNet. No public internet access.

**10. CI/CD Pipeline**
Add GitHub Actions to automatically deploy infrastructure and code on every push to main branch.

---

## Appendix A: Complete local.settings.json Template

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "<storage-connection-string>",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "FUNCTIONS_EXTENSION_VERSION": "~4",
    "BlobStorageConnection": "<storage-connection-string>",
    "ServiceBusConnection": "<servicebus-connection-string>",
    "COSMOS_ENDPOINT": "https://<cosmos-account>.documents.azure.com:443/",
    "COSMOS_KEY": "<cosmos-primary-key>",
    "AI_SERVICES_ENDPOINT": "https://<ai-services>.cognitiveservices.azure.com/",
    "AI_SERVICES_KEY": "<ai-services-key>",
    "AZURE_OPENAI_ENDPOINT": "https://<ai-services>.cognitiveservices.azure.com/",
    "AZURE_OPENAI_KEY": "<ai-services-key>",
    "AZURE_OPENAI_DEPLOYMENT": "gpt-4o",
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT": "text-embedding-ada-002",
    "SEARCH_ENDPOINT": "https://<search-service>.search.windows.net",
    "SEARCH_KEY": "<search-admin-key>"
  }
}
```

Add `local.settings.json` to `.gitignore` — never commit secrets.

## Appendix B: Quick Reference Commands

```bash
# Deploy infrastructure
az deployment sub create --location centralindia \
  --template-file infra/main.bicep --parameters infra/parameters.dev.json

# Deploy function code
func azure functionapp publish <func-name> --python --build remote

# Get function key
az functionapp keys list --name <func-name> --resource-group <rg>

# Stream live logs
az functionapp log tail --name <func-name> --resource-group <rg>

# Check dead-letter count
az servicebus queue show --resource-group <rg> \
  --namespace-name <sb-namespace> --name document-processing \
  --query "countDetails" --output table

# Restart function app
az functionapp restart --name <func-name> --resource-group <rg>

# List all app settings
az functionapp config appsettings list --name <func-name> --resource-group <rg>
```

## Appendix C: Architecture Decision Records

These are the key decisions made and why:

| Decision | Chosen | Rejected | Reason |
|---|---|---|---|
| Compute | Azure Functions (Consumption) | AKS, App Service | Lowest cost for event-driven workloads |
| Database | Cosmos DB Serverless | Azure SQL, Table Storage | Schema flexibility, native JSON, serverless pricing |
| Queue | Service Bus | Storage Queue, Event Hub | Dead-letter support, message locking, enterprise features |
| AI extraction | Document Intelligence | Custom OCR, Tesseract | Pre-trained models, no ML expertise needed |
| Search | Azure AI Search | Elasticsearch, Cosmos DB search | Native vector search, hybrid search, managed service |
| IaC | Bicep | Terraform, ARM JSON | Native Azure, simpler syntax than ARM, no state file |
| Language | Python 3.11 | Node.js, C# | Best AI/ML library ecosystem |

---

*Tutorial for Enterprise AI Document Processing Platform*
*Built on Azure AI Foundry — November 2026*
