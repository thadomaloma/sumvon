import { Controller } from "@hotwired/stimulus"

// The server gives up on OCR after ~20 seconds; leave room for a slow upload.
const SCAN_TIMEOUT_MS = 60_000
// Photos are shrunk to this long edge before upload: receipt text stays legible, and a
// 50 MB ProRAW original becomes a few hundred kilobytes.
const UPLOAD_MAX_EDGE = 2048
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024
const RAW_PHOTO = /\.(dng|raw|cr2|cr3|nef|arw|orf|rw2)$/i

export default class extends Controller {
  static targets = ["amount", "date", "status", "alternatives"]
  static values = { url: String }

  disconnect() {
    this.scanRequest?.abort()
  }

  async scan(event) {
    const input = event.currentTarget
    const file = input.files[0]
    if (!file) return

    this.scanRequest?.abort()
    const request = new AbortController()
    this.scanRequest = request
    let timedOut = false
    const timeout = setTimeout(() => {
      timedOut = true
      request.abort()
    }, SCAN_TIMEOUT_MS)
    this.statusTarget.textContent = this.statusTarget.dataset.scanning
    this.clearAlternatives()
    const before = { amount: this.amountTarget.value, date: this.dateTarget.value, kind: this.selectedKind }

    try {
      const photo = await this.preparePhoto(file)
      if (this.scanRequest !== request) return
      if (!photo) return

      const body = new FormData()
      body.append("photo", photo, photo.name || "receipt.jpg")
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json"
        },
        body,
        signal: request.signal
      })
      const data = await response.json()
      if (this.scanRequest !== request) return
      if (!response.ok) {
        this.statusTarget.textContent = data.error || this.statusTarget.dataset.failed
        return
      }

      const found = []
      let kept = false
      for (const [field, target, label] of [
        ["amount", this.amountTarget, this.statusTarget.dataset.amountLabel],
        ["date", this.dateTarget, this.statusTarget.dataset.dateLabel]
      ]) {
        if (!data[field]) continue
        if (this.fill(target, data[field], before[field])) found.push(label)
        else kept = true
      }
      // An ATM slip is money moving between the person's own accounts.
      if (data.kind) {
        if (this.selectKind(data.kind, before.kind)) found.push(this.statusTarget.dataset.kindLabel)
        else kept = true
      }

      if (found.length) {
        this.statusTarget.textContent = `${this.statusTarget.dataset.found} ${found.join(", ")}.`
      } else if (data.alternatives?.length) {
        this.statusTarget.textContent = this.statusTarget.dataset.pickAmount
      } else {
        this.statusTarget.textContent = kept ? this.statusTarget.dataset.kept : this.statusTarget.dataset.notFound
      }
      this.showAlternatives(data.alternatives || [], data.amount ? this.statusTarget.dataset.otherAmounts : "")
    } catch (error) {
      if (this.scanRequest !== request) return
      if (timedOut) this.statusTarget.textContent = this.statusTarget.dataset.timedOut
      else if (error.name !== "AbortError") this.statusTarget.textContent = this.statusTarget.dataset.failed
    } finally {
      clearTimeout(timeout)
      input.value = ""
      if (this.scanRequest === request) this.scanRequest = null
    }
  }

  // Shrinks the photo to a JPEG in the browser when it can decode it (including HEIC
  // and ProRAW on iPhone), so uploads are small and fast. Photos it can't decode are
  // sent as they are, unless they are RAW or too large for the server to accept.
  async preparePhoto(file) {
    let bitmap
    try {
      bitmap = await createImageBitmap(file)
    } catch (_error) {
      if (RAW_PHOTO.test(file.name) || /dng|raw/i.test(file.type)) return this.rejectPhoto(this.statusTarget.dataset.rawUnsupported)
      if (file.size > MAX_UPLOAD_BYTES) return this.rejectPhoto(this.statusTarget.dataset.tooLarge)
      return file
    }

    try {
      const scale = Math.min(1, UPLOAD_MAX_EDGE / Math.max(bitmap.width, bitmap.height))
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(bitmap.width * scale)
      canvas.height = Math.round(bitmap.height * scale)
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88))
      if (!blob) return file.size > MAX_UPLOAD_BYTES ? this.rejectPhoto(this.statusTarget.dataset.tooLarge) : file
      return new File([ blob ], "receipt.jpg", { type: "image/jpeg" })
    } finally {
      bitmap.close()
    }
  }

  rejectPhoto(message) {
    this.statusTarget.textContent = message
    return null
  }

  // When OCR can't tell which printed amount is the total, the person picks it.
  showAlternatives(amounts, label) {
    this.clearAlternatives()
    if (!amounts.length) return

    if (label) {
      const caption = document.createElement("span")
      caption.className = "text-xs text-slate-500"
      caption.textContent = label
      this.alternativesTarget.append(caption)
    }
    for (const amount of amounts) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "rounded-full border border-slate-300 bg-white px-3 py-1.5 text-sm font-semibold tabular-nums hover:border-emerald-700"
      button.textContent = Number(amount).toLocaleString()
      button.addEventListener("click", () => this.chooseAmount(amount))
      this.alternativesTarget.append(button)
    }
    this.alternativesTarget.hidden = false
  }

  chooseAmount(amount) {
    this.fill(this.amountTarget, amount, this.amountTarget.value)
    this.statusTarget.textContent = `${this.statusTarget.dataset.found} ${this.statusTarget.dataset.amountLabel}.`
    this.amountTarget.focus()
    this.clearAlternatives()
  }

  clearAlternatives() {
    this.alternativesTarget.replaceChildren()
    this.alternativesTarget.hidden = true
  }

  get selectedKind() {
    return this.element.querySelector('input[name="transaction[kind]"]:checked')?.value
  }

  selectKind(kind, kindBeforeScan) {
    const option = this.element.querySelector(`input[name="transaction[kind]"][value="${CSS.escape(kind)}"]`)
    if (!option || this.selectedKind !== kindBeforeScan) return false
    if (option.checked) return true

    option.checked = true
    option.dispatchEvent(new Event("input", { bubbles: true }))
    option.dispatchEvent(new Event("change", { bubbles: true }))
    return true
  }

  // Leaves a field alone if the person edited it while the scan was running, and
  // announces the change so listeners such as the draft autosave pick it up.
  fill(target, value, valueBeforeScan) {
    if (target.value !== valueBeforeScan) return false

    target.value = value
    target.dispatchEvent(new Event("input", { bubbles: true }))
    target.dispatchEvent(new Event("change", { bubbles: true }))
    return true
  }
}
