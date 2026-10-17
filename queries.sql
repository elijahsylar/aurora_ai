-- Aurora pilot report: queries behind the published numbers
-- ===========================================================
-- Every query is read-only (SELECT). It was run against the pilot database
-- with `SET SESSION TRANSACTION READ ONLY`, data as of 2026-10-17. Each block
-- is labeled with the audit section that produced it (A§n in the page's
-- source comments).
--
-- Pilot window and exclusions, used throughout (written out in full below):
--   sessions:      id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6'
--                  AND id NOT IN (2190, 2588, 2590)
--   child tables:  session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6'
--                  AND session_id NOT IN (2190, 2588, 2590)
-- 2190, 2588 and 2590 are sessions inserted by hand to steer the rotation (A§7.15).
-- Rows with no session at all are placed in the window by timestamp.
-- Timestamps are naive local time. Inclusion is by session ID, not by clock time.
--
-- Some figures need a step after the query (regular expressions over text,
-- a permutation baseline, correlations). Those steps are described in comments
-- next to the query that feeds them, with the exact patterns used.


-- ---------------------------------------------------------------------------
-- A§7.1  Excluded model: claude-opus-4.6
-- ---------------------------------------------------------------------------
SELECT id, started_at, ended_at, painting_title IS NOT NULL AS titled
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model = 'claude-opus-4.6'
ORDER BY id;


-- ---------------------------------------------------------------------------
-- A§7.15  Excluded sessions inserted by hand (SENTINEL notes); window bounds
-- ---------------------------------------------------------------------------
SELECT id, model, started_at, ended_at, canvas_coverage, painting_title
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND notes LIKE 'SENTINEL%';

SELECT MIN(started_at), MAX(started_at)
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590);


-- ---------------------------------------------------------------------------
-- A§7.3  Pilot totals
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS sessions, COUNT(DISTINCT model) AS models
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590);

-- Sessions per model (min / median / max are taken from this list).
SELECT model, COUNT(*) AS sessions
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
GROUP BY model
ORDER BY sessions DESC;

SELECT COUNT(*) AS thoughts
FROM thoughts
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);

SELECT COUNT(*) AS thoughts_with_base
FROM thoughts
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) AND emotion = 'base';

-- Feel entries (the `emotions` table), excluding the placeholder 'base'.
SELECT COUNT(*) AS feel_entries, COUNT(DISTINCT LOWER(emotion)) AS distinct_feel_words
FROM emotions
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) AND emotion <> 'base';

-- Sleep-phase texts (the `dreams` table), reflections, sound strings, snapshots.
SELECT COUNT(*) FROM dreams
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM reflections
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM sounds
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM canvas_snapshots
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);

-- Paintings: titled sessions minus placeholder titles (titles starting with '[').
SELECT SUM(painting_title IS NOT NULL AND painting_title <> '') AS titled,
       SUM(painting_title LIKE '[%') AS placeholders
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590);

-- Sessions with no thoughts.
SELECT COUNT(*)
FROM sessions s
LEFT JOIN (SELECT session_id, COUNT(*) AS n FROM thoughts GROUP BY session_id) t
       ON t.session_id = s.id
WHERE s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590) AND t.n IS NULL;


-- ---------------------------------------------------------------------------
-- A§2.1  Reflection date range
-- ---------------------------------------------------------------------------
SELECT MIN(reflected_at), MAX(reflected_at)
FROM reflections
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);


-- ---------------------------------------------------------------------------
-- A§7.2 / A§7.15  Zero-coverage sessions
-- ---------------------------------------------------------------------------
SELECT SUM(canvas_coverage = 0) AS zero_coverage, SUM(canvas_coverage > 0) AS nonzero
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590);

-- Zero-coverage sessions by title kind (real title = explained; the rest undetermined).
SELECT CASE WHEN painting_title IS NULL OR painting_title = '' THEN 'no title'
            WHEN painting_title LIKE '[%' THEN 'placeholder'
            ELSE 'real title' END AS kind,
       COUNT(*)
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590) AND canvas_coverage = 0
GROUP BY kind;

-- Zero-coverage sessions that logged sounds / thoughts.
SELECT SUM(EXISTS(SELECT 1 FROM sounds x WHERE x.session_id = s.id)),
       SUM(EXISTS(SELECT 1 FROM thoughts t WHERE t.session_id = s.id))
FROM sessions s
WHERE s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590) AND s.canvas_coverage = 0;

-- Surviving snapshots that belong to zero-coverage sessions (16 rows; min/max coverage).
SELECT x.session_id, x.coverage, s.canvas_coverage
FROM canvas_snapshots x
JOIN sessions s ON s.id = x.session_id
WHERE s.canvas_coverage = 0 AND x.session_id BETWEEN 14 AND 3244
  AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590);


-- ---------------------------------------------------------------------------
-- A§7.4 / A§7.13 / A§7.15  Session length
-- ---------------------------------------------------------------------------
-- Durations in minutes. Post-processing: sessions with a negative duration
-- (1 row) are dropped; the median, the histogram bins (0-1, 1-5, 5-15, 15-30,
-- 30-45, 45-60, 60-70, 70-90, 90-180, >180) and the count under 5 minutes are
-- computed over the remaining 2,987 values. Sessions over 3 hours: duration > 180.
SELECT TIMESTAMPDIFF(SECOND, started_at, ended_at) / 60 AS minutes
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590) AND ended_at IS NOT NULL;

SELECT COUNT(*) AS no_end_time
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590) AND ended_at IS NULL;

SELECT id, model, started_at, ended_at
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590) AND ended_at < started_at;


-- ---------------------------------------------------------------------------
-- A§7.5  By month; sleep-phase art lexicon
-- ---------------------------------------------------------------------------
SELECT DATE_FORMAT(started_at, '%Y-%m') AS month, COUNT(*) AS sessions,
       COUNT(DISTINCT DATE(started_at)) AS active_days
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
GROUP BY month
ORDER BY month;

-- Sleep-phase texts. Post-processing: a text "matches the art lexicon" if it
-- matches (case-insensitive)
--   \b(canvas\w*|paint\w*|brush\w*|colou?r\w*|draw\w*|stroke\w*|palette\w*|art|artist\w*|artwork\w*|pixel\w*|hue\w*|sketch\w*)\b
-- The "excluding color words" figure drops colou?r\w* and hue\w* from the pattern.
-- Months are DATE_FORMAT(dreamed_at, '%Y-%m').
SELECT model, content, dreamed_at
FROM dreams
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);


-- ---------------------------------------------------------------------------
-- A§7.6  Per-model table
-- ---------------------------------------------------------------------------
SELECT model, COUNT(*) FROM thoughts
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) GROUP BY model;
SELECT model, COUNT(*) FROM emotions
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) AND emotion <> 'base' GROUP BY model;
SELECT model, COUNT(*) FROM dreams
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) GROUP BY model;
SELECT model, COUNT(*) FROM reflections
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) GROUP BY model;
SELECT model, COUNT(*) FROM sounds
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) GROUP BY model;
SELECT model, COUNT(*) FROM chats
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) GROUP BY model;

-- Mean coverage over non-zero sessions, and its n.
SELECT model, AVG(canvas_coverage) AS mean_coverage, COUNT(*) AS n_nonzero
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590) AND canvas_coverage > 0
GROUP BY model;

-- Zero-coverage sessions per model.
SELECT model, SUM(canvas_coverage = 0) AS zero_sessions
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
GROUP BY model;


-- ---------------------------------------------------------------------------
-- A§7.7  Feel words
-- ---------------------------------------------------------------------------
-- Post-processing over these rows: distinct words; words occurring once;
-- words produced by exactly one model; words produced by >= 15 models;
-- per-model top-3 entries; "stuck" entries by model.
SELECT model, LOWER(emotion) AS word
FROM emotions
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) AND emotion <> 'base';

-- Thought-steps: thoughts counted under the current feel word (base excluded).
-- Post-processing: totals per word; top 5; share of "calm" from each model;
-- per-model top word, compared with the top entry word (agreement count).
-- "feel free" counts use, over thought text, the patterns
--   \bfeel free\b            and   \bfeel(?:ing)?\s+free\b   (case-insensitive)
SELECT model, emotion, thought
FROM thoughts
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);

-- Non-affect and ambiguous words: post-processing sums the entries (rows of
-- the query below) for each of two word lists, classified by a single rater
-- without a validated coding scheme. The full lists:
--   non-affect (131 entries): during, various, low, different, lately, bright,
--     smooth, captures, incredibly, after, brings, light, weight, one, full,
--     done, order, state, accidental, significant, emotions, calms, unfinished
--   ambiguous state or situation words (1,931 entries): harmony, flow, balance,
--     purpose, connection, creativity, completion, growth, mystery, complete,
--     thirsty, awake, warm, heavy, creative, uncreative, stillness, centered,
--     grounded, safe, tension, urgency, empty, dreamy, weightless,
--     weightlessness, free, freedom, stuck, lost, accomplishment
SELECT LOWER(emotion) AS word, COUNT(*) AS entries
FROM emotions
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590) AND emotion <> 'base'
GROUP BY word
ORDER BY entries DESC;


-- ---------------------------------------------------------------------------
-- A§7.8  Base rates for selected words
-- ---------------------------------------------------------------------------
-- Post-processing: for each word w, entries = emotion rows equal to w; models
-- (as feel word) = distinct models with such rows; models (in thoughts / in
-- sleep-phase texts) = distinct models with >= 1 text matching \bw\b
-- (case-insensitive). Inputs: the emotions and thoughts queries in A§7.7 and
-- the dreams query in A§7.5.
SELECT model, emotion, occurred_at
FROM emotions
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590)
  AND LOWER(emotion) = 'weightless'
ORDER BY occurred_at;


-- ---------------------------------------------------------------------------
-- A§7.9  Titles
-- ---------------------------------------------------------------------------
-- Post-processing: drop titles starting with '['; normalize by lower-casing and
-- removing characters outside [a-z0-9 ]. Themes are counted with the patterns
--   sunset/sunrise \bsun(set|rise)   harmony \bharmon   abstract \babstract
--   serenity/serene \bseren   (case-insensitive)
-- Shared titles = normalized titles produced by >= 2 (or >= 4) distinct models.
-- Baseline = the same count after randomly shuffling the model labels across
-- titles, mean of 200 runs (random seed 1).
SELECT model, painting_title
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
  AND painting_title IS NOT NULL AND painting_title <> '';


-- ---------------------------------------------------------------------------
-- A§7.10  Color words and sound strings
-- ---------------------------------------------------------------------------
-- Color words: whole-word matches in thought text (from the thoughts query in
-- A§7.7) of red, orange, yellow, green, cyan, blue, purple, pink, white, gray,
-- grey (counted as gray), brown, magenta, lime, navy, black.
-- Sound strings: post-processing counts distinct strings, the top 12 share and
-- the top 3.
SELECT chars
FROM sounds
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590);


-- ---------------------------------------------------------------------------
-- A§7.12  Other figures
-- ---------------------------------------------------------------------------
SELECT question_key, COUNT(*)
FROM reflections
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590)
GROUP BY question_key
ORDER BY 2 DESC;

SELECT model, COUNT(*)
FROM reflections
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590)
GROUP BY model
ORDER BY 2 DESC
LIMIT 2;

-- mistral-base sleep-phase texts in its three largest sessions.
SELECT session_id, COUNT(*)
FROM dreams
WHERE model = 'mistral-base' AND session_id BETWEEN 14 AND 3244 AND session_id NOT IN (2190, 2588, 2590)
GROUP BY session_id
ORDER BY 2 DESC
LIMIT 3;

-- gemma2-9b sessions and thoughts before / from 2026-04-10.
SELECT SUM(started_at < '2026-04-10'), SUM(started_at >= '2026-04-10')
FROM sessions
WHERE model = 'gemma2-9b' AND id BETWEEN 14 AND 3244 AND id NOT IN (2190, 2588, 2590);

SELECT SUM(captured_at < '2026-04-10'), SUM(captured_at >= '2026-04-10')
FROM thoughts
WHERE model = 'gemma2-9b' AND session_id BETWEEN 14 AND 3244 AND session_id NOT IN (2190, 2588, 2590);

-- Child rows whose session row is missing (all have a session_id inside the window).
SELECT COUNT(*) FROM dreams x LEFT JOIN sessions s ON s.id = x.session_id
WHERE x.session_id BETWEEN 14 AND 3244 AND x.model <> 'claude-opus-4.6' AND s.id IS NULL;
SELECT COUNT(*) FROM sounds x LEFT JOIN sessions s ON s.id = x.session_id
WHERE x.session_id BETWEEN 14 AND 3244 AND x.model <> 'claude-opus-4.6' AND s.id IS NULL;
SELECT COUNT(*) FROM chats x LEFT JOIN sessions s ON s.id = x.session_id
WHERE x.session_id BETWEEN 14 AND 3244 AND x.model <> 'claude-opus-4.6' AND s.id IS NULL;

-- Missing session IDs inside the window: 3,231 IDs in range minus rows present.
SELECT 3244 - 14 + 1 - COUNT(*) AS missing_ids
FROM sessions
WHERE id BETWEEN 14 AND 3244;

-- Records with no session, placed in the window by timestamp (A§7.15).
SELECT COUNT(*) FROM thoughts
WHERE session_id IS NULL AND captured_at >= '2026-03-07' AND captured_at < '2026-06-15';
SELECT SUM(emotion <> 'base') AS feel_entries, SUM(emotion = 'base') AS base_rows
FROM emotions
WHERE session_id IS NULL AND occurred_at >= '2026-03-07' AND occurred_at < '2026-06-15';

-- Repeated identical thoughts within a session (extra rows).
SELECT COALESCE(SUM(n - 1), 0)
FROM (SELECT session_id, thought, COUNT(*) AS n
      FROM thoughts
      WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590)
      GROUP BY session_id, thought
      HAVING n > 1) x;

-- Thoughts containing chat control tokens.
SELECT COUNT(*)
FROM thoughts
WHERE session_id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND session_id NOT IN (2190, 2588, 2590)
  AND (thought LIKE '%<|%' OR thought LIKE '%[INST]%'
       OR thought LIKE '%</s>%' OR thought LIKE '%<end_of_turn>%');


-- ---------------------------------------------------------------------------
-- A§7.16  Example canvas images
-- ---------------------------------------------------------------------------
-- Eligibility (applied in Python to the rows of the first query): the
-- timelapse name {model}_{title.lower().replace(' ', '_')[:40]} must be
-- produced by exactly one session in the second query; exactly one saved
-- snapshot file must be time-stamped from 120 s before to 5 s after ended_at;
-- the renderer's saved final frame must match that snapshot on >= 99% of
-- pixels (difference <= 15 levels). Pick: session 3084 kept; two more drawn
-- from eligible sessions of models other than qwen, pool sorted by id,
-- random.Random(20261017) shuffle, first two from different models.
SELECT id, model, painting_title, started_at, ended_at, canvas_coverage
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
  AND painting_title IS NOT NULL AND painting_title <> '' AND painting_title NOT LIKE '[%'
  AND ended_at IS NOT NULL;

-- Title uniqueness is checked against every titled session ever recorded,
-- because a later session with the same title would overwrite the file.
SELECT id, model, painting_title
FROM sessions
WHERE painting_title IS NOT NULL AND painting_title <> '';

SELECT id, model, started_at, canvas_coverage, painting_title
FROM sessions
WHERE id IN (1208, 1941, 3084)
  AND id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590);

-- ---------------------------------------------------------------------------
-- A§7.18  Data quality: label mismatches, overlaps, daylight-saving span
-- ---------------------------------------------------------------------------
-- Records labeled with a different model from their session (feel entries
-- exclude 'base'; repeat for dreams and sounds).
SELECT COUNT(*) FROM thoughts x JOIN sessions s ON s.id = x.session_id
WHERE BINARY x.model <> BINARY s.model
  AND s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM emotions x JOIN sessions s ON s.id = x.session_id
WHERE BINARY x.model <> BINARY s.model AND x.emotion <> 'base'
  AND s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM dreams x JOIN sessions s ON s.id = x.session_id
WHERE BINARY x.model <> BINARY s.model
  AND s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590);
SELECT COUNT(*) FROM sounds x JOIN sessions s ON s.id = x.session_id
WHERE BINARY x.model <> BINARY s.model
  AND s.id BETWEEN 14 AND 3244 AND s.model <> 'claude-opus-4.6' AND s.id NOT IN (2190, 2588, 2590);

-- Overlaps and the daylight-saving span: post-processing walks these rows in
-- ID order and counts sessions whose start is more than 1 minute before the
-- previous row's end, and sessions with started_at < '2026-03-08 02:00'
-- <= ended_at.
SELECT id, started_at, ended_at
FROM sessions
WHERE id BETWEEN 14 AND 3244 AND model <> 'claude-opus-4.6' AND id NOT IN (2190, 2588, 2590)
ORDER BY id;
