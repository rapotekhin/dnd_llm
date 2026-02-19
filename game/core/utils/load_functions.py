# Func for load files with different formats
from typing import List
import json

def load_jsonl_file(file_path: str) -> List[dict]:
    with open(file_path, 'r', encoding='utf-8') as f:
        return [json.loads(line) for line in f]