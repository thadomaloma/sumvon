import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["month", "year", "value"]
  static values = { currentYear: Number }

  connect() {
    this.sync()
  }

  monthChanged() {
    if (this.monthTarget.value && !this.yearTarget.value) {
      this.yearTarget.value = String(this.currentYearValue)
    }

    this.sync()
  }

  sync() {
    const month = this.monthTarget.value
    const year = this.yearTarget.value
    this.valueTarget.value = month && year ? `${year}-${month}` : ""
  }
}
