const RopeFeedback = {
  mounted() {
    this.tries = Number(this.el.dataset.tries)
  },

  updated() {
    const nextTries = Number(this.el.dataset.tries)
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (nextTries < this.tries && !reduced) {
      const svg = this.el.querySelector("svg")
      if (svg) {
        svg.classList.remove("forka-rope-hit")
        void svg.offsetWidth
        svg.classList.add("forka-rope-hit")
        clearTimeout(this._hitTimer)
        this._hitTimer = setTimeout(() => {
          svg.classList.remove("forka-rope-hit")
        }, 360)
      }
    }

    this.tries = nextTries
  },

  destroyed() {
    clearTimeout(this._hitTimer)
  }
}

export default RopeFeedback
