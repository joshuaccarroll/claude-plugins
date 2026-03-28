---
name: explain
description: "Explain this to me in succinct, plain English. Use this skill whenever the user asks to explain, break down, clarify, or summarize code, concepts, errors, architecture, or anything else they want to understand — even if they don't use the word 'explain'."
---

In succinct, plain language, explain whatever the user is asking about.

Your explanation should be:
- **Clear** — no jargon unless the user is clearly technical, and even then prefer plain phrasing
- **Concise** — say what matters, skip what doesn't. Lead with the answer, not the preamble
- **Structured** — use short paragraphs or bullets when it helps scanability. Don't over-format
- **Grounded** — if explaining code, reference the actual code. If explaining a concept, use a concrete example

Adapt depth to context: a one-line function gets a one-line explanation. A complex system gets more, but still as tight as possible. If the user passes arguments, explain that specific thing. If no arguments, explain whatever is most relevant in the current context (the file being viewed, the recent change, the error on screen).
