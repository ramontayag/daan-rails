---
shaping: true
---

# Documents — Shaping

## Source

> In Daan, I want to be able to see plans made with any agent in HTML. For comparison, in claude or CLI-based AI workflows, I have them write the plan in a markdown file, and I open it in a markdown -> HTML viewer so I can read mermaid diagrams easily. I want this to be built-in in Daan. So let's say I tell an agent I want to make a plan with them, perhaps they write the markdown somewhere and then display it to me via the UI. But what if there are many documents to view? And where is this document? They have their own workspace, and I won't necessarily have access to that workspace, so maybe it should live in Daan's database, like Slack's canvases do.

---

## Problem

When working with agents on planning tasks, the resulting markdown documents (often containing Mermaid diagrams) live somewhere inaccessible — either in an agent's workspace or a local CLI directory. There's no built-in way to view them rendered in the Daan UI, and no central place to find or manage them.

## Outcome

Agents can create and update rich documents (markdown + Mermaid) that are stored in Daan's database and rendered as HTML in the UI — accessible from any agent's thread, browsable, and persistent.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | Agents can write/update markdown documents (inc. Mermaid) to a persistent store | Core goal |
| R1 | Documents render as HTML (Mermaid diagrams rendered, not raw text) | Core goal |
| R2 | Human can open a document from within a chat thread | Must-have |
| R3 | Documents are scoped to a thread; browsable via a panel icon (like task list / costs) | Must-have |
| R4 | Agent creates/updates documents via an explicit tool call | Must-have |
| R5 | Documents have a title and are associated with the thread | Must-have |
| R6 | Single version per document (overwrite); architecture doesn't preclude versioning later | Must-have |
| R7 | Agent can create multiple documents in one thread | Must-have |
| R8 | Clicking a doc (from panel or agent message link) opens a full-screen modal | Must-have |
| R9 | Modal has an X to close and return to previous view; works on mobile and desktop | Must-have |

---

## A: DB-backed documents with tool creation and modal viewer

| Part | Mechanism | Flag |
|------|-----------|:----:|
| A1 | `Document` model: `title`, `body` (markdown), `chat_id` | |
| A2 | Redcarpet renders markdown → HTML; Mermaid.js renders `mermaid` fenced blocks client-side | |
| A3 | Documents panel: lists docs for current thread; icon shows count badge, updates via Turbo Stream broadcast on create/update | |
| A4 | Document show page renders full-screen; X links to `params[:return_to_uri]` (set by chat view) | |
| A5 | Agent message links to `/documents/:id?return_to_uri=...`; standard Turbo Frame navigation | |
| A6 | Agent tools: `create_document(title, body)` → returns doc id; `update_document(id, body)` → overwrites body | |
| A7 | Shallow routes: top-level `resources :documents` for show; `resources :chats, shallow: true { resources :documents }` for index/create | |

---

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | Agents can write/update markdown documents to a persistent store | Core goal | ✅ |
| R1 | Documents render as HTML with Mermaid diagrams | Core goal | ✅ |
| R2 | Human can open a document from within a chat thread | Must-have | ✅ |
| R3 | Documents scoped to thread; browsable via panel icon | Must-have | ✅ |
| R4 | Agent creates/updates via explicit tool call | Must-have | ✅ |
| R5 | Documents have a title and are associated with the thread | Must-have | ✅ |
| R6 | Single version; architecture doesn't preclude versioning later | Must-have | ✅ |
| R7 | Agent can create multiple documents in one thread | Must-have | ✅ |
| R8 | Clicking a doc opens full-screen modal | Must-have | ✅ |
| R9 | Modal has X to close; works on mobile and desktop | Must-have | ✅ |

**Selected shape: A**
