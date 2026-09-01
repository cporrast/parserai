import { Controller } from "@hotwired/stimulus"
import { idempotencyKey, operationResult } from "controllers/operation_poller"

export default class extends Controller {
  static targets = ["editor", "lineNumbers", "status", "suggestButton", "urls", "instructions", "model"]
  static values = { suggestUrl: String }

  connect() {
    this.update()
  }

  update() {
    this.lineNumbersTarget.textContent = Array.from(
      { length: Math.max(this.editorTarget.value.split("\n").length, 1) },
      (_, index) => index + 1
    ).join("\n")
    this.validate()
  }

  syncScroll() {
    this.lineNumbersTarget.scrollTop = this.editorTarget.scrollTop
  }

  keydown(event) {
    if (event.key === "Tab") {
      event.preventDefault()
      this.insertText("  ")
    } else if (event.key === "Enter") {
      event.preventDefault()
      const before = this.editorTarget.value.slice(0, this.editorTarget.selectionStart)
      const indentation = before.split("\n").pop().match(/^\s*/)?.[0] || ""
      this.insertText(`\n${indentation}`)
    }
  }

  format() {
    try {
      this.editorTarget.value = JSON.stringify(JSON.parse(this.editorTarget.value), null, 2)
      this.update()
      this.editorTarget.focus()
    } catch (_) {
      this.showStatus("Fix invalid JSON before formatting", false)
    }
  }

  async suggest() {
    const url = this.urlsTarget.value.split("\n").map(value => value.trim()).find(Boolean)
    const instructions = this.instructionsTarget.value.trim()
    if (!url || !instructions) {
      this.showStatus("Add a URL and instructions first", false)
      return
    }

    this.suggestButtonTarget.disabled = true
    this.suggestButtonTarget.textContent = "Inspecting page…"
    this.showStatus("The extraction model is reviewing one page", true)

    try {
      const response = await fetch(this.suggestUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json",
          "Idempotency-Key": idempotencyKey()
        },
        body: JSON.stringify({ url, instructions, output_schema: this.editorTarget.value, setup_model: this.modelTarget.value, scrape_run_id: this.element.dataset.scrapeRunId })
      })
      const payload = await operationResult(response)

      this.editorTarget.value = payload.schema
      this.editorTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.showStatus(payload.cached ? "Cached schema recommendation reused" : "Schema recommendation generated", true)
    } catch (error) {
      this.showStatus(error.message, false)
    } finally {
      this.suggestButtonTarget.disabled = false
      this.suggestButtonTarget.textContent = "Suggest with AI"
    }
  }

  insertText(text) {
    const start = this.editorTarget.selectionStart
    const end = this.editorTarget.selectionEnd
    this.editorTarget.setRangeText(text, start, end, "end")
    this.editorTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  validate() {
    if (this.editorTarget.closest("[data-controller~='output-format']")?.querySelector("select")?.value === "csv") {
      this.showStatus("CSV columns", true)
      return
    }

    try {
      JSON.parse(this.editorTarget.value)
      this.showStatus("Valid JSON", true)
    } catch (error) {
      this.showStatus(`Invalid JSON · ${error.message.replace(/^JSON\.parse: /, "")}`, false)
    }
  }

  showStatus(message, valid) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-emerald-400", valid)
    this.statusTarget.classList.toggle("text-rose-400", !valid)
  }
}
