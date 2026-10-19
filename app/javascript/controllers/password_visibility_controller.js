import { Controller } from "@hotwired/stimulus"

// Shows or hides the characters of a password field. The toggle stays hidden until this
// connects, so it never appears without working. The field always returns to
// type="password" before its form submits and before Turbo caches the page, so password
// managers recognise the submission and plain text never lands in the page cache.
export default class extends Controller {
  static targets = ["input", "button", "showIcon", "hideIcon"]
  static values = { showLabel: String, hideLabel: String }

  connect() {
    this.form = this.inputTarget.form
    this.form?.addEventListener("submit", this.conceal)
    document.addEventListener("turbo:before-cache", this.conceal)
    this.render(false)
    this.buttonTarget.hidden = false
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.conceal)
    document.removeEventListener("turbo:before-cache", this.conceal)
    this.conceal()
  }

  // Pressing the button would otherwise move focus off the field and close the
  // on-screen keyboard; keep the caret where the person was typing.
  keepFocus(event) {
    if (document.activeElement === this.inputTarget) event.preventDefault()
  }

  toggle(event) {
    event.preventDefault()
    const input = this.inputTarget
    const focused = document.activeElement === input
    const { selectionStart, selectionEnd } = input
    const reveal = input.type === "password"

    input.type = reveal ? "text" : "password"
    this.render(reveal)

    if (focused) {
      input.focus()
      // Newer Chromium rebuilds the field's editor on a type change and moves the caret to
      // the start while still reporting the old selection, which makes setting the same
      // range a no-op. Move it away first, then restore it now and again next frame.
      const restore = () => {
        try {
          input.setSelectionRange(0, 0)
          input.setSelectionRange(selectionStart, selectionEnd)
        } catch { /* selection unsupported */ }
      }
      restore()
      // Typing can arrive before the next frame, so restore before the first edit too.
      const beforeFirstEdit = () => restore()
      input.addEventListener("beforeinput", beforeFirstEdit, { once: true })
      requestAnimationFrame(() => {
        input.removeEventListener("beforeinput", beforeFirstEdit)
        restore()
      })
    }
  }

  conceal = () => {
    if (this.inputTarget.type === "password") return

    this.inputTarget.type = "password"
    this.render(false)
  }

  render(revealed) {
    const label = revealed ? this.hideLabelValue : this.showLabelValue
    this.buttonTarget.setAttribute("aria-pressed", String(revealed))
    this.buttonTarget.setAttribute("aria-label", label)
    this.buttonTarget.title = label
    // SVG elements have no `hidden` property, so set the attribute itself.
    this.showIconTarget.toggleAttribute("hidden", revealed)
    this.hideIconTarget.toggleAttribute("hidden", !revealed)
  }
}
