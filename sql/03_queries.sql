-- ============================================================
-- 03_queries.sql — Blake Simpson (Data Analyst)
-- ============================================================
-- Target environment:
--   Warehouse : ROHAN_BLAKE_KENNETH_WH
--   Database  : CS5542_LAB5_ROHAN_BLAKE_KENNETH
--   Table     : RAW.CHUNKS  (416 rows, the only table)
--   View      : APP.CHUNKS_V (same data, app-facing)
--
-- CHUNKS_V columns:
--   EVIDENCE_ID  VARCHAR  – unique chunk key (e.g. "bm25_prf_p01_c001")
--   DOC_ID       VARCHAR  – paper identifier  (e.g. "bm25_prf")
--   SOURCE_FILE  VARCHAR  – PDF filename      (e.g. "bm25_prf.pdf")
--   PAGE         NUMBER   – page number
--   CHUNK_INDEX  NUMBER   – chunk position on page
--   CHUNK_TEXT   VARCHAR  – raw extracted text
--
-- Note: No TOKEN_COUNT column exists; we approximate it as
--       ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' ')) — word count.
-- ============================================================

USE WAREHOUSE ROHAN_BLAKE_KENNETH_WH;
USE DATABASE CS5542_LAB5_ROHAN_BLAKE_KENNETH;


-- ──────────────────────────────────────────────────────────────
-- Q1 — AGGREGATION
-- "Average Token Count per Paper"
-- Since there is no TOKEN_COUNT column, we approximate token
-- count as word count: ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' ')).
-- Groups by DOC_ID (paper) and reports chunk count + avg words.
-- ──────────────────────────────────────────────────────────────
SELECT
    DOC_ID                                              AS PAPER,
    SOURCE_FILE,
    COUNT(*)                                            AS TOTAL_CHUNKS,
    ROUND(AVG(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' '))), 1)  AS AVG_WORD_COUNT,
    SUM(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' ')))             AS TOTAL_WORDS
FROM APP.CHUNKS_V
GROUP BY DOC_ID, SOURCE_FILE
ORDER BY AVG_WORD_COUNT DESC;


-- ──────────────────────────────────────────────────────────────
-- Q2 — JOIN
-- "List chunks enriched with paper intro text"
--
-- Joins CHUNKS_V to a sub-query that identifies each paper's
-- first chunk (page 1, index 1) as a paper-header reference row.
-- This returns all chunks enriched with their paper's intro text,
-- demonstrating a self-join pattern within a single table.
-- ──────────────────────────────────────────────────────────────
WITH paper_intro AS (
    -- One representative row per paper: the very first chunk (page 1, chunk 1)
    SELECT
        DOC_ID,
        SOURCE_FILE,
        CHUNK_TEXT  AS INTRO_TEXT
    FROM APP.CHUNKS_V
    WHERE PAGE = 1
      AND CHUNK_INDEX = 1
)
SELECT
    c.DOC_ID,
    c.SOURCE_FILE,
    c.PAGE,
    c.CHUNK_INDEX,
    c.EVIDENCE_ID,
    LEFT(pi.INTRO_TEXT, 120)    AS PAPER_INTRO_SNIPPET,
    LEFT(c.CHUNK_TEXT, 200)     AS CHUNK_PREVIEW
FROM APP.CHUNKS_V       c
JOIN paper_intro        pi  ON pi.DOC_ID = c.DOC_ID
ORDER BY c.DOC_ID, c.PAGE, c.CHUNK_INDEX;


-- ──────────────────────────────────────────────────────────────
-- Q3 — COMPLEX (Window Function + Ranking)
-- "Rank papers by total content volume"
--
-- Uses RANK() OVER (ORDER BY ...) to produce a leaderboard of
-- papers by total extracted words (proxy for paper richness).
-- A second window function computes per-paper percentile.
-- ──────────────────────────────────────────────────────────────
WITH paper_stats AS (
    SELECT
        DOC_ID,
        SOURCE_FILE,
        COUNT(*)                                            AS TOTAL_CHUNKS,
        SUM(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' ')))             AS TOTAL_WORDS,
        ROUND(AVG(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' '))), 1)  AS AVG_WORDS_PER_CHUNK,
        MAX(PAGE)                                           AS MAX_PAGE
    FROM APP.CHUNKS_V
    GROUP BY DOC_ID, SOURCE_FILE
)
SELECT
    RANK() OVER (ORDER BY TOTAL_WORDS DESC)             AS CONTENT_RANK,
    DOC_ID,
    SOURCE_FILE,
    TOTAL_CHUNKS,
    TOTAL_WORDS,
    AVG_WORDS_PER_CHUNK,
    MAX_PAGE,
    ROUND(
        PERCENT_RANK() OVER (ORDER BY TOTAL_WORDS) * 100,
        1
    )                                                   AS PERCENTILE
FROM paper_stats
ORDER BY CONTENT_RANK;


-- ══════════════════════════════════════════════════════════════
-- EXTENSION — APP.DOC_SUMMARY View
-- ══════════════════════════════════════════════════════════════
-- Pre-aggregates all per-paper stats into a single view so the
-- dashboard can load a full summary in one fast query.
--
-- Columns:
--   DOC_ID, SOURCE_FILE
--   TOTAL_CHUNKS        – number of extracted chunks
--   MAX_PAGE            – last page seen (proxy for paper length)
--   TOTAL_WORDS         – sum of word counts across all chunks
--   AVG_WORDS_PER_CHUNK – average words per chunk
--   CONTENT_RANK        – rank by total word count (1 = richest)
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW APP.DOC_SUMMARY AS
WITH stats AS (
    SELECT
        DOC_ID,
        SOURCE_FILE,
        COUNT(*)                                            AS TOTAL_CHUNKS,
        MAX(PAGE)                                           AS MAX_PAGE,
        SUM(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' ')))             AS TOTAL_WORDS,
        ROUND(AVG(ARRAY_SIZE(SPLIT(CHUNK_TEXT, ' '))), 1)  AS AVG_WORDS_PER_CHUNK
    FROM APP.CHUNKS_V
    GROUP BY DOC_ID, SOURCE_FILE
)
SELECT
    DOC_ID,
    SOURCE_FILE,
    TOTAL_CHUNKS,
    MAX_PAGE,
    TOTAL_WORDS,
    AVG_WORDS_PER_CHUNK,
    RANK() OVER (ORDER BY TOTAL_WORDS DESC)  AS CONTENT_RANK
FROM stats
ORDER BY CONTENT_RANK;
