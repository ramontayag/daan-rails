import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "thread-list-width"
const MIN_WIDTH = 180

export default class extends Controller {
  static targets = ["panel"]

  panelTargetConnected(panel) {
    if (window.innerWidth < 768 || panel.classList.contains("hidden")) return
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) panel.style.flex = `0 0 ${saved}px`
  }

  startDrag(event) {
    if (window.innerWidth < 768) return
    this._dragging = true
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  _drag(event) {
    if (!this._dragging) return
    const containerLeft = this.element.getBoundingClientRect().left
    const width = Math.max(
      MIN_WIDTH,
      Math.min(
        this.element.offsetWidth - MIN_WIDTH,
        event.clientX - containerLeft
      )
    )
    this.panelTarget.style.flex = `0 0 ${width}px`
  }

  _stopDrag() {
    if (!this._dragging) return
    this._dragging = false
    const width = Math.round(this.panelTarget.getBoundingClientRect().width)
    if (width > 0) localStorage.setItem(STORAGE_KEY, width)
  }
}
