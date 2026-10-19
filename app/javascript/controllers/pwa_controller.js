import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["networkBanner", "networkMessage", "updateNotice", "installSection", "installButton", "installHelp", "installedMessage", "updateStatus", "checkUpdateButton"]
  static values = {
    offlineMessage: String,
    failureMessage: String,
    checkingUpdateMessage: String,
    upToDateMessage: String,
    updateInstallingMessage: String,
    updateCheckFailedMessage: String,
    updateUnsupportedMessage: String
  }

  connect() {
    this.online = () => this.setOnline()
    this.offline = () => this.setOffline()
    this.installAvailable = () => this.showInstallButton()
    this.updateAvailable = () => this.showUpdateNotice()
    this.networkFailure = () => this.showNetworkFailure()
    this.offlineSubmit = () => this.setOffline()

    window.addEventListener("online", this.online)
    window.addEventListener("offline", this.offline)
    window.addEventListener("sumvon:install-available", this.installAvailable)
    window.addEventListener("sumvon:update-ready", this.updateAvailable)
    window.addEventListener("sumvon:network-failure", this.networkFailure)
    window.addEventListener("sumvon:offline-submit", this.offlineSubmit)
    document.addEventListener("turbo:fetch-request-error", this.networkFailure)

    navigator.onLine ? this.setOnline() : this.setOffline()
    this.refreshInstallState()
    if (window.sumvonServiceWorkerRegistration?.waiting) this.showUpdateNotice()
  }

  disconnect() {
    window.removeEventListener("online", this.online)
    window.removeEventListener("offline", this.offline)
    window.removeEventListener("sumvon:install-available", this.installAvailable)
    window.removeEventListener("sumvon:update-ready", this.updateAvailable)
    window.removeEventListener("sumvon:network-failure", this.networkFailure)
    window.removeEventListener("sumvon:offline-submit", this.offlineSubmit)
    document.removeEventListener("turbo:fetch-request-error", this.networkFailure)
  }

  setOffline() {
    if (!this.hasNetworkBannerTarget) return
    this.networkMessageTarget.textContent = this.offlineMessageValue
    this.networkBannerTarget.classList.remove("hidden")
  }

  setOnline() {
    if (this.hasNetworkBannerTarget) this.networkBannerTarget.classList.add("hidden")
  }

  showNetworkFailure() {
    if (!this.hasNetworkBannerTarget) return
    this.networkMessageTarget.textContent = this.failureMessageValue
    this.networkBannerTarget.classList.remove("hidden")
  }

  retry() { window.location.reload() }
  reload() { window.location.reload() }

  refreshInstallState() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
    if (standalone) {
      document.documentElement.classList.add("pwa-standalone")
      if (this.hasInstalledMessageTarget) this.installedMessageTarget.classList.remove("hidden")
      if (this.hasInstallButtonTarget) this.installButtonTarget.classList.add("hidden")
      if (this.hasInstallHelpTarget) this.installHelpTarget.classList.add("hidden")
    } else if (window.sumvonInstallPrompt) {
      this.showInstallButton()
    }
  }

  showInstallButton() {
    if (this.hasInstallButtonTarget) this.installButtonTarget.classList.remove("hidden")
  }

  async install() {
    const prompt = window.sumvonInstallPrompt
    if (!prompt) {
      if (this.hasInstallHelpTarget) this.installHelpTarget.open = true
      return
    }
    await prompt.prompt()
    await prompt.userChoice
    window.sumvonInstallPrompt = null
    if (this.hasInstallButtonTarget) this.installButtonTarget.classList.add("hidden")
  }

  showUpdateNotice() {
    if (this.hasUpdateNoticeTarget) this.updateNoticeTarget.classList.remove("hidden")
  }

  async checkForUpdate() {
    this.setUpdateStatus(this.checkingUpdateMessageValue)
    if (this.hasCheckUpdateButtonTarget) this.checkUpdateButtonTarget.disabled = true

    try {
      const registration = window.sumvonServiceWorkerRegistration || await navigator.serviceWorker?.getRegistration("/")
      if (!registration) return this.setUpdateStatus(this.updateUnsupportedMessageValue)

      await registration.update()
      if (registration.waiting) {
        this.showUpdateNotice()
      } else if (registration.installing) {
        this.setUpdateStatus(this.updateInstallingMessageValue)
      } else {
        this.setUpdateStatus(this.upToDateMessageValue)
      }
    } catch (_error) {
      this.setUpdateStatus(this.updateCheckFailedMessageValue)
    } finally {
      if (this.hasCheckUpdateButtonTarget) this.checkUpdateButtonTarget.disabled = false
    }
  }

  setUpdateStatus(message) {
    if (!this.hasUpdateStatusTarget) return
    this.updateStatusTarget.textContent = message
    this.updateStatusTarget.classList.remove("hidden")
  }

  applyUpdate() {
    const registration = window.sumvonServiceWorkerRegistration
    if (!registration?.waiting) return window.location.reload()
    window.sumvonApplyUpdate = true
    registration.waiting.postMessage({ type: "SKIP_WAITING" })
  }
}
