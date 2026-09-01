import { Controller } from "@hotwired/stimulus"
import { idempotencyKey, operationResult } from "controllers/operation_poller"

export default class extends Controller {
  static targets = [
    "editor", "lineNumbers", "status", "suggestButton", "urls", "instructions",
    "outputSchema", "outputFormat", "preview", "previewContainer", "matchCount",
    "model", "pagePreview", "diagnostics", "legend", "pageMeta", "outputLabel"
  ]
  static values = { suggestUrl: String, testUrl: String }

  connect() { this.update() }

  update() {
    this.lineNumbersTarget.textContent = Array.from(
      { length: Math.max(this.editorTarget.value.split("\n").length, 1) },
      (_, index) => index + 1
    ).join("\n")
    this.validate()
  }

  syncScroll() { this.lineNumbersTarget.scrollTop = this.editorTarget.scrollTop }

  keydown(event) {
    if (event.key === "Tab") {
      event.preventDefault()
      this.insert("  ")
    } else if (event.key === "Enter") {
      event.preventDefault()
      const before = this.editorTarget.value.slice(0, this.editorTarget.selectionStart)
      this.insert(`\n${before.split("\n").pop().match(/^\s*/)?.[0] || ""}`)
    }
  }

  format() {
    try {
      this.editorTarget.value = JSON.stringify(JSON.parse(this.editorTarget.value), null, 2)
      this.update()
    } catch (_) {
      this.show("Fix invalid JSON before formatting", false)
    }
  }

  async suggest() {
    await this.request(this.suggestUrlValue, this.suggestButtonTarget, "Inspecting page…", {}, payload => {
      this.editorTarget.value = payload.rules
      this.update()
      const count = payload.matched_items === 1 ? "1 matched element" : `${payload.matched_items} matched elements`
      this.show(payload.cached ? `Cached recommendation reused · ${count}` : `Executable rules generated · ${count}`, true)
    })
  }

  async preview(event) {
    const refresh = event.currentTarget.dataset.refresh === "true"
    await this.request(
      this.testUrlValue,
      event.currentTarget,
      refresh ? "Refreshing page…" : "Building preview…",
      { refresh },
      payload => this.renderPreview(payload)
    )
  }

  async request(url, button, busyText, extraPayload, success) {
    const firstUrl = this.urlsTarget.value.split("\n").map(value => value.trim()).find(Boolean)
    if (!firstUrl) return this.show("Add a URL first", false)

    const oldText = button.textContent
    button.disabled = true
    button.textContent = busyText
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json",
          "Idempotency-Key": idempotencyKey()
        },
        body: JSON.stringify({
          url: firstUrl,
          instructions: this.instructionsTarget.value,
          output_schema: this.outputSchemaTarget.value,
          output_format: this.outputFormatTarget.value,
          selector_rules: this.editorTarget.value,
          setup_model: this.modelTarget.value,
          scrape_run_id: this.element.dataset.scrapeRunId,
          ...extraPayload
        })
      })
      const payload = await operationResult(response)
      success(payload)
    } catch (error) {
      this.show(error.message, false)
    } finally {
      button.disabled = false
      button.textContent = oldText
    }
  }

  renderPreview(payload) {
    const diagnostics = payload.diagnostics || {}
    const emitted = diagnostics.emitted_records ?? payload.matched_items
    this.previewTarget.textContent = payload.preview_text || JSON.stringify(payload.final_data || payload.data, null, 2)
    this.pagePreviewTarget.srcdoc = payload.preview_html || "<p>Page preview unavailable.</p>"
    this.matchCountTarget.textContent = `${payload.matched_items} matched · ${emitted} exported`
    this.outputLabelTarget.textContent = this.outputFormatTarget.value === "csv" ? "Final CSV data" : "Final JSON · one previewed URL"
    this.pageMetaTarget.textContent = this.pageDescription(payload.page)
    this.renderLegend(diagnostics.fields || {})
    this.renderDiagnostics(diagnostics)
    this.previewContainerTarget.classList.remove("hidden")
    this.show(payload.page?.refreshed ? "Fresh page downloaded and previewed" : "Preview built from the cached page", true)
  }

  renderLegend(fields) {
    const entries = Object.entries(fields)
    if (entries.length === 0) {
      this.legendTarget.replaceChildren()
      return
    }

    const label = this.elementNode("span", "font-semibold text-slate-500", "Highlights")
    const chips = entries.map(([name, details]) => {
      const chip = this.elementNode("span", "inline-flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1 font-medium text-slate-700 ring-1 ring-slate-200")
      const dot = this.elementNode("span", "size-2 rounded-full")
      dot.style.backgroundColor = details.color
      chip.append(dot, document.createTextNode(name))
      return chip
    })
    this.legendTarget.replaceChildren(label, ...chips)
  }

  renderDiagnostics(diagnostics) {
    const summary = this.elementNode("div", "grid gap-2 sm:grid-cols-3")
    summary.append(
      this.metric("Matched items", diagnostics.matched_items ?? 0),
      this.metric("Exported records", diagnostics.emitted_records ?? 0),
      this.metric("Empty records", diagnostics.empty_records ?? 0)
    )

    const fields = this.elementNode("div", "mt-4 divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200")
    Object.entries(diagnostics.fields || {}).forEach(([name, details]) => {
      const row = this.elementNode("div", "flex flex-col gap-1 px-3 py-2.5 text-xs sm:flex-row sm:items-center sm:justify-between")
      const fieldName = this.elementNode("span", "flex items-center gap-2 font-semibold text-slate-800")
      const dot = this.elementNode("span", "size-2 rounded-full")
      dot.style.backgroundColor = details.color
      fieldName.append(dot, document.createTextNode(name))
      const text = `${details.matched_items} with values · ${details.missing_items} missing · ${details.total_matches} DOM matches`
      row.append(fieldName, this.elementNode("span", "text-slate-500", text))
      fields.append(row)
    })

    const warnings = this.elementNode("div", "mt-4")
    const warningList = diagnostics.warnings || []
    if (warningList.length === 0) {
      warnings.append(this.elementNode("p", "rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5 text-xs font-medium text-emerald-800", "No selector warnings on this page."))
    } else {
      const title = this.elementNode("p", "mb-2 text-xs font-bold text-amber-900", "Review before running")
      const list = this.elementNode("ul", "space-y-1 rounded-xl border border-amber-200 bg-amber-50 px-5 py-3 text-xs leading-5 text-amber-900")
      warningList.forEach(warning => {
        const item = document.createElement("li")
        item.className = "list-disc"
        item.textContent = warning
        list.append(item)
      })
      warnings.append(title, list)
    }

    this.diagnosticsTarget.replaceChildren(summary, fields, warnings)
  }

  metric(label, value) {
    const element = this.elementNode("div", "rounded-xl bg-slate-50 px-3 py-2.5")
    element.append(
      this.elementNode("p", "text-[10px] font-bold uppercase tracking-wider text-slate-400", label),
      this.elementNode("p", "mt-1 text-lg font-bold text-slate-900", String(value))
    )
    return element
  }

  elementNode(tagName, className, text) {
    const element = document.createElement(tagName)
    element.className = className
    if (text !== undefined) element.textContent = text
    return element
  }

  pageDescription(page) {
    if (!page) return "Cached source HTML"
    const fetchedAt = page.fetched_at ? new Date(page.fetched_at).toLocaleString() : "unknown time"
    return `${page.title || page.url} · fetched ${fetchedAt}`
  }

  insert(text) {
    const start = this.editorTarget.selectionStart
    this.editorTarget.setRangeText(text, start, this.editorTarget.selectionEnd, "end")
    this.editorTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  validate() {
    try {
      JSON.parse(this.editorTarget.value)
      this.show("Valid selector JSON", true)
    } catch (error) {
      this.show(`Invalid JSON · ${error.message}`, false)
    }
  }

  show(message, valid) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-emerald-400", valid)
    this.statusTarget.classList.toggle("text-rose-400", !valid)
  }
}
