# Fix Slack Formatting Markup Leaking into Voice Output

## Context

When the voice assistant reads Slack messages aloud, raw formatting markup leaks through to the TTS output. For example, `<@U12345>` is read as "at sign U 1 2 3 4 5" instead of the user's name, `*bold*` is read as "star bold star", and `:thinking:` is read as "colon thinking colon".

The root cause is that messages flow from the Slack API through `slack-read-service.ts` → `tool-handler.ts` → `voice-session.ts` → OpenAI Realtime API with no formatting step. The system prompt tells the AI to "naturally handle Slack formatting" but TTS can't reliably do this.

## Plan

### Step 1: Create a message formatting utility

Create `src/message-formatter.ts` with a `formatMessageForVoice()` function.

Handle these patterns:
- User mentions `<@USERID>` → resolve to display name via userCache, fallback to "someone"
- Channel mentions `<#CID|name>` → "the [name] channel"
- URLs `<https://...|label>` → just the label, or "a link" if no label
- Bold `*text*`, italic `_text_`, strikethrough `~text~` → strip markers
- Code backticks → strip markers, keep content
- Emoji shortcodes `:name:` → strip entirely
- Handle nested and malformed markup gracefully

### Step 2: Integrate into slack-read-service

Modify `getMessageDetail()` and `getRecentMessages()` in `slack-read-service.ts` to call `formatMessageForVoice()` on message text before returning.

The `userCache` parameter is already available in these functions so resolving mentions should be straightforward.

### Step 3: Update the system prompt

In `tool-handler.ts`, update the system prompt instruction from telling the AI to handle formatting itself to telling it the text is already cleaned up.

### Step 4: Test

- Unit tests for `formatMessageForVoice()` covering all markup patterns
- Integration test: verify `getMessageDetail()` returns clean text
- Manual test: send a message with markup, ask the assistant to read it
