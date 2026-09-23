"""Resolve the production runtime; installation tests may supply a copied package."""
import os
from pathlib import Path
import sys
ROOT = Path(os.environ.get("KNOWLEDGE_RUNTIME", Path(__file__).resolve().parents[3] / "plugins/knowledge/scripts"))
sys.path.insert(0, str(ROOT))
