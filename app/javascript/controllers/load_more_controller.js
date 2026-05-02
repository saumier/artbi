import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "button", "loader"]
  static values  = {
    page:      { type: Number,  default: 1 },
    hasMore:   { type: Boolean, default: true },
    itemClass: { type: String,  default: "ev-card" },
    perPage:   { type: Number,  default: 6 }
  }

  async load() {
    this.buttonTarget.disabled = true
    this.loaderTarget.hidden = false

    const nextPage = this.pageValue + 1
    const url = this._buildUrl(nextPage)

    try {
      const response = await fetch(url, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" }
      })

      this.loaderTarget.hidden = true

      if (response.status === 204) {
        this.buttonTarget.hidden = true
        return
      }

      const html = await response.text()
      this.gridTarget.insertAdjacentHTML("beforeend", html)
      this.pageValue = nextPage

      const count = (html.match(new RegExp(`class="${this.itemClassValue}"`, "g")) || []).length
      if (count >= this.perPageValue) {
        this.buttonTarget.disabled = false
      } else {
        this.buttonTarget.hidden = true
      }
    } catch (err) {
      this.loaderTarget.hidden = true
      this.buttonTarget.disabled = false
      console.error("Load more fetch failed:", err)
    }
  }

  _buildUrl(page) {
    const url = new URL(window.location.href)
    url.searchParams.set("page",     page)
    url.searchParams.set("infinite", "1")
    return url.toString()
  }
}
