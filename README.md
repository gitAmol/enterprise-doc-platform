# 🏗️ Enterprise Document Processing Platform

An enterprise-grade, event-driven document processing platform built on Azure, demonstrating modern cloud architecture patterns.

## 🎯 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Azure Front Door (CDN + WAF)                          │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
            ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
            │   React UI   │    │   Admin UI   │    │   REST API   │
            │ (Static Web) │    │ (Static Web) │    │  (API Mgmt)  │
            └──────────────┘    └──────────────┘    └──────────────┘
                                                            │
                                                            ▼
                                                 ┌──────────────────┐
                                                 │  Azure Functions │
                                                 │   (Orchestrator) │
                                                 └──────────────────┘
                                                            │
                    ┌───────────────────┬───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼                   ▼
            ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
            │ Service Bus  │    │  Event Grid  │    │ Blob Storage │    │  Cosmos DB   │
            │   (Queue)    │    │  (Events)    │    │  (Documents) │    │  (Metadata)  │
            └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                    │                   │
                    ▼                   ▼
            ┌──────────────────────────────────────────────────────────┐
            │                    AI Processing Pipeline                 │
            ├──────────────┬──────────────┬──────────────┬─────────────┤
            │ Doc Intel    │ Azure OpenAI │ AI Search    │ Translator  │
            │ (OCR/Extract)│ (Summarize)  │ (Index)      │ (Multi-lang)│
            └──────────────┴──────────────┴──────────────┴─────────────┘
```

## 🔐 Security Features

| Feature | Implementation |
|---------|----------------|
| **Zero-Trust** | Managed Identity for all service-to-service auth |
| **Secrets Management** | Azure Key Vault with RBAC |
| **Network Security** | Private endpoints (production) |
| **API Security** | OAuth 2.0, Rate limiting, WAF |
| **Data Encryption** | TLS 1.2+, encryption at rest |

## 📦 Azure Services Used

| Service | Purpose | Tier |
|---------|---------|------|
| Azure Functions | Serverless compute | Consumption |
| Azure Service Bus | Message queue | Standard |
| Azure Cosmos DB | Document metadata | Serverless |
| Azure Blob Storage | Document storage | Standard LRS |
| Azure AI Services | Document Intelligence | S0 |
| Azure OpenAI | GPT-4o, Embeddings | S0 |
| Azure AI Search | Vector search | Basic |
| API Management | API Gateway | Consumption |
| Key Vault | Secrets | Standard |
| Application Insights | Monitoring | Pay-as-you-go |

## 🚀 Deployment

### Prerequisites

1. Azure CLI installed and logged in
2. Azure subscription with sufficient permissions
3. Bicep CLI (included with Azure CLI)

### Deploy Infrastructure

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Deploy to dev environment
az deployment sub create \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.json
```

### Validate Deployment

```bash
# List deployed resources
az resource list --resource-group rg-docplatform-dev --output table
```

## 📁 Project Structure

```
enterprise-doc-platform/
├── infra/                      # Infrastructure as Code
│   ├── main.bicep              # Main orchestration
│   ├── parameters.dev.json     # Dev environment params
│   └── modules/
│       ├── keyvault.bicep      # Key Vault
│       ├── storage.bicep       # Blob Storage
│       ├── cosmosdb.bicep      # Cosmos DB
│       ├── servicebus.bicep    # Service Bus
│       ├── ai-services.bicep   # AI Services
│       ├── functions.bicep     # Azure Functions
│       ├── apim.bicep          # API Management
│       └── monitoring.bicep    # Observability
├── src/                        # Application code
│   ├── functions/              # Azure Functions
│   ├── api/                    # API layer
│   └── frontend/               # React UI
├── docs/                       # Documentation
└── README.md
```

## 🏛️ Enterprise Architecture Patterns

### 1. Event-Driven Architecture
- Loose coupling between services
- Async processing with Service Bus
- Event Grid for real-time notifications

### 2. CQRS Pattern
- Separate read/write paths
- Optimized query performance with AI Search
- Event sourcing with Cosmos DB

### 3. Circuit Breaker
- Dead-letter queues for failed messages
- Retry policies with exponential backoff
- Graceful degradation

### 4. Zero-Trust Security
- No hardcoded credentials
- Managed Identity everywhere
- RBAC-based access control

## 💰 Cost Optimization

- **Serverless**: Pay only for execution
- **Consumption tiers**: APIM, Functions
- **Auto-scaling**: Scale to zero when idle
- **Reserved capacity**: For production workloads

## 📊 Monitoring & Observability

- Distributed tracing with Application Insights
- Custom metrics and dashboards
- Alerting for SLA breaches
- Log Analytics for centralized logging

## 🔄 CI/CD Pipeline

GitHub Actions workflow included for:
- Infrastructure validation
- Automated deployment
- Integration testing

## 📝 License

MIT License

## 👤 Author

[Your Name] - Enterprise Architect

---

*Built as part of Azure AI learning journey*
