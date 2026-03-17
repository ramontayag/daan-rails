import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-resize-textarea"
export default class extends Controller {
  static targets = ["textarea"]
  
  connect() {
    this.resize()
    
    // Set initial min height based on single line height
    const computed = window.getComputedStyle(this.textareaTarget)
    const lineHeight = parseInt(computed.lineHeight) || 24
    this.minHeight = lineHeight + (parseInt(computed.paddingTop) || 0) + (parseInt(computed.paddingBottom) || 0)
    
    // Set max height (approximately 6 lines)
    this.maxHeight = this.minHeight + (lineHeight * 5)
    
    this.textareaTarget.style.minHeight = `${this.minHeight}px`
    this.textareaTarget.style.maxHeight = `${this.maxHeight}px`
  }

  resize() {
    const textarea = this.textareaTarget
    
    // Reset height to auto to get the correct scrollHeight
    textarea.style.height = 'auto'
    
    // Calculate new height based on content
    let newHeight = textarea.scrollHeight
    
    // Apply min/max constraints
    if (this.minHeight && newHeight < this.minHeight) {
      newHeight = this.minHeight
    } else if (this.maxHeight && newHeight > this.maxHeight) {
      newHeight = this.maxHeight
    }
    
    // Set the new height
    textarea.style.height = `${newHeight}px`
  }

  // Handle input events
  input() {
    this.resize()
  }

  // Handle paste events (resize after content is pasted)
  paste() {
    // Use setTimeout to resize after paste content is inserted
    setTimeout(() => this.resize(), 0)
  }

  // Handle key events for Enter key behavior
  keydown(event) {
    // Submit form on Enter (without Shift)
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      this.element.querySelector('form').requestSubmit()
    }
    // Allow Shift+Enter for new lines (default textarea behavior)
  }
}