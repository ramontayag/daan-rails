import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field"]

  connect() {
    this.fieldTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone
  }
}
