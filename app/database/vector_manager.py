import os
import tempfile
from typing import List, Dict, Any, Optional, Union
from pathlib import Path
import uuid
import time

from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import (
    TextLoader, 
    PyPDFLoader, 
    UnstructuredMarkdownLoader
)
from langchain_community.vectorstores import Chroma
from langchain_openai import OpenAIEmbeddings
from langchain.schema import Document

class VectorDatabaseManager:
    """Manager for vector database operations"""
    
    def __init__(self, db_path: str, embedding_model: str = "text-embedding-3-small"):
        """
        Initialize the vector database manager
        
        Args:
            db_path: Path to the vector database
            embedding_model: OpenAI embedding model to use
        """
        self.db_path = db_path
        self._ensure_db_exists()
        
        # Initialize embeddings
        self.embeddings = OpenAIEmbeddings(model=embedding_model)
        
        # Initialize vector store
        self.vector_store = Chroma(
            persist_directory=self.db_path,
            embedding_function=self.embeddings
        )
        
        # Text splitter for document chunking
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=100
        )
    
    def _ensure_db_exists(self):
        """Ensure the vector database directory exists"""
        if not os.path.exists(self.db_path):
            os.makedirs(self.db_path)
    
    def add_document(self, file_obj: Any, metadata: Optional[Dict[str, Any]] = None) -> bool:
        """
        Add a document to the vector database
        
        Args:
            file_obj: File object (from Streamlit file_uploader)
            metadata: Optional metadata for the document
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Create a temporary file to save the uploaded content
            with tempfile.NamedTemporaryFile(delete=False, suffix=f".{file_obj.name.split('.')[-1]}") as temp_file:
                temp_file.write(file_obj.getvalue())
                temp_path = temp_file.name
            
            # Load the document based on file type
            file_extension = file_obj.name.split('.')[-1].lower()
            
            if file_extension == 'pdf':
                loader = PyPDFLoader(temp_path)
            elif file_extension == 'md':
                loader = UnstructuredMarkdownLoader(temp_path)
            else:  # Default to text loader
                loader = TextLoader(temp_path)
            
            documents = loader.load()
            
            # Add metadata if provided
            if metadata:
                for doc in documents:
                    doc.metadata.update(metadata)
            else:
                # Add basic metadata
                doc_id = str(uuid.uuid4())
                for doc in documents:
                    doc.metadata.update({
                        "source": file_obj.name,
                        "document_id": doc_id
                    })
            
            # Split documents into chunks
            chunks = self.text_splitter.split_documents(documents)
            
            # Add to vector store
            self.vector_store.add_documents(chunks)
            
            # Clean up temporary file
            os.unlink(temp_path)
            
            return True
        
        except Exception as e:
            print(f"Error adding document to vector database: {e}")
            return False
    
    def add_text(self, text: str, metadata: Dict[str, Any]) -> bool:
        """
        Add text directly to the vector database
        
        Args:
            text: Text content to add
            metadata: Metadata for the text
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Create a Document object
            doc = Document(page_content=text, metadata=metadata)
            
            # Split into chunks
            chunks = self.text_splitter.split_documents([doc])
            
            # Add to vector store
            self.vector_store.add_documents(chunks)
            
            return True
        
        except Exception as e:
            print(f"Error adding text to vector database: {e}")
            return False
    
    def search(self, query: str, k: int = 5, diversity_threshold: float = 0.7) -> List[Dict[str, Any]]:
        """
        Search the vector database for relevant documents with improved diversity
        
        Args:
            query: Search query
            k: Number of results to return
            diversity_threshold: Threshold for similarity between results (lower = more diverse)
            
        Returns:
            List of dictionaries containing document content and metadata
        """
        try:
            # Начинаем отслеживать время выполнения для логгирования
            start_time = time.time()
            
            # Запрашиваем больше результатов, чем нужно, чтобы потом отфильтровать похожие
            results = self.vector_store.similarity_search_with_score(query, k=k*2)
            
            # Фильтруем результаты для обеспечения разнообразия
            filtered_results = []
            seen_content_hashes = set()
            
            for doc, score in results:
                # Создаем хеш содержимого для определения похожести
                # Используем только первые 100 символов для сравнения
                content_hash = hash(doc.page_content[:100])
                
                # Проверяем, не видели ли мы уже похожий контент
                if content_hash not in seen_content_hashes:
                    filtered_results.append((doc, score))
                    seen_content_hashes.add(content_hash)
                
                # Если у нас достаточно разнообразных результатов, останавливаемся
                if len(filtered_results) >= k:
                    break
            
            # Если после фильтрации у нас меньше результатов, чем запрошено,
            # добавляем оставшиеся результаты
            if len(filtered_results) < k:
                for doc, score in results:
                    if len(filtered_results) >= k:
                        break
                    
                    # Проверяем, нет ли уже этого документа в отфильтрованных результатах
                    if not any(doc.page_content == d.page_content for d, _ in filtered_results):
                        filtered_results.append((doc, score))
            
            # Format results
            formatted_results = []
            for doc, score in filtered_results:
                formatted_results.append({
                    "content": doc.page_content,
                    "metadata": doc.metadata,
                    "relevance_score": score
                })
            
            # Выводим информацию о времени выполнения запроса
            elapsed_time = time.time() - start_time
            print(f"Vector search completed in {elapsed_time:.2f}s, found {len(formatted_results)} results")
            
            return formatted_results
        
        except Exception as e:
            print(f"Error searching vector database: {e}")
            return []
    
    def delete_by_metadata(self, metadata_field: str, metadata_value: str) -> bool:
        """
        Delete documents from the vector database by metadata
        
        Args:
            metadata_field: Metadata field to filter by
            metadata_value: Value to match
            
        Returns:
            True if successful, False otherwise
        """
        try:
            self.vector_store.delete(
                where={metadata_field: metadata_value}
            )
            return True
        
        except Exception as e:
            print(f"Error deleting from vector database: {e}")
            return False 