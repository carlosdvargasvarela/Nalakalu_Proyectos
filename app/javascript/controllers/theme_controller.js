import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "theme"

// Toggles data-bs-theme on <html> between "light" and "dark", persisting the
// choice in localStorage. Falls back to the OS preference (prefers-color-scheme)
// the first time, before any manual choice has been made.
export default class extends Controller {
  static targets = ["icon"]

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const theme = stored || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
    this.apply(theme)
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-bs-theme")
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem(STORAGE_KEY, next)
    this.apply(next)
  }

  apply(theme) {
    document.documentElement.setAttribute("data-bs-theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
    if (this.hasIconTarget) {
      this.iconTarget.textContent = theme === "dark" ? "☀" : "☾"
    }
  }
}
