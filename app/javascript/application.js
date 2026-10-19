// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  window.sumvonInstallPrompt = event
  window.dispatchEvent(new CustomEvent("sumvon:install-available"))
})

if ("serviceWorker" in navigator && window.isSecureContext) {
  window.addEventListener("load", async () => {
    try {
      const registration = await navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
      window.sumvonServiceWorkerRegistration = registration

      const announceUpdate = () => window.dispatchEvent(new CustomEvent("sumvon:update-ready"))
      if (registration.waiting) announceUpdate()
      registration.addEventListener("updatefound", () => {
        const worker = registration.installing
        worker?.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) announceUpdate()
        })
      })
      navigator.serviceWorker.addEventListener("controllerchange", () => {
        if (window.sumvonApplyUpdate) window.location.reload()
      })
    } catch (_error) {
      window.dispatchEvent(new CustomEvent("sumvon:network-failure"))
    }
  }, { once: true })
}
