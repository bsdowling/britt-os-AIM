import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Brand tokens — PRD §11
        ink: "#2c3e47",
        sage: "#7c8b60",
        sand: "#d6bfaa",
        mist: "#ececec",
        slate: "#444444",
        alert: "#a4453a",
        paper: "#fdfdfc",
      },
      fontFamily: {
        heading: ["var(--font-heading)", "Montserrat", "sans-serif"],
        body: ["var(--font-body)", "Inter", "sans-serif"],
      },
      borderRadius: {
        card: "8px",
        btn: "6px",
        chip: "4px",
      },
      boxShadow: {
        panel: "0 1px 2px rgba(44,62,71,0.06)",
      },
      spacing: {
        panel: "24px",
      },
    },
  },
  plugins: [],
};

export default config;
