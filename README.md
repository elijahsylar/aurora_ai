# Aurora: from pattern engine to blank-slate agent

A static site about the evolution of Aurora, a research platform that gives a program a canvas and a small set of commands and records what it does. The main page follows the system in six chapters, from a generative pattern engine, to language models choosing every stroke, to an agent that has to learn what its actions do. Each chapter states what it revealed and cites its evidence.

The appendix is the pilot report and audit: the March to June 2026 pilot of 26 models, the dataset it produced, an audit of that dataset and of earlier claims about it, and the SQL behind its numbers.

Author: Elijah Sylar Camp.

## Folder layout

- `index.html`: the main page.
- `style.css`, `motion.js`: the site's styles and scripts (no third-party requests).
- `img/`: the main page's figures; `img/v3/` holds the panels for the chapter 6 comparison slider.
- `data/`: the recorded replay of one rebuild session, used by the chapter 5 player.
- `fonts/`: IBM Plex Sans and IBM Plex Mono, under the SIL Open Font License (license files included).
- `pilot/`: the appendix. `pilot/index.html` is the pilot report and audit, `pilot/queries.sql` the read-only SQL behind its numbers, `pilot/figures/` its canvases and charts.
- `queries.sql`, `figures/`: copies kept at their earlier addresses, so old links still work. Old links to sections of the report (for example `#limitations`) are forwarded to the appendix.

## Code and data

The code and the data are private. Both are available on request for review.
