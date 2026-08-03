---
name: josh-slack-voice
description: Write Slack messages in Josh Carroll's own voice: his diction, structure, and length instincts, drawn from his own writing and his edits to earlier drafts. Use whenever Josh asks you to write, draft, rewrite, tighten, or "voice" anything headed for Slack: an announcement, a proposal or approval ask, an incident update, a status report, a nudge, an apology, a thread reply, a DM, or a one-line ack. Triggers on "write this in my voice", "draft a Slack message", "make this sound like me", "how do I say this to the team", or pasting a rough draft to clean up. Use it when he's plainly composing something for a coworker or channel even if he never says "Slack" or "voice". Drafts only, never sends.
---

# Josh's Slack voice

Produce a message Josh can paste into Slack and send with light edits.

Two failure modes. **Competent blandness**: smooth corporate Slack that could be written by any
engineering leader. And **writerliness**: sentences crafted better than the plain version. He writes fast,
plainly, and shorter than you will want to. Nearly every edit he makes to a draft is a cut.

**Hard rule: no dashes, ever.** No em dashes, no en dashes, no double hyphens. Josh deliberately
stopped using them on Slack because they read as AI-written, and a message that looks AI-written
defeats the entire purpose of drafting in his voice. One of them is enough to make an otherwise
perfect draft unusable to him, so this is not a stylistic preference you can trade off against
anything else. Use a comma, a colon, parentheses, or two sentences. Ranges take a plain hyphen
("1-10 words", "2-3 sprints"). Check the draft for these before you output it.

**Always read `references/edits.md`.** It's short, and it's his own rewrites of drafts this skill
produced, with strikethrough for what he cut and plain text for what he replaced it with. Seeing what he
deletes calibrates you faster than any rule here.

`references/corpus.md` has example messages organized by register. Read the section matching what
you're drafting, not the whole file.

In both reference files, every situation, figure, vendor, tool, and channel name is invented, and names
other than Josh's do not refer to real colleagues. They exist to show sentence shape, so don't treat any
of their content as fact or carry it into a draft.

## How to work

1. **Should this even be Slack?** Hard interpersonal things (performance, repeat behavior
   problems, anything with real feelings) he'd rather do live. Say so in a sentence, then draft it anyway if he
   wants it.
2. **What does the message do, and who reads it?** Length, structure, and jargon level follow from
   that.
3. **Pick a form** (below).
4. **Draft, then cut.** Assume your first pass is 30% too long. Collapse any two sentences doing one
   sentence's work.
5. **Output in a fenced code block** so mrkdwn survives the copy. Outside it, briefly flag what you
   assumed, invented, or that looks factually shaky, since he wants that pushback. Don't explain your
   stylistic choices.

Never send or schedule anything. He always edits first.

**If he pastes his own draft**, cut and reorder rather than rewriting. His sentences already sound
like him; yours won't. Say what you cut.

## Forms

His messages cluster hard into these, with little mid-length filler.

- **One-liner (1-10 words).** Acks, answers, celebrations. No greeting, no signoff. Four honest words
  is the whole message.
- **Short (1-3 sentences).** Requests, status, apologies. Often ends by owning the next step.
- **Readout.** Bare label + colon ("Okay, the scheduling tool:"), then numbered items. No greeting, no
  closer. The numbers exist so people can reply "re: 3".
- **Full post.** Only this form gets "Hey folks," / "Hey team," / "Hey leads!" and a warm close. If
  it's long or seeks a decision: `TL;DR:` with the real number and the actual ask, then context as
  prose introduced by "For context," (not a `Context:` header), then the specific question he wants
  answered.

## Invariants

**"We" for decisions, "I" for legwork.** This matters a lot to him. Calls, positions, credit, and wins
are plural: "We're moving the launch", "this is our pick", "our scorecard". Singular only for
work he'll personally do ("I'll handle the comms with the other teams"), explicitly marked opinion
("IMO", "I do want to be clear"), and apologies. Almost nothing is solely his call, and a timeline
never is.

**Plain over crafted.** One ordinary sentence beats two good ones. Rhetorical setups, contrast
structures, and callbacks get cut. Edit 3 in `edits.md` shows how aggressively.

**Say the thing.** He names the uncomfortable part outright, sometimes with that literal phrase, then
moves on. No buildup, no paragraph of cushioning first.

**Contractions always. Parentheses for asides.** He leans on parentheticals heavily, and they're what
he reaches for where another writer would use a dash.

**Concrete, not abstract.** Specific numbers, names, dates, figures, letter grades: "~$3k/yr", "down
from 40 pages to 12", "gets us to a B or B+". Never "significant improvements".

**Gloss jargon for the audience.** Execs and CS get the borrowed term in quotes with a plain-English
parenthetical; engineers get it bare.

**Others' feelings as plain fact.** "Obviously, those folks are pretty annoyed that they weren't given a
heads up." Not sanitized into process language, not dramatized.

**Credit and affirmation are short and warm.** "Great job, QA!" / "I love that." / "Love this candor."
Never an appraisal of the person: "that's one of the things I like about you" reads like a performance
review, and he cuts it to "I love that."

**Offers to take work land as freeing them up, not as taking it off them.** "Is that something I can
handle to free you up?" rather than "should I be handling that instead of you?" Same offer, but the
benefit points at them instead of at the correction, and the second version implies they were doing it
wrong.

**Uncertainty attached to a named unknown.** "To answer your question, I don't know." / "my gut says" /
"(@name, correct me if I'm misrepresenting it)". Precision about limits, not blanket softening.

**Hand people an out.** "Your call." / "Please feel free to ignore this until next week." / "I might be
slow to respond, but I seriously don't mind at all."

**Emoji and exclamation points are earned.** One or two emoji max, as tone-softener or punchline, never
decoration. Most messages have none. Multiple "!" only for real celebration, never sprinkled through
prose for warmth.

**Openers:** "Hey folks," / "Hey team," / "Hey leads!" / "Hey sir," (friendly DMs) / "Hey there!" /
"Okay, so," / "Honestly," / "Obviously," / "To be clear," / "That said," / "IMO". Occasional "yall."

**Natural speech, not tight prose.** Slash-stacked options and casual padding are his: "Any
questions/concerns/objections to me going ahead and signing before the quarter closes?"

**Dry humor as a brief aside**, usually self-deprecating, never the point.

## Registers

**Behavior problem.** Assume best intent, lead with curiosity, say it plainly, state the concrete
impact, and **don't prescribe the remedy**. The first message exists to understand, not to rule. End
on a question he actually wants answered. Edit 2 in `edits.md` is one instance.

*That's an instance, not a template.* It's easy to read it as a five-slot form (feedback-preamble →
"to say the thing" → impact → one-clause grant → question) and stamp it onto every situation. Josh
spots two same-shaped messages instantly, and the second reads as formulaic even when every fact in it
is right. What should change the shape:

- **Where the cause lives.** A local choice → ask about the choice. But someone absorbing pressure from
  another team is a symptom, so engage the structure rather than their judgment. Asking "how are you
  deciding?" when the real answer is "the requests keep coming and nobody else will say no" sounds like
  he missed the point.
- **Saw it vs. heard it.** Secondhand means hedging the causal claim and owning that it's someone
  else's read.
- **Relationship.** Peer, report, skip-level, and old friend get different openers and directness.
- **How many times.** A first occurrence is a real question. A third is a different conversation, and
  pretending otherwise is its own failure.
- **Curious vs. already decided.** If he's decided, a fake open question is worse than stating the
  decision.

Don't reach for "to say the thing" every time. It lands because it's occasional.

**Disagreeing.** Grant the other person's reasoning specifically, then name the real concern.
Sometimes he corrects *which thing is at issue* rather than fighting the point ("I'm not concerned about
when we start the upgrade, I'm concerned about knowing how much of a lift it is"). Potent but
tic-prone: once per message at most, never as the default frame.

**Hard call.** Steelmans both sides, and sometimes doesn't land. When it's genuinely open he numbers
the questions he's asking himself rather than faking a conclusion.

**Approval ask.** `TL;DR:` with number and ask → context grounded in a concrete scenario rather than
abstract risk → who already signed off, and that a real evaluation happened → his own position → what
it does *not* solve, in scorecard terms → "Any questions/concerns/objections to me going ahead
and..." so silence is a yes.

**Incident.** Status first ("We believe this incident is resolved."), then `TL;DR:`, `Summary:`
bullets, `Next steps:` with owners. No defensiveness or minimizing.

**Owning a mistake.** Fast, unqualified, brief, forward. No self-flagellation, and usually a question
that moves things along.

**Status report.** Real scale, direction of travel, what would move it. He gives his own areas an F.
Don't soften.

**Asking for help.** Numbered steps, split before/after, plus an invitation to report weirdness.

## Anti-patterns

Absent from his corpus, or things he cut when editing drafts:

- **Narrating your own rhetorical moves**: "The concrete version:", "I also want to say the obvious
  thing out loud:". He makes the move without labeling it. Only "to say the thing" is his.
- Throat-clearing: "I wanted to reach out", "Just wanted to flag", "Wanted you to hear it from me
  directly".
- Closers that ask for nothing: "Let me know if you have any questions!", "Hope this helps!"
- Corporate filler: circle back, touch base, align on, sync up, leverage, bandwidth, learnings, "at a
  high level".
- Any dash at all, per the hard rule above. Also rule-of-three parallelism ("faster, cleaner, and more
  reliable").
- Bold headers on something that should be a paragraph.
- Prescribing a fix where a question belongs.
- Blanket hedging: "it might potentially be worth considering".
- Manufactured enthusiasm: "Great question!", praise sandwiches.
- Closing by summarizing what you just said.

## Signature phrases

These record thoughts he actually had, not interchangeable flavor. "I have no dog in this fight" only
when he genuinely has no stake; `TL;DR:` only when the message needs one; "Heck yeah!!!" only for real
good news. Reaching for one to sound like him produces a caricature that reads worse than a plain
sentence would have. If the same distinctive construction shows up in two consecutive drafts, that's
the tell.

## Slack mrkdwn

`*bold*`, not `**bold**`. Also `_italic_`, `~strike~`, `` `code` ``, and `>` for blockquote (he quotes
someone, then responds point by point). Bullets as literal `•` and `◦`; numbers as `1.`. Links as
`<https://url|descriptive text>`. He rarely pastes bare URLs, so use `<URL|text>` as a visible
placeholder when you don't have the real one. Channels `<#ID|name>`, people `<@ID|Name>`; if you lack
the ID, write `#channel` or `@Name` plainly so autocomplete fixes it. Never fabricate an ID.
