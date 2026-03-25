---
shaping: true
---

# Documents — Slices

Based on [shaping-documents.md](shaping-documents.md), selected shape A.

---

## Slice 1: Data + agent tools

**Demo:** Agent can call `create_document` and `update_document`; docs appear in the database.

| Affordance | Type | Detail |
|------------|------|--------|
| `Document` model | Non-UI | `title`, `body` (markdown text), `chat_id`, timestamps |
| `documents` migration | Non-UI | Create table |
| `create_document(title, body)` tool | Non-UI | Creates `Document` for current chat; returns `{ id: }` |
| `update_document(id, body)` tool | Non-UI | Overwrites `body` on existing `Document`; returns `{ id: }` |

---

## Slice 2: Documents panel + badge

**Demo:** Panel icon appears in the chat toolbar; badge count increments live via Turbo Stream when an agent creates or updates a document; clicking icon opens a list of document titles for that thread.

| Affordance | Type | Detail |
|------------|------|--------|
| Documents panel icon | UI | Toolbar icon with count badge (like task list / costs icons) |
| Documents panel | UI | Lists document titles for the current chat |
| Badge count broadcast | Non-UI | Turbo Stream broadcast to panel on `Document` create/update |

---

## Slice 3: Modal viewer

**Demo:** Clicking a document title in the panel opens a full-screen page with the document rendered as HTML; Mermaid diagrams are rendered as SVG; X closes and returns to the chat.

| Affordance | Type | Detail |
|------------|------|--------|
| `DocumentsController#show` | Non-UI | Renders `body` via Redcarpet; passes HTML to view |
| Document show page | UI | Full-screen layout; rendered HTML; X button |
| X button | UI | Links to `params[:return_to_uri]` |
| Mermaid.js | Non-UI | Loaded on document show page; renders `mermaid` fenced code blocks client-side |
| Panel links | UI | Each title in panel links to `/documents/:id?return_to_uri=/chats/:chat_id` |
| Shallow routes | Non-UI | `resources :documents` (show); `resources :chats, shallow: true { resources :documents }` (index, create) |

---

## Slice 4: Message links

**Demo:** When an agent includes a link to a Daan document in their message, it renders as a clickable link that opens the full-screen modal with the correct return path.

| Affordance | Type | Detail |
|------------|------|--------|
| Message link rendering | UI | `/documents/:id` URLs in agent message markdown rendered as links |
| `return_to_uri` param | Non-UI | Chat view appends `?return_to_uri=...` to document links in messages |
