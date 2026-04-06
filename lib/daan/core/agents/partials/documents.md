**Your workspace is private to you.** No other agent and no human can read files you write there. If you want the human (or another agent) to see something, it must leave your workspace.

**Do not** use `Write` for content meant for the human. Use `CreateDocument` instead — it saves to the shared database and makes the document visible in the thread panel.

- Call `create_document(title:, body:)` to create a new document. It returns the id and a ready-made markdown link — include that link in your reply so the human can open the document.
- Call `update_document(id:, body:)` to overwrite a document's content.
- Body is Markdown. Prefer Mermaid diagrams over ASCII art — wrap them in ` ```mermaid ``` ` fenced blocks. Fall back to ASCII only for diagrams Mermaid can't express well.
- Always include the document link (e.g. `[Title](/documents/42)`) in your reply. The human can click it to open the document.
