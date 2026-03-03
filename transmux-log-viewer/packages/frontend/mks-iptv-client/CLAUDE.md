# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Template Context

This repository is a **submodule of `/Users/mks/mks-scaffolder`** and serves as a template for generating new React projects. The scaffolder replaces these template variables:

| Variable | Description | Location |
|----------|-------------|----------|
| `mks-iptv-client` | Package name | `package.json` |
| `Mks Iptv Client` | Display title | `index.html`, `src/App.tsx` |
| `log viewer and iptv client player for debug and testing purposes. maybe a future iptv client web` | Project description | `package.json`, `README.md`, `index.html`, `src/App.tsx` |
| `MKS2508` | Author name | `package.json` |

## Development Commands

```bash
bun run dev      # Start development server (Vite)
bun run build    # Type-check + production build (tsc -b && vite build)
bun run lint     # Run ESLint
bun run preview  # Preview production build locally
```

## Stack

| Tool | Version | Notes |
|------|---------|-------|
| React | 19.2 | Latest with StrictMode |
| Vite | 8.0.0-beta | Experimental beta |
| Tailwind CSS | v4 | Using `@tailwindcss/vite` plugin |
| TypeScript | 5.9 | Strict mode enabled |
| @mks2508/mks-ui | latest | BaseUI-based component library |

## Architecture

### Entry Points

- `src/main.tsx` - App entry, wraps `App` with `AppThemeProvider`
- `src/App.tsx` - Main application component with header, tabs, feature cards
- `src/index.css` - Tailwind imports + CSS variables for theming

### Path Aliases

- `@/*` maps to `./src/*` (configured in `tsconfig.json` and `vite.config.ts`)

### Theme System

The app uses `@mks2508/theme-manager-react` for theming:

- `src/providers/ThemeProvider.tsx` - Wraps the app with `ThemeProvider`, defaults to `synthwave84` theme
- `public/registry.json` - Theme registry with 4 built-in themes
- `public/themes/` - CSS files for each theme variant (light/dark)

Animation presets: `wipe`, `circle-expand`, `circle-shrink`, `diamond`, `crossfade`, `gif-mask`, `slide`, `none`

### Component Sources

| Source | Usage |
|--------|-------|
| `@mks2508/mks-ui/react` | Primary UI components (Button, Card, Dialog, etc.) |
| `@mks2508/theme-manager-react` | Theme hooks and SettingsModal |
| `src/components/animate-ui/` | Local animated components (theme-toggler, button, particles) |
| `lucide-react` | Icon library |
| `@hugeicons/react` + `@hugeicons/core-free-icons` | Alternative icon system |

## Critical: Tailwind v4 Consumer Setup

`@mks2508/mks-ui` ships compiled JS with Tailwind class strings. Tailwind v4's `@tailwindcss/vite` plugin **does not scan `node_modules` by default**.

The following directive in `src/index.css` is **required**:

```css
@source "../node_modules/@mks2508/mks-ui/dist";
```

Without this, component utility classes will not be generated and components will render unstyled.

## Theme CSS Variables

The app uses OKLCH color space for CSS variables. Base variables in `:root` (light) and `.dark` (dark mode):

- `--background`, `--foreground`
- `--card`, `--card-foreground`
- `--primary`, `--primary-foreground`
- `--secondary`, `--secondary-foreground`
- `--muted`, `--muted-foreground`
- `--accent`, `--accent-foreground`
- `--destructive`
- `--border`, `--input`, `--ring`
- `--radius`

## Adding New Themes

Install themes from TweakCN or custom registries:

```bash
bun run install-theme https://tweakcn.com/r/themes/your-theme.json
```

This updates `public/registry.json` and adds CSS files to `public/themes/`.

## React-Grab Integration

The template includes `react-grab` and `@react-grab/mcp/client` for MCP-based component grabbing in development mode (loaded in `index.html`).
