import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.abortController = new AbortController()
    const options = { passive: false, signal: this.abortController.signal }

    this.element.addEventListener("touchmove", this.blockGesture, options)
    this.element.addEventListener("gesturestart", this.blockGesture, options)
    this.element.addEventListener("gesturechange", this.blockGesture, options)
    this.element.addEventListener("dragstart", this.blockGesture, options)
    this.element.addEventListener("pointermove", this.blockPointerDrag, options)
    this.element.addEventListener("wheel", this.blockHorizontalWheel, options)
  }

  disconnect() {
    this.abortController?.abort()
  }

  blockGesture = (event) => {
    if (this.isInteractive(event.target)) return

    event.preventDefault()
  }

  blockPointerDrag = (event) => {
    if (this.isInteractive(event.target)) return

    if (event.pointerType !== "mouse" || event.buttons !== 0) event.preventDefault()
  }

  blockHorizontalWheel = (event) => {
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) event.preventDefault()
  }

  isInteractive(target) {
    return target instanceof Element && Boolean(target.closest("a, button, summary, input, select, textarea, [role='button']"))
  }
}
