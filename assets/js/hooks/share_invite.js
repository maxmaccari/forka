const ShareInvite = {
  mounted() {
    this._copyBtn = this.el.querySelector("[data-copy-invite]")
    this._shareBtn = this.el.querySelector("[data-share-invite]")
    this._statusEl = this.el.querySelector("[data-share-status]")
    this._inputEl = this.el.querySelector("#room-invite-url")

    this._onCopy = async () => {
      const url = this._inviteUrl()
      if (!url) return

      try {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
          await navigator.clipboard.writeText(url)
          this._setStatus("Link copiado! Mande no grupo da turma.")
        } else if (this._fallbackCopy()) {
          this._setStatus("Link copiado! Mande no grupo da turma.")
        } else {
          this._setStatus("Não foi possível copiar o link. Copie o endereço acima.")
        }
      } catch (_err) {
        if (this._fallbackCopy()) {
          this._setStatus("Link copiado! Mande no grupo da turma.")
        } else {
          this._setStatus("Não foi possível copiar o link. Copie o endereço acima.")
        }
      }
    }

    this._onShare = async () => {
      const url = this._inviteUrl()
      if (!url || typeof navigator.share !== "function") return

      try {
        await navigator.share({
          title: this.el.dataset.title || "Forka",
          url
        })
        this._setStatus("Convite compartilhado!")
      } catch (err) {
        if (err && err.name !== "AbortError") {
          this._setStatus("Não foi possível compartilhar. Use Copiar link.")
        }
      }
    }

    if (this._copyBtn) {
      this._copyBtn.addEventListener("click", this._onCopy)
    }

    if (this._shareBtn && typeof navigator.share === "function") {
      this._shareBtn.classList.remove("hidden")
      this._shareBtn.addEventListener("click", this._onShare)
    }
  },

  destroyed() {
    if (this._copyBtn && this._onCopy) {
      this._copyBtn.removeEventListener("click", this._onCopy)
    }

    if (this._shareBtn && this._onShare) {
      this._shareBtn.removeEventListener("click", this._onShare)
    }
  },

  _inviteUrl() {
    return (this._inputEl && this._inputEl.value) || this.el.dataset.url || ""
  },

  _fallbackCopy() {
    if (!this._inputEl) return false
    this._inputEl.focus()
    this._inputEl.select()
    try {
      return document.execCommand("copy")
    } catch (_err) {
      return false
    }
  },

  _setStatus(message) {
    if (this._statusEl) {
      this._statusEl.textContent = message
    }
  }
}

export default ShareInvite
