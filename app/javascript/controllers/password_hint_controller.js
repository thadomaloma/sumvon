import { Controller } from "@hotwired/stimulus"

// Marks the password length hint as met while the person types, so the requirement is
// visible before submitting rather than only as an error afterwards.
export default class extends Controller {
  static targets = ["input", "hint"]
  static values = { minimum: Number }

  connect() {
    this.update()
  }

  update() {
    const met = this.inputTarget.value.length >= this.minimumValue
    this.hintTarget.classList.toggle("is-met", met)
  }
}
