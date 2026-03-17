import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="preserve-focus"
export default class extends Controller {
  connect() {
    // Listen for Turbo events to preserve focus
    document.addEventListener('turbo:before-stream-render', this.preserveFocus.bind(this))
    document.addEventListener('turbo:after-stream-render', this.restoreFocus.bind(this))
    
    // Also listen for frame replacements
    document.addEventListener('turbo:before-frame-render', this.preserveFocus.bind(this))
    document.addEventListener('turbo:after-frame-render', this.restoreFocus.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:before-stream-render', this.preserveFocus.bind(this))
    document.removeEventListener('turbo:after-stream-render', this.restoreFocus.bind(this))
    document.removeEventListener('turbo:before-frame-render', this.preserveFocus.bind(this))
    document.removeEventListener('turbo:after-frame-render', this.restoreFocus.bind(this))
  }

  preserveFocus(event) {
    // Only preserve focus for message inputs
    const activeElement = document.activeElement
    if (activeElement && activeElement.matches('textarea[data-testid="message-input"]')) {
      console.log('Preserving focus on:', activeElement)
      this.focusedElement = activeElement
      this.cursorPosition = activeElement.selectionStart
      this.focusedValue = activeElement.value
      
      // Store a way to find this element again after potential DOM changes
      this.focusSelector = 'textarea[data-testid="message-input"]'
      this.focusContainer = activeElement.closest('[data-testid="compose-bar"]')
    } else {
      this.focusedElement = null
      this.cursorPosition = null
      this.focusedValue = null
      this.focusSelector = null
      this.focusContainer = null
    }
  }

  restoreFocus(event) {
    if (this.focusedElement || this.focusSelector) {
      setTimeout(() => {
        let elementToFocus = this.focusedElement

        // If the original element is no longer in the DOM, find it again
        if (!elementToFocus || !document.contains(elementToFocus)) {
          console.log('Original element not found, searching for replacement')
          if (this.focusContainer && document.contains(this.focusContainer)) {
            elementToFocus = this.focusContainer.querySelector(this.focusSelector)
          } else {
            elementToFocus = document.querySelector(this.focusSelector)
          }
        }

        if (elementToFocus) {
          console.log('Restoring focus to:', elementToFocus)
          elementToFocus.focus()
          
          // Restore cursor position if the value matches
          if (this.cursorPosition !== null && elementToFocus.value === this.focusedValue) {
            elementToFocus.setSelectionRange(this.cursorPosition, this.cursorPosition)
          }
        } else {
          console.log('Could not find element to restore focus to')
        }
      }, 50) // Slightly longer delay to ensure DOM is fully updated
    }
  }
}