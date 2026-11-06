import logging
import os
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex, SimpleField, SearchableField, SearchField,
    SearchFieldDataType, VectorSearch, HnswAlgorithmConfiguration,
    VectorSearchProfile, SemanticConfiguration, SemanticSearch,
    SemanticPrioritizedFields, SemanticField
)
from azure.core.credentials import AzureKeyCredential

logger = logging.getLogger(__name__)

INDEX_NAME = "documents-index"


class SearchService:
    def __init__(self):
        endpoint   = os.environ["SEARCH_ENDPOINT"]
        api_key    = os.environ["SEARCH_KEY"]
        credential = AzureKeyCredential(api_key)

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
                profiles=[VectorSearchProfile(name="vector-profile", algorithm_configuration_name="hnsw-config")]
            ),
            semantic_search=SemanticSearch(
                configurations=[SemanticConfiguration(
                    name="semantic-config",
                    prioritized_fields=SemanticPrioritizedFields(
                        content_fields=[SemanticField(field_name="summary"),
                                        SemanticField(field_name="fullText")]
                    )
                )]
            )
        )
        self._index_client.create_index(index)
        logger.info("Created search index: %s", INDEX_NAME)

    def index_document(self, doc_id: str, tenant_id: str, doc_type: str,
                       file_name: str, summary: str, full_text: str,
                       created_at: str, embedding: list[float]):
        document = {
            "id":           doc_id,
            "tenantId":     tenant_id,
            "documentType": doc_type,
            "fileName":     file_name,
            "summary":      summary,
            "fullText":     full_text[:10000],
            "createdAt":    created_at,
        }
        if embedding is not None:
            document["contentVector"] = embedding
        self._search_client.upload_documents([document])
        logger.info("Indexed document %s in search", doc_id)

    def search(self, query: str, tenant_id: str, query_vector: list[float] = None) -> list:
        from azure.search.documents.models import VectorizedQuery

        vector_query = None
        if query_vector:
            vector_query = VectorizedQuery(
                vector=query_vector,
                k_nearest_neighbors=5,
                fields="contentVector"
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
