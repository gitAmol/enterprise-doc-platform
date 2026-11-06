import logging
import os
from openai import AzureOpenAI

logger = logging.getLogger(__name__)


class OpenAIService:
    def __init__(self):
        self._client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_KEY"],
            api_version="2024-12-01-preview"
        )
        self._deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")

    def summarize(self, text: str, doc_type: str) -> str:
        logger.info("Summarizing %s document", doc_type)

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

        summary = response.choices[0].message.content
        logger.info("Summary generated (%d chars)", len(summary))
        return summary

    def get_embedding(self, text: str) -> list[float]:
        response = self._client.embeddings.create(
            model=os.environ.get("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "text-embedding-ada-002"),
            input=text[:8000]
        )
        return response.data[0].embedding
