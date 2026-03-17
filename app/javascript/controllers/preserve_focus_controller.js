import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="preserve-focus"
export default class extends Controller {
  connect() {
    // Handle focus after page loads (including redirects)
    this.handleInitialFocus()
    
    // Prevent autofocus during Turbo updates
    document.addEventListener('turbo:before-stream-render', this.disableAutofocus.bind(this))
    document.addEventListener('turbo:load', this.handleInitialFocus.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:before-stream-render', this.disableAutofocus.bind(this))
    document.removeEventListener('turbo:load', this.handleInitialFocus.bind(this))
  }

  handleInitialFocus() {
    // On page load, focus should go to the thread panel input if we're viewing a thread
    const threadPanel = document.querySelector('[data-testid="thread-panel"]')
    const threadInput = threadPanel?.querySelector('textarea[data-testid="message-input"]')
    
    if (threadInput && threadPanel) {
      // Disable any autofocus on other elements
      document.querySelectorAll('[autofocus]').forEach(el => {
        if (el !== threadInput) {
          el.removeAttribute('autofocus')
        }
      })
      
      // Focus on the thread input
      setTimeout(() => {
        threadInput.focus()
      }, 100)
    }
  }

  disableAutofocus(event) {
    // Disable all autofocus during Turbo Stream updates
    setTimeout(() => {
      document.querySelectorAll('[autofocus]').forEach(el => {
        el.removeAttribute('autofocus')
      })
    }, 0)
  }
}