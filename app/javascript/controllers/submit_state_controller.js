import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.start = (event) => this.begin(event)
    this.end = () => this.finish()
    this.element.addEventListener("turbo:submit-start", this.start)
    this.element.addEventListener("turbo:submit-end", this.end)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.start)
    this.element.removeEventListener("turbo:submit-end", this.end)
  }

  begin(event) {
    this.submitter = event.detail.formSubmission.submitter
    if (!this.submitter) return
    this.originalLabel = this.submitter.value || this.submitter.textContent
    const savingLabel = this.submitter.dataset.submitStateSavingText || "Saving…"
    if (this.submitter.tagName === "INPUT") this.submitter.value = savingLabel
    else this.submitter.textContent = savingLabel
    this.submitter.disabled = true
    this.submitter.setAttribute("aria-busy", "true")
  }

  finish() {
    if (!this.submitter) return
    if (this.submitter.tagName === "INPUT") this.submitter.value = this.originalLabel
    else this.submitter.textContent = this.originalLabel
    this.submitter.disabled = false
    this.submitter.removeAttribute("aria-busy")
  }
}
