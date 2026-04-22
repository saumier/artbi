import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["btn"]

  onSubmit() {
    this.btnTarget.classList.add("ev-btn--loading")
    this.btnTarget.disabled = true
  }
}
