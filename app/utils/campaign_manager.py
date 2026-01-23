import os
import json
from typing import Dict, Any, List, Optional
import streamlit as st
from pathlib import Path

class CampaignManager:
    """Manager for campaign state and documents"""
    
    def __init__(self, data_dir: str = "./data"):
        """
        Initialize the campaign manager
        
        Args:
            data_dir: Directory for storing campaign data
        """
        self.data_dir = data_dir
        self.campaigns_file = os.path.join(data_dir, "campaigns.json")
        self.documents_file = os.path.join(data_dir, "campaign_documents.json")
        
        # Ensure data directory exists
        os.makedirs(data_dir, exist_ok=True)
    
    def save_campaign_state(self, campaign_state: Dict[str, Any]) -> bool:
        """
        Save campaign state to file
        
        Args:
            campaign_state: Dictionary containing campaign state
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Load existing campaigns
            campaigns = self.load_campaigns()
            
            # Update or add current campaign
            campaign_name = campaign_state.get("campaign_name", "Default Campaign")
            campaigns[campaign_name] = campaign_state
            
            # Save to file
            with open(self.campaigns_file, 'w', encoding='utf-8') as f:
                json.dump(campaigns, f, indent=2, ensure_ascii=False)
            
            return True
        except Exception as e:
            print(f"Error saving campaign state: {e}")
            return False
    
    def load_campaigns(self) -> Dict[str, Dict[str, Any]]:
        """
        Load all campaigns from file
        
        Returns:
            Dictionary of campaigns
        """
        if not os.path.exists(self.campaigns_file):
            return {}
        
        try:
            with open(self.campaigns_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading campaigns: {e}")
            return {}
    
    def load_campaign_state(self, campaign_name: str) -> Dict[str, Any]:
        """
        Load a specific campaign state
        
        Args:
            campaign_name: Name of the campaign to load
            
        Returns:
            Campaign state dictionary
        """
        campaigns = self.load_campaigns()
        return campaigns.get(campaign_name, {})
    
    def save_document_info(self, document_info: Dict[str, Any]) -> bool:
        """
        Save document information to file
        
        Args:
            document_info: Dictionary containing document information
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Load existing documents
            documents = self.load_documents()
            
            # Add new document
            doc_id = document_info.get("id", str(len(documents) + 1))
            document_info["id"] = doc_id
            documents[doc_id] = document_info
            
            # Save to file
            with open(self.documents_file, 'w', encoding='utf-8') as f:
                json.dump(documents, f, indent=2, ensure_ascii=False)
            
            return True
        except Exception as e:
            print(f"Error saving document info: {e}")
            return False
    
    def load_documents(self) -> Dict[str, Dict[str, Any]]:
        """
        Load all document information from file
        
        Returns:
            Dictionary of document information
        """
        if not os.path.exists(self.documents_file):
            return {}
        
        try:
            with open(self.documents_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading documents: {e}")
            return {}
    
    def get_campaign_documents(self, campaign_name: str) -> List[Dict[str, Any]]:
        """
        Get all documents for a specific campaign
        
        Args:
            campaign_name: Name of the campaign
            
        Returns:
            List of document information dictionaries
        """
        documents = self.load_documents()
        return [doc for doc in documents.values() if doc.get("campaign_name") == campaign_name]
    
    def delete_document(self, document_id: str) -> bool:
        """
        Delete a document
        
        Args:
            document_id: ID of the document to delete
            
        Returns:
            True if successful, False otherwise
        """
        try:
            documents = self.load_documents()
            if document_id in documents:
                del documents[document_id]
                
                # Save updated documents
                with open(self.documents_file, 'w', encoding='utf-8') as f:
                    json.dump(documents, f, indent=2, ensure_ascii=False)
                
                return True
            return False
        except Exception as e:
            print(f"Error deleting document: {e}")
            return False 