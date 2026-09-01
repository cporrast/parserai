import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    event.preventDefault()
    const selected = Number(event.currentTarget.dataset.index)

    this.tabTargets.forEach((tab, index) => {
      tab.classList.toggle("bg-slate-950", index === selected)
      tab.classList.toggle("text-white", index === selected)
      tab.classList.toggle("text-slate-500", index !== selected)
    })
    this.panelTargets.forEach((panel, index) => panel.classList.toggle("hidden", index !== selected))
  }
}
