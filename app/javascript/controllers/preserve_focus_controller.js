import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="preserve-focus"
export default class extends Controller {
  connect() {
    // Listen for Turbo events to preserve focus
    document.addEventListener('turbo:before-stream-render', this.preserveFocus.bind(this))
    document.addEventListener('turbo:after-stream-render', this.restoreFocus.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:before-stream-render', this.preserveFocus.bind(this))
    document.removeEventListener('turbo:after-stream-render', this.restoreFocus.bind(this))
  }

  preserveFocus(event) {
    // Only preserve focus for message inputs
    const activeElement = document.activeElement
    if (activeElement && activeElement.matches('textarea[data-testid="message-input"]')) {
      this.focusedElement = activeElement
      this.cursorPosition = activeElement.selectionStart
    } else {
      this.focusedElement = null
      this.cursorPosition = null
    }
  }

  restoreFocus(event) {
    if (this.focusedElement && document.contains(this.focusedElement)) {
      // Small delay to ensure DOM updates are complete
      setTimeout(() => {
        this.focusedElement.focus()
        if (this.cursorPosition !== null) {
          this.focusedElement.setSelectionRange(this.cursorPosition, this.cursorPosition)
        }
      }, 10)
    }
  }
}