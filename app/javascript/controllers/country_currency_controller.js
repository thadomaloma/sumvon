import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["country", "currency"]
  static values = { map: Object }

  countryChanged() {
    const currency = this.mapValue[this.countryTarget.value]
    if (!currency) return

    this.currencyTarget.value = currency
    this.currencyTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
