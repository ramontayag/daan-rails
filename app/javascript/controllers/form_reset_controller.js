import { Controller } from "@hotwired/stimulus"

// Resets the form and re-focuses the textarea after a successful Turbo submission.
// Attach to the same wrapper as auto-resize-textarea so it can reset the height.
export default class extends Controller {
  static targets = ["textarea"]

  reset() {
    this.element.querySelector("form").reset()
    this.textareaTarget.style.height = "auto"
    this.textareaTarget.focus()
  }
}
