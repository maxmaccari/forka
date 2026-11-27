const SUBMIT_SELECTOR = 'button:not([type]), button[type="submit"], input[type="submit"]'
const RECOVERY_TIMEOUT_MS = 8000

// Native POST forms get no phx-disable-with from LiveView, so a double click posts twice.
// Browsers emit no reliable event when a navigation is stopped, so restore the submit
// controls after a bounded delay if the page is still active.
const PreventDoubleSubmit = {
  mounted() {
    this._submitting = false
    this._savedControls = []
    this._recoveryTimer = null

    this._restore = () => {
      clearTimeout(this._recoveryTimer)
      this._recoveryTimer = null
      this._submitting = false

      if (!this.el.isConnected) {
        this._cleanupListeners()
        this._savedControls = []
        return
      }

      this._savedControls.forEach(({ control, isInput, originalLabel, wasDisabled }) => {
        if (originalLabel !== null) {
          if (isInput) {
            control.value = originalLabel
          } else {
            control.textContent = originalLabel
          }
        }

        control.disabled = wasDisabled
      })

      this._savedControls = []
    }

    this._onSubmit = (event) => {
      if (event.defaultPrevented) return

      if (this._submitting) {
        event.preventDefault()
        return
      }

      this._submitting = true
      this._savedControls = []

      this.el.querySelectorAll(SUBMIT_SELECTOR).forEach((control) => {
        const disableText = control.getAttribute("phx-disable-with")
        const isInput = control.tagName === "INPUT"
        const originalLabel = disableText ? (isInput ? control.value : control.textContent) : null

        this._savedControls.push({
          control,
          isInput,
          originalLabel,
          wasDisabled: control.disabled
        })

        if (disableText) {
          if (isInput) {
            control.value = disableText
          } else {
            control.textContent = disableText
          }
        }

        control.disabled = true
      })

      clearTimeout(this._recoveryTimer)
      this._recoveryTimer = setTimeout(this._restore, RECOVERY_TIMEOUT_MS)
    }

    this._onPageShow = (event) => {
      if (event.persisted && this._submitting) {
        this._restore()
      }
    }

    this.el.addEventListener("submit", this._onSubmit)
    window.addEventListener("pageshow", this._onPageShow)
  },

  destroyed() {
    // LiveSocket unloads and destroys hooks on a native submit while the document is
    // still open; keep the recovery timer and guard active until unload or recovery.
    if (!this._submitting) {
      clearTimeout(this._recoveryTimer)
      this._recoveryTimer = null
      this._cleanupListeners()
    }
  },

  _cleanupListeners() {
    if (this._onSubmit) {
      this.el.removeEventListener("submit", this._onSubmit)
    }

    if (this._onPageShow) {
      window.removeEventListener("pageshow", this._onPageShow)
    }
  }
}

export default PreventDoubleSubmit
