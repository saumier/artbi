import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "hiddenValue", "hiddenType", "hiddenLabel"]
  static values  = { url: String, minLength: { type: Number, default: 1 } }

  connect() {
    this._timer     = null
    this._open      = false
    this._results   = []
    this._cursor    = -1
    this._bound_clickOutside = this._clickOutside.bind(this)
    document.addEventListener("click", this._bound_clickOutside)
  }

  disconnect() {
    clearTimeout(this._timer)
    document.removeEventListener("click", this._bound_clickOutside)
  }

  // ── Triggered by input event ───────────────────────────────────
  onInput() {
    const q = this.inputTarget.value.trim()

    // Clear any previous selection when the user edits the text
    this.hiddenValueTarget.value = ""
    this.hiddenTypeTarget.value  = ""
    this.hiddenLabelTarget.value = ""

    clearTimeout(this._timer)

    if (q.length < this.minLengthValue) {
      this._close()
      return
    }

    this._timer = setTimeout(() => this._fetch(q), 180)
  }

  // ── Keyboard navigation ────────────────────────────────────────
  onKeydown(event) {
    if (!this._open) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._moveCursor(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this._moveCursor(-1)
        break
      case "Enter":
        if (this._cursor >= 0) {
          event.preventDefault()
          this._selectIndex(this._cursor)
        }
        break
      case "Escape":
        this._close()
        break
    }
  }

  // ── Selecting an item ──────────────────────────────────────────
  pick(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10)
    this._selectIndex(idx)
  }

  // ── Private ────────────────────────────────────────────────────
  async _fetch(q) {
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
      const res  = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      this._results = await res.json()
      this._cursor  = -1
      this._render()
    } catch (_) {
      // network error — fail silently
    }
  }

  _render() {
    const list = this.dropdownTarget

    if (!this._results.length) {
      list.innerHTML = `<li class="ac-empty">Aucun résultat</li>`
      this._open = true
      list.hidden = false
      return
    }

    list.innerHTML = this._results.map((r, i) => {
      const icon = r.type === "province"
        ? `<svg class="ac-icon" viewBox="0 0 20 20" fill="currentColor"><path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z"/><path fill-rule="evenodd" d="M4 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm3 4a1 1 0 000 2h.01a1 1 0 100-2H7zm3 0a1 1 0 000 2h3a1 1 0 100-2h-3zm-3 4a1 1 0 100 2h.01a1 1 0 100-2H7zm3 0a1 1 0 100 2h3a1 1 0 100-2h-3z" clip-rule="evenodd"/></svg>`
        : `<svg class="ac-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/></svg>`

      const meta = r.province
        ? `<span class="ac-meta">${r.province}</span>`
        : `<span class="ac-meta ac-meta--province">Province</span>`

      return `<li class="ac-item" role="option" data-idx="${i}" data-action="click->autocomplete#pick mouseenter->autocomplete#highlight">
        ${icon}
        <span class="ac-label">${this._highlight(r.label)}</span>
        ${meta}
      </li>`
    }).join("")

    this._open = true
    list.hidden = false
  }

  _highlight(text) {
    const q = this.inputTarget.value.trim()
    if (!q) return text
    const re = new RegExp(`(${q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi")
    return text.replace(re, "<mark>$1</mark>")
  }

  _moveCursor(delta) {
    const items = this.dropdownTarget.querySelectorAll(".ac-item")
    if (!items.length) return

    this._cursor = Math.max(0, Math.min(this._cursor + delta, items.length - 1))
    items.forEach((el, i) => el.classList.toggle("ac-item--active", i === this._cursor))
    items[this._cursor]?.scrollIntoView({ block: "nearest" })
  }

  highlight(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10)
    this._cursor = idx
    this.dropdownTarget.querySelectorAll(".ac-item")
        .forEach((el, i) => el.classList.toggle("ac-item--active", i === idx))
  }

  _selectIndex(idx) {
    const r = this._results[idx]
    if (!r) return

    this.inputTarget.value     = r.label
    this.hiddenValueTarget.value = r.value
    this.hiddenTypeTarget.value  = r.type
    this.hiddenLabelTarget.value = r.label
    this._close()
  }

  _close() {
    this._open   = false
    this._cursor = -1
    this.dropdownTarget.hidden = true
    this.dropdownTarget.innerHTML = ""
  }

  _clickOutside(event) {
    if (!this.element.contains(event.target)) this._close()
  }
}
