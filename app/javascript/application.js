// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Preserve focus across Turbo Stream renders (global because it applies to all
// streams, not scoped to a specific element). Without this, broadcast_replace_to
// and broadcast_append_to can cause the browser to blur the active element.
document.addEventListener("turbo:before-stream-render", (event) => {
  const activeElement = document.activeElement
  if (!activeElement || activeElement === document.body) return

  const originalRender = event.detail.render
  event.detail.render = (streamElement) => {
    originalRender(streamElement)
    if (document.contains(activeElement)) {
      activeElement.focus()
    }
  }
})
