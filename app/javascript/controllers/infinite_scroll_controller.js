import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "sentinel", "loader"]
  static values  = {
    page:      { type: Number,  default: 1 },
    hasMore:   { type: Boolean, default: true },
    itemClass: { type: String,  default: "ev-card" },
    perPage:   { type: Number,  default: 12 }
  }

  connect() {
    this._observer = new IntersectionObserver(
      entries => this._onIntersect(entries),
      { rootMargin: "300px" }   // start fetching 300px before sentinel enters viewport
    )
    if (this.hasSentinelTarget) {
      this._observer.observe(this.sentinelTarget)
      // On Turbo Drive navigation the observer fires before layout is finalised and
      // can miss a sentinel that is already in view.  A rAF fires after the first
      // paint so we always get an accurate visibility check.
      requestAnimationFrame(() => this._checkSentinelVisible())
    }
  }

  disconnect() {
    this._observer.disconnect()
  }

  // ── Private ────────────────────────────────────────────────────
  _onIntersect(entries) {
    if (!entries[0].isIntersecting) return
    if (!this.hasMoreValue)         return
    this._loadNext()
  }

  _checkSentinelVisible() {
    if (!this.hasSentinelTarget || !this.hasMoreValue) return
    const rect = this.sentinelTarget.getBoundingClientRect()
    if (rect.top < window.innerHeight + 300) {
      this._loadNext()
    }
  }

  async _loadNext() {
    this.hasMoreValue = false      // block re-entry while fetching
    this._showLoader()

    const nextPage = this.pageValue + 1
    const url = this._buildUrl(nextPage)

    try {
      const response = await fetch(url, { headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" } })

      this._hideLoader()

      if (response.status === 204) {   // no more content
        this._removeSentinel()
        return
      }

      const html = await response.text()
      this.gridTarget.insertAdjacentHTML("beforeend", html)
      this.pageValue = nextPage

      // If a full page was returned there may be more — re-arm the observer
      const count = (html.match(new RegExp(`class="${this.itemClassValue}"`, "g")) || []).length
      if (count >= this.perPageValue) {
        this.hasMoreValue = true
        // Sentinel may still be in view after new cards are inserted; check again.
        requestAnimationFrame(() => this._checkSentinelVisible())
      } else {
        this._removeSentinel()
      }
    } catch (err) {
      this._hideLoader()
      this.hasMoreValue = true   // allow retry on next scroll
      console.error("Infinite scroll fetch failed:", err)
    }
  }

  _buildUrl(page) {
    const url = new URL(window.location.href)
    url.searchParams.set("page",     page)
    url.searchParams.set("infinite", "1")
    return url.toString()
  }

  _showLoader() {
    this.loaderTarget.hidden = false
  }

  _hideLoader() {
    this.loaderTarget.hidden = true
  }

  _removeSentinel() {
    this.sentinelTarget.remove()
  }
}
