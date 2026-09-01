import { Controller } from "@hotwired/stimulus"
import { idempotencyKey, operationResult } from "controllers/operation_poller"

export default class extends Controller {
  static targets = ["urls", "status"]
  static values = { url: String }

  connect() { this.lastUrl = null; this.queue() }
  disconnect() { clearTimeout(this.timer) }

  queue() {
    clearTimeout(this.timer)
    const url = this.urlsTarget.value.split("\n").map(value => value.trim()).find(Boolean)
    if (!url || url === this.lastUrl || !/^https?:\/\//i.test(url)) return
    this.timer = setTimeout(() => this.prefetch(url), 700)
  }

  async prefetch(url) {
    this.lastUrl = url
    this.statusTarget.textContent = "Preparing the first page with Nokogiri…"
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content, "Accept": "application/json", "Idempotency-Key": idempotencyKey() },
        body: JSON.stringify({ url, scrape_run_id: this.element.dataset.scrapeRunId })
      })
      const payload = await operationResult(response)
      this.statusTarget.textContent = payload.title ? `Prepared “${payload.title}” for previews and suggestions.` : "Page prepared for previews and suggestions."
    } catch (error) {
      this.statusTarget.textContent = error.message
      this.lastUrl = null
    }
  }
}
