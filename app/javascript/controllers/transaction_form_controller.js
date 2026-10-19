import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "categoryGroup", "transferGroup", "category", "accountLabel", "account", "transferAccount"]

  connect() { this.refresh() }
  change() { this.refresh() }

  refresh() {
    const kind = this.kindTargets.find((input) => input.checked)?.value || "expense"
    const transfer = kind === "transfer"
    this.categoryGroupTarget.hidden = transfer
    this.transferGroupTarget.hidden = !transfer
    this.categoryTarget.disabled = transfer
    this.transferAccountTarget.disabled = !transfer
    this.accountLabelTarget.textContent = transfer ? "From account" : "Account"

    Array.from(this.categoryTarget.options).forEach((option) => {
      if (!option.value) return
      option.hidden = option.dataset.kind !== kind
      option.disabled = option.dataset.kind !== kind
    })
    if (this.categoryTarget.selectedOptions[0]?.dataset.kind !== kind) this.categoryTarget.value = ""
  }

  accountChanged() {
    if (this.transferAccountTarget.value === this.accountTarget.value) this.transferAccountTarget.value = ""
  }
}
