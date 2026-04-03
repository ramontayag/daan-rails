import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "chevron"]

  toggle() {
    this.panelTarget.classList.toggle("hidden")
    this.chevronTarget.classList.toggle("rotate-180")
  }
}
