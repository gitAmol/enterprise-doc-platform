import logging
import os
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from models.document import DocumentMetadata

logger = logging.getLogger(__name__)

DATABASE_NAME   = "DocumentPlatformDB"
CONTAINER_NAME  = "Documents"


class CosmosService:
    def __init__(self):
        endpoint = os.environ["COSMOS_ENDPOINT"]
        key      = os.environ["COSMOS_KEY"]
        self._client    = CosmosClient(endpoint, credential=key)
        self._container = (
            self._client
            .get_database_client(DATABASE_NAME)
            .get_container_client(CONTAINER_NAME)
        )

    def upsert(self, doc: DocumentMetadata) -> dict:
        result = self._container.upsert_item(doc.to_dict())
        logger.info("Upserted document %s", doc.id)
        return result

    def get(self, doc_id: str, tenant_id: str) -> dict:
        return self._container.read_item(item=doc_id, partition_key=tenant_id)

    def update_status(self, doc_id: str, tenant_id: str, status: str, error: str = None):
        doc = self.get(doc_id, tenant_id)
        doc["status"] = status
        if error:
            doc["errorMessage"] = error
        self._container.upsert_item(doc)
        logger.info("Updated document %s status to %s", doc_id, status)
