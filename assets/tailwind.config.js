// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/forka_web.ex",
    "../lib/forka_web/**/*.*ex",
    '../deps/backpex/**/*.*ex',
    '../deps/backpex/assets/js/**/*.*js'
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  plugins: [
    // require("@tailwindcss/forms")({strategy: 'class'}),
  ]
}
