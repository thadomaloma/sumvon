import { Controller } from "@hotwired/stimulus"

// Preselects the time zone that matches the browser on a fresh sign-up form, and keeps
// the short summary next to the "Change" control in sync with the select.
export default class extends Controller {
  static targets = ["select", "label"]
  static values = { detect: Boolean }

  connect() {
    if (this.detectValue) this.detect()
    this.sync()
  }

  detect() {
    let zone
    try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone } catch { return }
    if (!zone) return

    // Browsers may report an older alias (Asia/Calcutta for Asia/Kolkata), so compare
    // each option the way this browser itself names the zone too.
    const ids = (candidate) => (candidate.dataset.iana || "").split(" ").filter(Boolean)
    const matches = Array.from(this.selectTarget.options).filter((candidate) =>
      ids(candidate).some((id) => id === zone || this.browserName(id) === zone))
    // Several Rails zones share one IANA zone (Osaka, Sapporo and Tokyo are all
    // Asia/Tokyo), so prefer the one named after its own IANA city.
    const city = (id) => id.split("/").pop().replace(/_/g, " ")
    const option = matches.find((candidate) => ids(candidate).some((id) => city(id) === candidate.value)) || matches[0]
    if (option) this.selectTarget.value = option.value
  }

  browserName(id) {
    try { return new Intl.DateTimeFormat("en", { timeZone: id }).resolvedOptions().timeZone } catch { return null }
  }

  sync() {
    const option = this.selectTarget.selectedOptions[0]
    if (option) this.labelTarget.textContent = option.textContent
  }
}
