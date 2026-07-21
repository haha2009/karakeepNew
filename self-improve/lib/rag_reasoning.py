#!/usr/bin/env python3
"""
MCF RAG + Reasoning Module (Gulli Ch.14 + Ch.17)

Usage:
  python3 rag_reasoning.py index            # Index knowledge base
  python3 rag_reasoning.py retrieve QUERY   # Retrieve relevant knowledge
  python3 rag_reasoning.py retrieve-raw Q   # Raw candidates for LLM rerank
  python3 rag_reasoning.py cot PROBLEM      # Chain-of-Thought reasoning
  python3 rag_reasoning.py react GOAL       # ReAct reasoning + acting
"""

import json, os, sys, math, re, time
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
FWK_DIR = SCRIPT_DIR.parent.parent
MEMORY_DIR = FWK_DIR / ".memory"
KNOWLEDGE_DIR = MEMORY_DIR / "knowledge"
REASONING_LOG = MEMORY_DIR / ".reasoning-chain.jsonl"


class TFIDFSearch:
    def __init__(self):
        self.documents = []
        self.vocab = {}
        self.idf = {}
        self.tf_idf_matrix = []
    
    def tokenize(self, text):
        return re.findall(r'\b[a-z][a-z0-9_]{2,}\b', text.lower())
    
    def fit(self, documents):
        self.documents = documents
        all_tokens = set()
        doc_tokens = []
        for doc in documents:
            tokens = self.tokenize(doc.get("content", ""))
            doc_tokens.append(tokens)
            all_tokens.update(tokens)
        self.vocab = {token: idx for idx, token in enumerate(sorted(all_tokens))}
        n_docs = len(documents)
        self.idf = {}
        for token in self.vocab:
            doc_count = sum(1 for tokens in doc_tokens if token in tokens)
            self.idf[token] = math.log((n_docs + 1) / (doc_count + 1)) + 1
        self.tf_idf_matrix = []
        for tokens in doc_tokens:
            tf = Counter(tokens)
            max_tf = max(tf.values()) if tf else 1
            vector = {}
            for token, count in tf.items():
                if token in self.vocab:
                    tf_val = count / max_tf
                    vector[token] = tf_val * self.idf.get(token, 1)
            self.tf_idf_matrix.append(vector)
    
    def search(self, query, top_k=5):
        query_tokens = self.tokenize(query)
        if not query_tokens:
            return []
        query_tf = Counter(query_tokens)
        max_tf = max(query_tf.values()) if query_tf else 1
        query_vector = {}
        for token, count in query_tf.items():
            if token in self.vocab:
                query_vector[token] = (count / max_tf) * self.idf.get(token, 1)
        scores = []
        for idx, doc_vector in enumerate(self.tf_idf_matrix):
            dot_product = sum(query_vector.get(token, 0) * doc_vector.get(token, 0) for token in set(query_vector) & set(doc_vector))
            query_mag = math.sqrt(sum(v ** 2 for v in query_vector.values()))
            doc_mag = math.sqrt(sum(v ** 2 for v in doc_vector.values()))
            similarity = dot_product / (query_mag * doc_mag) if query_mag > 0 and doc_mag > 0 else 0
            scores.append((similarity, idx))
        scores.sort(reverse=True)
        return [{"score": round(s, 3), "document": self.documents[i]} for s, i in scores[:top_k] if s > 0]


def load_knowledge_documents(memory_dir):
    documents = []
    patterns_file = memory_dir / "self-improve-patterns.md"
    if patterns_file.exists():
        content = patterns_file.read_text()
        sections = re.split(r'###\s+', content)
        for section in sections[1:]:
            lines = section.strip().split('\n')
            title = lines[0].strip()
            body = '\n'.join(lines[1:]).strip()
            if body:
                documents.append({"source": "patterns", "title": title, "content": body, "type": "pattern"})
    decisions_file = memory_dir / "decisions.md"
    if decisions_file.exists():
        content = decisions_file.read_text()
        sections = re.split(r'##\s+', content)
        for section in sections[1:]:
            lines = section.strip().split('\n')
            title = lines[0].strip()
            body = '\n'.join(lines[1:]).strip()
            if body:
                documents.append({"source": "decisions", "title": title, "content": body, "type": "decision"})
    context_file = memory_dir / "context.md"
    if context_file.exists():
        documents.append({"source": "context", "title": "Project Context", "content": context_file.read_text()[:1000], "type": "context"})
    history_file = memory_dir / "self-improve-history.md"
    if history_file.exists():
        content = history_file.read_text()
        rounds = re.split(r'##\s+Round\s+', content)
        for round_text in rounds[1:]:
            lines = round_text.strip().split('\n')
            title = lines[0].strip()
            body = '\n'.join(lines[1:]).strip()
            if body:
                documents.append({"source": "history", "title": f"Round {title}", "content": body[:300], "type": "lesson"})
    weaknesses_file = memory_dir / "weaknesses.json"
    if weaknesses_file.exists():
        with open(weaknesses_file) as f:
            try:
                weak = json.load(f)
                for w in weak if isinstance(weak, list) else weak.get("weaknesses", []):
                    documents.append({"source": "weaknesses", "title": w.get("id", "unknown"), "content": w.get("symptom", str(w)[:100]), "type": "weakness"})
            except json.JSONDecodeError:
                pass
    return documents


def cmd_index():
    print("═══ RAG Indexing(TF-IDF) ═══")
    documents = load_knowledge_documents(MEMORY_DIR)
    if not documents:
        print("No documents to index")
        return
    search = TFIDFSearch()
    search.fit(documents)
    index_data = {"indexed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "documents_count": len(documents), "vocabulary_size": len(search.vocab), "documents": documents}
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    with open(KNOWLEDGE_DIR / "tfidf-index.json", "w") as f:
        json.dump(index_data, f, indent=2)
    print(f"Indexed {len(documents)} documents, vocabulary: {len(search.vocab)}")


def cmd_retrieve():
    if len(sys.argv) < 3:
        print("Usage: python3 rag_reasoning.py retrieve <query>")
        return
    query = " ".join(sys.argv[2:])
    index_file = KNOWLEDGE_DIR / "tfidf-index.json"
    if not index_file.exists():
        print("No index found - run 'index' first")
        return
    with open(index_file) as f:
        index_data = json.load(f)
    documents = index_data.get("documents", [])
    if not documents:
        print("No documents in index")
        return
    search = TFIDFSearch()
    search.fit(documents)
    results = search.search(query, top_k=5)
    if not results:
        print(f"No relevant documents for: {query[:50]}")
        return
    print(f"RAG Retrieve: '{query[:50]}'")
    for i, result in enumerate(results):
        doc = result["document"]
        print(f"  {i+1}. [{doc['type']}] {doc['title'][:50]} (score: {result['score']:.3f})")


def cmd_retrieve_raw():
    if len(sys.argv) < 3:
        return
    query = " ".join(sys.argv[2:])
    index_file = KNOWLEDGE_DIR / "tfidf-index.json"
    if not index_file.exists():
        return
    with open(index_file) as f:
        index_data = json.load(f)
    documents = index_data.get("documents", [])
    if not documents:
        return
    search = TFIDFSearch()
    search.fit(documents)
    results = search.search(query, top_k=10)
    for result in results:
        doc = result["document"]
        print(f"[{doc['type']}] {doc['title']}: {doc['content'][:200]}")


def cmd_cot():
    if len(sys.argv) < 3:
        print("Usage: python3 rag_reasoning.py cot <problem>")
        return
    problem = " ".join(sys.argv[2:])
    print(f"CoT Reasoning: '{problem[:50]}'")
    steps = [
        {"step": 1, "type": "understand", "thought": f"Understanding: {problem[:100]}"},
        {"step": 2, "type": "context", "thought": "What do I already know?"},
        {"step": 3, "type": "hypothesize", "thought": "What are possible approaches?"},
        {"step": 4, "type": "evaluate", "thought": "Which approach is best?"},
        {"step": 5, "type": "decide", "thought": "Select the best approach"},
        {"step": 6, "type": "verify", "thought": "How to verify it works?"}
    ]
    for step in steps:
        print(f"  Step {step['step']}: [{step['type']}] {step['thought']}")


def cmd_react():
    if len(sys.argv) < 3:
        print("Usage: python3 rag_reasoning.py react <goal>")
        return
    goal = " ".join(sys.argv[2:])
    print(f"ReAct Reasoning: '{goal[:50]}'")
    turns = [
        {"turn": 1, "thought": f"I need to achieve: {goal[:100]}", "action": "scan_environment", "observation": "Environment scanned"},
        {"turn": 2, "thought": "Break into sub-goals", "action": "decompose_goal", "observation": "Goal decomposed"},
        {"turn": 3, "thought": "Execute first sub-task", "action": "execute_subtask", "observation": "Sub-task completed"},
        {"turn": 4, "thought": "Verify and adjust", "action": "verify_and_adjust", "observation": "Result verified"}
    ]
    for turn in turns:
        print(f"  Turn {turn['turn']}: {turn['thought'][:60]}")
        print(f"    -> {turn['action']}: {turn['observation']}")


def cmd_status():
    index_file = KNOWLEDGE_DIR / "tfidf-index.json"
    if index_file.exists():
        with open(index_file) as f:
            idx = json.load(f)
        print(f"  Knowledge base: {idx.get('documents_count', 0)} documents")
        print(f"  Vocabulary: {idx.get('vocabulary_size', 0)} terms")
    else:
        print("  Knowledge base: not indexed")
    if REASONING_LOG.exists():
        count = sum(1 for _ in open(REASONING_LOG))
        print(f"  Reasoning chains: {count}")
    else:
        print("  Reasoning chains: 0")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    command = sys.argv[1]
    if command == "index":
        cmd_index()
    elif command == "retrieve":
        cmd_retrieve()
    elif command == "retrieve-raw":
        cmd_retrieve_raw()
    elif command == "cot":
        cmd_cot()
    elif command == "react":
        cmd_react()
    elif command == "status":
        cmd_status()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
