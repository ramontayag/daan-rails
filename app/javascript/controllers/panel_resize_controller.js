import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "thread-panel-width"
const MIN_WIDTH = 200

export default class extends Controller {
  static targets = ["panel"]

  panelTargetConnected(panel) {
    if (window.innerWidth < 768 || panel.classList.contains("hidden")) return
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) panel.style.width = saved + "px"
  }

  startDrag(event) {
    if (window.innerWidth < 768) return
    this._dragging = true
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  _drag(event) {
    if (!this._dragging) return
    const width = Math.max(
      MIN_WIDTH,
      Math.min(
        this.element.offsetWidth - MIN_WIDTH,
        this.element.getBoundingClientRect().right - event.clientX
      )
    )
    this.panelTarget.style.width = width + "px"
  }

  _stopDrag() {
    if (!this._dragging) return
    this._dragging = false
    const width = parseInt(this.panelTarget.style.width)
    if (!isNaN(width)) localStorage.setItem(STORAGE_KEY, width)
  }
}
