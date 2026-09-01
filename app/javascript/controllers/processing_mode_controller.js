import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "llmPanel", "selectorPanel"]

  connect() { this.change() }

  change() {
    const selectors = this.selectTarget.value === "selectors"
    this.llmPanelTargets.forEach(panel => panel.classList.toggle("hidden", selectors))
    this.selectorPanelTargets.forEach(panel => panel.classList.toggle("hidden", !selectors))
  }
}
