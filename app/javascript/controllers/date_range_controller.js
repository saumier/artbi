import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rangeInput", "btn", "customDates"]

  // Called when a preset/custom button is clicked
  select(event) {
    const value = event.currentTarget.dataset.value

    // Update the hidden <input name="date_range">
    this.rangeInputTarget.value = value

    // Sync active state across all buttons
    this.btnTargets.forEach(btn =>
      btn.classList.toggle("ev-daterange-btn--active", btn.dataset.value === value)
    )

    // Show custom date pickers only for "custom"
    const isCustom = value === "custom"
    this.customDatesTarget.hidden = !isCustom

    // Auto-submit presets immediately; for "custom" the user fills dates then hits Rechercher
    if (!isCustom) {
      this.element.closest("form").requestSubmit()
    }
  }
}
