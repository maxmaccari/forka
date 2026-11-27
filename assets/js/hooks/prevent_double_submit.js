const SUBMIT_SELECTOR = 'button:not([type]), button[type="submit"], input[type="submit"]'

// Native POST forms get no phx-disable-with from LiveView, so a double click posts twice.
const PreventDoubleSubmit = {
  mounted() {
    this._onSubmit = () => {
      this.el.querySelectorAll(SUBMIT_SELECTOR).forEach((btn) => {
        const disableText = btn.getAttribute("phx-disable-with")
        if (disableText) btn.textContent = disableText
        btn.disabled = true
      })
    }

    this.el.addEventListener("submit", this._onSubmit)
  },

  destroyed() {
    this.el.removeEventListener("submit", this._onSubmit)
  }
}

export default PreventDoubleSubmit
