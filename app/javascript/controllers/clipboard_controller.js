import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.dataset.text).then(() => {
      const original = this.buttonTarget.innerHTML
      this.buttonTarget.innerHTML = this.buttonTarget.dataset.copiedHtml
      setTimeout(() => { this.buttonTarget.innerHTML = original }, 2000)
    })
  }
}
