-- Chunk storage with a dense (pgvector) and a sparse (tsvector) index side by side.
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS documents (
  id          text PRIMARY KEY,
  title       text NOT NULL,
  source      text NOT NULL,
  ingested_at timestamptz NOT NULL DEFAULT now()
);

-- array_to_string is only STABLE, which a generated column rejects; joining text with a fixed separator is immutable.
CREATE OR REPLACE FUNCTION immutable_array_to_string(text[], text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT array_to_string($1, $2) $$;

CREATE TABLE IF NOT EXISTS chunks (
  id           text PRIMARY KEY,
  doc_id       text NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  doc_title    text NOT NULL,
  heading_path text[] NOT NULL DEFAULT '{}',
  ordinal      integer NOT NULL,
  text         text NOT NULL,
  -- 1024 matches voyage-3.5 (output_dimension=1024) and the hashing embedder default.
  embedding    vector(1024) NOT NULL,
  tsv          tsvector GENERATED ALWAYS AS (
                 setweight(to_tsvector('english', doc_title || ' ' || immutable_array_to_string(heading_path, ' ')), 'B') ||
                 setweight(to_tsvector('english', text), 'A')
               ) STORED
);

CREATE INDEX IF NOT EXISTS chunks_doc_id_idx ON chunks (doc_id);
CREATE INDEX IF NOT EXISTS chunks_tsv_idx ON chunks USING gin (tsv);
CREATE INDEX IF NOT EXISTS chunks_embedding_idx ON chunks USING hnsw (embedding vector_cosine_ops);
