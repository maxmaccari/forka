const DOUBLE_SUBMIT_WINDOW_MS = 1000
const ACTIVE_LISTENERS = new WeakMap()

// Native POST forms bypass LiveView's phx-submit locking, so a rapid double click
// posts twice. Suppress repeat submits inside a short window while keeping the
// button enabled so a stopped submission can be retried once the window elapses.
const PreventDoubleSubmit = {
  mounted() {
    const previous = ACTIVE_LISTENERS.get(this.el)
    if (previous) {
      this.el.removeEventListener("submit", previous)
      ACTIVE_LISTENERS.delete(this.el)
    }

    this._lastSubmitAt = null

    this._onSubmit = (event) => {
      if (event.defaultPrevented) return

      const now = performance.now()

      if (this._lastSubmitAt !== null && now - this._lastSubmitAt < DOUBLE_SUBMIT_WINDOW_MS) {
        event.preventDefault()
        return
      }

      this._lastSubmitAt = now
    }

    ACTIVE_LISTENERS.set(this.el, this._onSubmit)
    this.el.addEventListener("submit", this._onSubmit)
  },

  destroyed() {
    // LiveSocket unloads and destroys hooks on a native submit while the document is
    // still open; keep the listener active if this form has submitted, and remove it
    // on genuine unmount.
    if (this._lastSubmitAt === null && this._onSubmit) {
      this.el.removeEventListener("submit", this._onSubmit)

      if (ACTIVE_LISTENERS.get(this.el) === this._onSubmit) {
        ACTIVE_LISTENERS.delete(this.el)
      }
    }
  }
}

export default PreventDoubleSubmit
