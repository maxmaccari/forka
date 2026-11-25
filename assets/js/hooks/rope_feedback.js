const RopeFeedback = {
  mounted() {
    this.tries = Number(this.el.dataset.tries)
  },

  updated() {
    const nextTries = Number(this.el.dataset.tries)
    const reduced =
      typeof window !== "undefined" &&
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const svg = this.el.querySelector("svg")

    if (Number.isFinite(this.tries) && Number.isFinite(nextTries) && svg) {
      if (nextTries < this.tries && !reduced) {
        svg.classList.remove("forka-rope-hit")
        void svg.offsetWidth
        svg.classList.add("forka-rope-hit")
        clearTimeout(this._hitTimer)
        this._hitTimer = setTimeout(() => {
          svg.classList.remove("forka-rope-hit")
        }, 400)
      } else if (reduced || nextTries > this.tries) {
        clearTimeout(this._hitTimer)
        svg.classList.remove("forka-rope-hit")
      }
    }

    this.tries = nextTries
  },

  destroyed() {
    clearTimeout(this._hitTimer)
  }
}

export default RopeFeedback
