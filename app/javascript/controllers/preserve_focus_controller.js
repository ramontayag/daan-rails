import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="preserve-focus"
export default class extends Controller {
  connect() {
    // Prevent any autofocus during Turbo updates
    document.addEventListener('turbo:before-stream-render', this.disableAutofocus.bind(this))
    document.addEventListener('turbo:before-frame-render', this.disableAutofocus.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:before-stream-render', this.disableAutofocus.bind(this))
    document.removeEventListener('turbo:before-frame-render', this.disableAutofocus.bind(this))
  }

  disableAutofocus(event) {
    // Find and temporarily disable all autofocus attributes
    setTimeout(() => {
      const autofocusElements = document.querySelectorAll('[autofocus]')
      autofocusElements.forEach(el => {
        el.removeAttribute('autofocus')
      })
    }, 0)
  }
}