import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "content", "loader", "title", "footer"]
  static values  = { detailsUrl: String }

  connect() {
    this._onBeforeCache = () => this._reset()
    document.addEventListener("turbo:before-cache", this._onBeforeCache)
    this._reset()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._onBeforeCache)
  }

  async open({ params: { name, url, image, uri, startDate, startTime, endDate, locationName, city, province } }) {
    this.titleTarget.textContent = name ?? ""
    this.contentTarget.innerHTML = ""
    this.footerTarget.innerHTML  = ""
    this.footerTarget.hidden     = true
    this.loaderTarget.hidden     = false
    this.dialogTarget.showModal()

    try {
      const ep = new URL(this.detailsUrlValue, location.origin)
      if (url)          ep.searchParams.set("url",           url)
      if (image)        ep.searchParams.set("image",         image)
      if (uri)          ep.searchParams.set("uri",           uri)
      if (startDate)    ep.searchParams.set("start_date",    startDate)
      if (startTime)    ep.searchParams.set("start_time",    startTime)
      if (endDate)      ep.searchParams.set("end_date",      endDate)
      if (locationName) ep.searchParams.set("location_name", locationName)
      if (city)         ep.searchParams.set("city",          city)
      if (province)     ep.searchParams.set("province",      province)

      const res = await fetch(ep, { headers: { Accept: "text/html" } })
      if (!res.ok) throw new Error()
      this.contentTarget.innerHTML = await res.text()
      this._afterLoad()
    } catch {
      this.contentTarget.innerHTML =
        '<p class="ev-modal__error">Impossible de charger les détails.</p>'
    } finally {
      this.loaderTarget.hidden = true
    }
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  expandDescription(event) {
    const desc = this.contentTarget.querySelector(".ev-modal__description--collapsed")
    if (desc) desc.classList.remove("ev-modal__description--collapsed")
    event.currentTarget.hidden = true
  }

  _reset() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
    if (this.hasContentTarget) this.contentTarget.innerHTML = ""
    if (this.hasFooterTarget) {
      this.footerTarget.innerHTML = ""
      this.footerTarget.hidden    = true
    }
  }

  _afterLoad() {
    // Move links out of scrollable body into the fixed footer target
    const linksEl = this.contentTarget.querySelector(".ev-modal__links")
    if (linksEl) {
      this.footerTarget.appendChild(linksEl)
      this.footerTarget.hidden = false
    }

    // Hide "read more" if description isn't actually truncated
    const desc = this.contentTarget.querySelector(".ev-modal__description--collapsed")
    const btn  = this.contentTarget.querySelector(".ev-modal__read-more")
    if (desc && btn) {
      if (desc.scrollHeight <= desc.clientHeight + 2) btn.hidden = true
    }
  }
}
