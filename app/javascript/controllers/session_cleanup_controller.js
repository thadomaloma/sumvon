import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  clear() {
    const draftPrefixes = ["sumvon.transaction-draft.", "sumaro.transaction-draft.", "sumtui.transaction-draft."]

    Object.keys(sessionStorage)
      .filter((key) => draftPrefixes.some((prefix) => key.startsWith(prefix)))
      .forEach((key) => sessionStorage.removeItem(key))
  }
}
