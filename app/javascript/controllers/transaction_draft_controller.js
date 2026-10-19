import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notice"]
  static values = { key: String }

  connect() {
    this.ttl = 30 * 60 * 1000
    this.timer = null
    this.draft = this.readDraft()
    if (this.draft && this.hasNoticeTarget) this.noticeTarget.classList.remove("hidden")
  }

  scheduleSave() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), 250)
  }

  save() {
    const data = {}
    const allowed = ["transaction[idempotency_key]", "transaction[kind]", "transaction[amount]", "transaction[financial_account_id]", "transaction[transfer_account_id]", "transaction[category_id]", "transaction[transaction_date]"]
    new FormData(this.element).forEach((value, name) => {
      if (allowed.includes(name)) data[name] = value
    })
    sessionStorage.setItem(this.keyValue, JSON.stringify({ savedAt: Date.now(), data }))
  }

  submit(event) {
    if (navigator.onLine) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.save()
    window.dispatchEvent(new CustomEvent("sumvon:offline-submit"))
  }

  submitted(event) {
    if (event.detail.success) this.clear()
  }

  continueDraft() {
    if (!this.draft) return
    Object.entries(this.draft.data).forEach(([name, value]) => {
      const field = this.element.elements.namedItem(name)
      if (!field) return
      field.value = value
      const changedField = typeof field.dispatchEvent === "function" ? field : Array.from(field).find((candidate) => candidate.value === value)
      changedField?.dispatchEvent(new Event("change", { bubbles: true }))
    })
    this.noticeTarget.classList.add("hidden")
  }

  discard() {
    this.clear()
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")
  }

  clear() {
    sessionStorage.removeItem(this.keyValue)
    this.draft = null
  }

  readDraft() {
    try {
      const draft = JSON.parse(sessionStorage.getItem(this.keyValue))
      if (!draft || Date.now() - draft.savedAt > this.ttl) {
        this.clear()
        return null
      }
      return draft
    } catch (_error) {
      this.clear()
      return null
    }
  }
}
