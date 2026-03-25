# Thread Panel Resize — Design Spec

## Context

The thread panel sits to the right of the thread list on md+ screens. Currently it has a fixed layout. Users should be able to drag its left edge to resize it, with the width persisting across sessions (localStorage). Mobile is unaffected.

## Architecture

A new Stimulus controller (`panel-resize`) is placed on the flex row container in `threads/show.html.erb`. A sibling drag handle element sits between the thread list and the thread panel turbo frame. The thread list becomes `flex-1` (fills remaining space); the thread panel gets an explicit width managed by the controller.

## Components

**`panel_resize_controller.js`** (requires Stimulus 3.x, shipped with Rails 8.1)

Targets: `panel` (the turbo frame element).

- `panelTargetConnected(panel)` — Fires on connect and after each Turbo navigation that replaces the frame content. Guards: if `window.innerWidth < 768` or the panel has the `hidden` class, no-op. Otherwise reads `localStorage["thread-panel-width"]`; if present, sets `panel.style.width = savedValue + "px"` (value stored as bare integer string, restored with `"px"` appended). If absent, leaves the server-rendered inline style (400px) alone.

- `startDrag(event)` — No-ops if `window.innerWidth < 768`. Calls `event.currentTarget.setPointerCapture(event.pointerId)` (using `currentTarget`, not `target`, to ensure capture is always set on the outer handle element regardless of which child was clicked). All three pointer events (`pointerdown`, `pointermove`, `pointerup`) are wired via `data-action` on the same outer handle element — pointer capture ensures `pointermove`/`pointerup` are delivered to that element even after the pointer leaves it.

- `_drag(event)` — Computes `this.element.getBoundingClientRect().right - event.clientX`. Clamps to `[200, this.element.offsetWidth - 200]`. Applies as `this.panelTarget.style.width = width + "px"`.

- `_stopDrag(event)` — Pointer capture is released automatically by the browser on `pointerup`. Reads `parseInt(this.panelTarget.style.width)`; if result is not `NaN`, saves to `localStorage["thread-panel-width"]`. (Guards against a click-without-drag producing an empty style value.)

`window.innerWidth < 768` is the **single authoritative mobile gate**, applied in both `startDrag` and `panelTargetConnected`.

localStorage key: `"thread-panel-width"` — bare string, intentional. Stored as bare integer (e.g. `"400"`), restored by appending `"px"`.

**`threads/show.html.erb`**

- `data-controller="panel-resize"` on `div.flex.flex-1.overflow-hidden.min-w-0`
- Drag handle (only rendered when `@chat` is present), placed between thread list and turbo frame:
  ```html
  <div class="hidden md:flex w-1 cursor-col-resize flex-shrink-0 group items-stretch"
       data-action="pointerdown->panel-resize#startDrag pointermove->panel-resize#_drag pointerup->panel-resize#_stopDrag">
    <div class="w-px bg-gray-200 group-hover:bg-blue-400 mx-auto transition-colors duration-150"></div>
  </div>
  ```
- Turbo frame class: keep `flex flex-col border-l border-gray-200` and the `hidden` conditional; remove `flex-1 min-w-0`; add `style: "width: 400px"` and `data: { panel_resize_target: "panel" }`.

**`thread_list_component.html.erb`**

When `open_chat`, the full outer div class becomes:
`hidden md:flex md:flex-col md:flex-1 md:min-w-0` (replaces `hidden md:flex md:flex-col md:w-96`)

## Data Flow

1. Page loads → `panelTargetConnected` fires → restores saved width if desktop and panel visible
2. User grabs handle → `startDrag` captures pointer on outer handle via `event.currentTarget.setPointerCapture`
3. Pointer moves → `_drag` updates `panelTarget.style.width`
4. Pointer released → `_stopDrag` saves bare integer to localStorage (guards against NaN)
5. Turbo navigates to a different thread → frame content replaced → `panelTargetConnected` fires again → width restored

## Constraints

- Only active on md+ (guarded in `startDrag` and `panelTargetConnected`)
- Min 200px, max `this.element.offsetWidth − 200px`
- Default: 400px server-rendered inline style (used when localStorage is empty)
- Mobile: handle not rendered, no resize behavior

## Testing

- Run `bin/rails test && bin/rails test:system` — no regressions expected
- Manual: drag narrows/widens panel; reload confirms persistence; navigating between threads preserves width; mobile shows no handle; clicking handle without dragging does not corrupt localStorage
