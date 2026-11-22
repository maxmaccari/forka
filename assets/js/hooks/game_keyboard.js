const GameKeyboard = {
  mounted() {
    this._onKeyDown = (e) => {
      if (e.ctrlKey || e.metaKey || e.altKey) return
      if (this.el.dataset.disabled === "true") return

      const target = e.target
      if (
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.tagName === "SELECT" ||
          target.isContentEditable)
      ) {
        return
      }

      const dialogs = document.querySelectorAll('[role="dialog"], [role="alertdialog"]')
      if (Array.from(dialogs).some((dialog) => dialog.getClientRects().length > 0)) {
        return
      }

      const folded = e.key
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toUpperCase()

      if (!/^[A-Z]$/.test(folded)) return

      const btn = this.el.querySelector(`[data-letter="${folded}"]:not(:disabled)`)
      if (btn) {
        e.preventDefault()
        btn.click()
      }
    }

    window.addEventListener("keydown", this._onKeyDown)
  },

  destroyed() {
    if (this._onKeyDown) {
      window.removeEventListener("keydown", this._onKeyDown)
    }
  }
}

export default GameKeyboard
