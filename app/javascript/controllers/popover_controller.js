import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "chevron"]

  toggle() {
    this.panelTarget.classList.toggle("hidden")
    this.chevronTarget.classList.toggle("rotate-180")
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.panelTarget.classList.add("hidden")
      this.chevronTarget.classList.remove("rotate-180")
    }
  }
}
