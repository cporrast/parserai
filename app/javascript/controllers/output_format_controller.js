import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "schema", "label", "help", "suggest", "format"]

  connect() {
    this.jsonDefault = this.schemaTarget.dataset.jsonValue || this.schemaTarget.value
    this.csvDefault = this.schemaTarget.dataset.csvValue || "name, price, description, url"
    this.render(false)
  }

  change() {
    this.render(true)
  }

  render(replaceValue) {
    const csv = this.selectTarget.value === "csv"
    this.labelTarget.textContent = csv ? "CSV columns" : "JSON Schema or example"
    this.helpTarget.textContent = csv
      ? "List columns separated by commas or new lines. ParserAI asks the model for rows and produces the CSV file."
      : "Provide a JSON Schema or an example JSON object. The model will return valid JSON matching this shape."
    if (this.hasSuggestTarget) this.suggestTarget.classList.toggle("hidden", csv)
    if (this.hasFormatTarget) this.formatTarget.classList.toggle("hidden", csv)

    if (replaceValue) {
      this.schemaTarget.value = csv ? this.csvDefault : this.jsonDefault
      this.schemaTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
