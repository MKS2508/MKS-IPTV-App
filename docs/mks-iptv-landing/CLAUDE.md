# CLAUDE.md - MKS-IPTV Landing Page

This file provides specific guidance for Claude Code when working with the Astro landing page implementation.

## Quick Reference

**Main Project Documentation**: `/Users/mks/Documents/GitHub/MKS-IPTV-App/CLAUDE.md`

**Current Working Directory**: `/Users/mks/Documents/GitHub/MKS-IPTV-App/docs/mks-iptv-landing/`

## Project Context

This is the **Astro landing page migration** for the MKS-IPTV-App project. The main repository contains documentation and build artifacts, while this subdirectory focuses on the modern landing page implementation.

### Key Files in This Directory

- `current-todos.md` - Current project tasks and progress tracking
- `refactor.astro.md` - Technical implementation plan for Astro migration
- `PLAYBOOK-ASTRO.md` - Astro-specific development patterns and guidelines
- `package.json` - Project dependencies and scripts
- `src/` - Source code directory with Astro components

## Development Workflow

### Starting Development
```bash
# From main repository directory
cd /Users/mks/Documents/GitHub/MKS-IPTV-App/docs/mks-iptv-landing

# Install dependencies
bun install

# Start development server
bun dev
```

### Build and Deploy
```bash
# Build for production
bun run build

# Preview production build
bun run preview

# Deploy to GitHub Pages
bun run deploy
```

## Project Status

**Current Phase**: Phase 2 - Core Components Setup  
**Progress**: 80% setup complete, implementing base layout components  
**Tech Stack**: Astro 5.11 + TypeScript 5.8 + Tailwind CSS 3.4 + Bun  

### Architecture Overview

This project follows atomic design principles adapted for Astro:

```
src/
├── components/
│   ├── layout/          # Layout components (Header, Footer, SEO)
│   ├── sections/        # Page sections (Hero, Features, Screenshots)
│   ├── ui/              # Reusable UI components
│   └── animations/      # GSAP animation components
├── layouts/             # Page layouts
├── pages/               # Route pages
├── scripts/             # TypeScript utilities
├── styles/              # Global styles
├── types/               # Type definitions
└── data/                # Static data files
```

## Development Methodology

This project follows the engineering methodology defined in the playbooks:

### Playbook References
- **General Methodology**: `./src/PLAYBOOK-GENERAL.md` - 3-phase development approach
- **React Patterns**: `./src/PLAYBOOK-REACT.md` - Atomic design and component patterns  
- **Astro Specific**: `./PLAYBOOK-ASTRO.md` - Astro-adapted development guidelines

### Component Structure
Following atomic design principles adapted for Astro:

#### MANDATORY Structure for ALL Components:
```
ComponentName/
├── index.astro          # Main component file (.astro)
├── styles.ts            # Tailwind classes organized (REQUIRED)
└── types.ts             # TypeScript interfaces (REQUIRED)
```

#### Interactive Components (with client-side logic):
```
InteractiveComponent/
├── index.astro          # Astro container
├── Interactive.tsx      # React/Vue island
├── styles.ts            # Shared Tailwind styles (REQUIRED)
└── types.ts             # Shared TypeScript types (REQUIRED)
```

**Important**: Every component MUST have its own `styles.ts` and `types.ts` files, even if minimal. This ensures consistency across the project.

### Development Principles
- **Static First**: Leverage Astro's static rendering for performance
- **Islands Pattern**: Use client-side hydration only when necessary
- **TypeScript Strict**: Full type safety with Astro's type system
- **Atomic Design**: Components organized as layout/ → sections/ → ui/ → animations/
- **Performance Focus**: Optimize for Core Web Vitals

### Styling Approach
- **Primary**: Tailwind CSS utility classes with organized style objects
- **Animations**: GSAP for complex animations, CSS for simple transitions
- **Responsive**: Mobile-first approach with breakpoint consistency
- **Theme**: Cyberpunk/synthwave aesthetic with CSS custom properties

### File Organization
- Use TypeScript path aliases (`@/components/*`, `@/layouts/*`, `@/scripts/*`)
- Follow naming conventions from `PLAYBOOK-ASTRO.md`
- Keep components focused, reusable, and well-documented
- Organize by atomic design categories

## Quality Standards

### Definition of Done (Astro Components)
Following the `PLAYBOOK-ASTRO.md` standards:

- [ ] **Implementation Complete**: Component `.astro` functional and respects defined API
- [ ] **TypeScript Types**: All props and interfaces properly typed
- [ ] **Responsive Design**: Works on mobile, tablet, and desktop
- [ ] **Accessibility**: ARIA labels, keyboard navigation, semantic HTML
- [ ] **Performance**: Optimized for Core Web Vitals (LCP, FID, CLS)
- [ ] **JSDoc Documentation**: Complete comments in Spanish
- [ ] **Build Verification**: `bun run check` and `bun run build` pass without errors
- [ ] **Visual Verification**: Component displays correctly in browser
- [ ] **Integration**: Works correctly with other system components

### Commands to Run
```bash
# Type checking
bun run check

# Linting
bun run lint

# Format code
bun run format
```

## Commit Guidelines

### Commit Message Format
**IMPORTANTE**: NUNCA agregar co-author ni menciones de "Generated with Claude Code" en los commits. Usar únicamente el formato estándar de Conventional Commits sin referencias a Claude o AI.

**Formato correcto:**
```
tipo(alcance): descripción corta

Cuerpo del commit explicando el porqué del cambio.
```

## Integration with Main Project

This landing page will be deployed as part of the main MKS-IPTV-App documentation site at:
`https://MKS2508.github.io/MKS-IPTV-App/`

### Key Relationships
- **Main CLAUDE.md**: Contains overall project context and Swift app architecture
- **Documentation Site**: This landing page replaces the Jekyll-based documentation
- **Build Artifacts**: App downloads and releases are managed in the main repository

## Next Steps

1. **Complete Core Components**: Layout, Header, Footer, SEO components
2. **Implement Hero Section**: GSAP animations and particle effects
3. **Add Content Sections**: Features, Screenshots, Downloads
4. **Setup Deployment**: GitHub Actions workflow for automated deployment

## References

- **Main Project**: `/Users/mks/Documents/GitHub/MKS-IPTV-App/CLAUDE.md`
- **Development Patterns**: `./PLAYBOOK-ASTRO.md`
- **Technical Plan**: `./refactor.astro.md`
- **Task Tracking**: `./current-todos.md`
- **Astro Documentation**: https://docs.astro.build/
- **TypeScript Guide**: https://docs.astro.build/en/guides/typescript/