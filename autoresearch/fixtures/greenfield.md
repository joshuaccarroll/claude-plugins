# Cards About Anything — MVP

## Context

A web app where users type in any topic and AI generates a custom deck of "Cards Against Humanity"-style prompt and response cards. Players can then play a game with friends using the generated deck. The MVP should cover deck generation and a basic multiplayer game loop.

## Tech Stack

- Frontend: React + Vite + Tailwind
- Backend: Node.js + Express
- AI: OpenAI API for card generation
- Real-time: WebSocket for multiplayer game state
- No database for MVP — game state lives in memory, decks are ephemeral

## Plan

### Step 1: Project scaffolding

Set up the monorepo structure:
- `client/` — React app via Vite
- `server/` — Express API + WebSocket server
- Shared types between client and server

### Step 2: Card generation API

Build a `POST /api/generate-deck` endpoint.

- Accept a topic string and optional card count (default 40 white, 10 black)
- Call OpenAI to generate prompt cards (black, with blanks) and response cards (white)
- Return the deck as JSON
- Each card has an ID, text, and type (black/white)

The prompt engineering is important here. Cards need to be funny, edgy but not offensive, and the blanks in black cards need to work grammatically with white card responses.

### Step 3: Game lobby

Build a lobby system where players can create and join games.

- Create game: generates a room code, creator picks a topic, deck is generated
- Join game: enter room code, pick a display name
- Lobby shows connected players, game creator can start when ready
- WebSocket for real-time player list updates

### Step 4: Game loop

Implement the core game mechanics:

**Round flow:**
1. One player is the "judge" (rotates each round)
2. A black card is revealed to all players
3. Non-judge players pick a white card from their hand (7 cards)
4. Once all submissions are in, judge sees them anonymously and picks a winner
5. Winner gets a point, next round starts

**State management:**
- Server manages authoritative game state
- Client receives state updates via WebSocket
- Handle disconnections gracefully

### Step 5: Scoring and game end

- Track points per player
- Game ends after all black cards are used or a configurable number of rounds
- Show final scoreboard with winner

### Step 6: Basic UI

- Landing page: topic input + "Generate & Play" button
- Lobby: player list, room code display, start button
- Game view: current black card, hand of white cards, submission area
- Judge view: anonymized submissions, pick winner button
- Scoreboard

Keep it simple — cards should look like actual playing cards (white with black text, rounded corners). Black cards are black with white text.

### Step 7: Polish and deploy

- Add loading states during deck generation
- Handle edge cases (player leaves mid-game, not enough players)
- Deploy frontend to Vercel, backend to Railway or Fly.io
- Add a "play again with same deck" option
