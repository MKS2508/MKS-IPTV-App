# MKS-IPTV Landing Page - Astro Migration

[![Astro](https://img.shields.io/badge/Astro-5.11-FF5D01?style=flat&logo=astro)](https://astro.build/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.8-3178C6?style=flat&logo=typescript)](https://www.typescriptlang.org/)
[![Tailwind CSS](https://img.shields.io/badge/Tailwind-3.4-06B6D4?style=flat&logo=tailwindcss)](https://tailwindcss.com/)
[![Bun](https://img.shields.io/badge/Bun-Latest-000000?style=flat&logo=bun)](https://bun.sh/)

Modern landing page for MKS-IPTV-App built with Astro, TypeScript, and Tailwind CSS. This project replaces the Jekyll-based documentation with a high-performance, animated landing page featuring cyberpunk aesthetics and smooth interactions.

## 🎯 Project Overview

**Migration from Jekyll to Astro** for the MKS-IPTV-App landing page, featuring:
- 📱 **App Showcase**: Downloads, features, and installation guides
- 🎬 **Interactive Elements**: GSAP animations, smooth scrolling, particle effects
- 📸 **Media Gallery**: Screenshots with PhotoSwipe lightbox
- 🚀 **Performance**: Static-first with islands for interactivity
- 🎨 **Cyberpunk Theme**: Modern synthwave aesthetic

## 🏗️ Architecture & Methodology

This project follows a rigorous engineering approach with documented patterns:

### Development Methodology
- **📚 General**: [`src/PLAYBOOK-GENERAL.md`](src/PLAYBOOK-GENERAL.md) - 3-phase development methodology
- **⚛️ React Patterns**: [`src/PLAYBOOK-REACT.md`](src/PLAYBOOK-REACT.md) - Atomic design and component patterns
- **🚀 Astro Specific**: [`PLAYBOOK-ASTRO.md`](PLAYBOOK-ASTRO.md) - Astro-adapted development guidelines

### Component Architecture
**Mandatory Structure** for ALL components:
```
components/
└── ComponentName/
    ├── index.astro           # Main component file
    ├── styles.ts             # Tailwind classes organized (REQUIRED)
    └── types.ts              # TypeScript interfaces (REQUIRED)
```

### Atomic Design Organization
- **`layout/`**: Page structure components (Header, Footer, SEO)
- **`sections/`**: Complete page sections (Hero, Features, Screenshots)
- **`ui/`**: Reusable UI elements (Button, Card, Gallery)
- **`animations/`**: GSAP animation components
- **`interactive/`**: Client-side components (Islands pattern)

## 📁 Project Structure

```
mks-iptv-landing/
├── src/
│   ├── components/                 # Atomic Design organization
│   │   ├── layout/                 # Layout components
│   │   ├── sections/               # Page sections  
│   │   ├── ui/                     # Reusable UI components
│   │   ├── animations/             # GSAP animation components
│   │   └── interactive/            # Client-side interactive components
│   ├── layouts/
│   │   └── Layout.astro            # Main page layout
│   ├── pages/
│   │   ├── index.astro             # Homepage
│   │   ├── download.astro          # Download page
│   │   └── screenshots.astro       # Screenshots gallery
│   ├── scripts/                    # TypeScript utilities
│   │   ├── gsap-animations.ts      # GSAP configurations
│   │   ├── smooth-scroll.ts        # Lenis setup
│   │   └── particles-config.ts     # tsParticles config
│   ├── styles/
│   │   └── globals.css             # Global styles
│   ├── types/
│   │   └── global.d.ts             # Global type definitions
│   └── data/                       # Static data files
│       ├── features.ts             # App features data
│       ├── screenshots.ts          # Screenshot gallery data
│       └── downloads.ts            # Download links data
├── public/
│   ├── images/                     # Static images
│   ├── videos/                     # Demo videos
│   └── files/                      # App downloads (.ipa, .app.zip)
├── CLAUDE.md                       # Claude Code guidance
├── PLAYBOOK-ASTRO.md               # Astro development patterns
├── current-todos.md                # Current project tasks
├── refactor.astro.md               # Technical implementation plan
├── astro.config.mjs                # Astro configuration
├── tailwind.config.ts              # Tailwind CSS configuration
├── tsconfig.json                   # TypeScript configuration
└── package.json                    # Dependencies and scripts
```

## 🧞 Commands

All commands are run from the project root (`docs/mks-iptv-landing/`):

### Development
| Command | Action |
|:--------|:-------|
| `bun install` | Install dependencies |
| `bun dev` | Start development server at `localhost:4321` |
| `bun build` | Build production site to `./dist/` |
| `bun preview` | Preview production build locally |

### Quality Assurance
| Command | Action |
|:--------|:-------|
| `bun run check` | Astro type checking |
| `bun run lint` | ESLint + TypeScript validation |
| `bun run format` | Prettier code formatting |
| `bun run sync` | Sync Astro types |

### Deployment
| Command | Action |
|:--------|:-------|
| `bun run deploy` | Build and deploy to GitHub Pages |

## 🎨 Tech Stack

### Core Framework
- **[Astro 5.11](https://astro.build/)** - Static site generator with islands architecture
- **[TypeScript 5.8](https://www.typescriptlang.org/)** - Type-safe development with strict configuration
- **[Bun](https://bun.sh/)** - Ultra-fast package manager and runtime
- **[Tailwind CSS 3.4](https://tailwindcss.com/)** - Utility-first CSS framework

### Animation & Interaction
- **[GSAP 3.13](https://gsap.com/)** - Professional animation library
- **[Lenis 1.3.4](https://lenis.darkroom.engineering/)** - Smooth scroll library
- **[tsParticles 3.8.1](https://particles.js.org/)** - Particle system for backgrounds

### UI Components
- **[Embla Carousel 8.6.0](https://www.embla-carousel.com/)** - Touch-friendly carousels
- **[PhotoSwipe 5.4.4](https://photoswipe.com/)** - Image lightbox gallery
- **[Keen Slider 6.8.6](https://keen-slider.io/)** - Additional carousel options

## 🚀 Getting Started

### Prerequisites
- **Bun** (latest version recommended)
- **Node.js** v18+ (for compatibility)
- **Git** for version control

### Installation

1. **Navigate to the project directory:**
   ```bash
   cd /Users/mks/Documents/GitHub/MKS-IPTV-App/docs/mks-iptv-landing
   ```

2. **Install dependencies:**
   ```bash
   bun install
   ```

3. **Start development server:**
   ```bash
   bun dev
   ```

4. **Open browser:**
   Navigate to `http://localhost:4321`

### Development Workflow

1. **Read the methodology**: Review `PLAYBOOK-ASTRO.md` for component patterns
2. **Follow the structure**: All components must have `index.astro`, `styles.ts`, and `types.ts`
3. **Check quality**: Run `bun run check` and `bun run lint` before commits
4. **Document components**: Add JSDoc in Spanish to all components

## ⚡ Quality Standards

### Definition of Done
Every component must meet these criteria:

- [ ] **Mandatory Structure**: `index.astro` + `styles.ts` + `types.ts` in component folder
- [ ] **Implementation Complete**: Component functional and respects defined API
- [ ] **Styles Separated**: All Tailwind classes organized in `styles.ts`
- [ ] **Types Defined**: All props and interfaces in `types.ts`
- [ ] **Responsive Design**: Works on mobile, tablet, and desktop
- [ ] **Accessibility**: ARIA labels, keyboard navigation, semantic HTML
- [ ] **Performance**: Optimized for Core Web Vitals (LCP, FID, CLS)
- [ ] **Documentation**: JSDoc comments in Spanish
- [ ] **Build Verification**: `bun run check` and `bun run build` pass
- [ ] **Visual Verification**: Component displays correctly in browser
- [ ] **Integration**: Works with other system components

### Code Quality
- **TypeScript Strict**: Full type safety with Astro's type system
- **ESLint**: Code linting and style enforcement
- **Prettier**: Consistent code formatting
- **Accessibility**: WCAG compliance and keyboard navigation

## 🎯 Current Status

- **Phase**: Phase 2 - Core Layout Components
- **Progress**: 75% setup complete, ready for component implementation
- **Next**: Implement Header, Footer, SEO, and MainLayout components
- **Tracking**: See [`current-todos.md`](current-todos.md) for detailed progress

## 📚 Documentation

### Project Documentation
- **[CLAUDE.md](CLAUDE.md)** - Claude Code specific guidance for this project
- **[current-todos.md](current-todos.md)** - Current tasks and progress tracking
- **[refactor.astro.md](refactor.astro.md)** - Complete technical implementation plan

### Development Playbooks
- **[PLAYBOOK-ASTRO.md](PLAYBOOK-ASTRO.md)** - Astro component patterns and guidelines
- **[src/PLAYBOOK-GENERAL.md](src/PLAYBOOK-GENERAL.md)** - General development methodology
- **[src/PLAYBOOK-REACT.md](src/PLAYBOOK-REACT.md)** - React/atomic design patterns

### External References
- **[Astro Documentation](https://docs.astro.build/)** - Official Astro docs
- **[TypeScript in Astro](https://docs.astro.build/en/guides/typescript/)** - TypeScript integration
- **[Tailwind CSS](https://tailwindcss.com/docs)** - Utility classes reference

## 🔗 Integration

This landing page is part of the larger MKS-IPTV-App project:

- **Main Repository**: `/Users/mks/Documents/GitHub/MKS-IPTV-App`
- **Documentation Site**: https://MKS2508.github.io/MKS-IPTV-App/
- **Deployment**: GitHub Pages with GitHub Actions
- **Build Artifacts**: iOS .ipa and macOS .app files hosted in main repository

## 🤝 Contributing

When contributing to this project:

1. **Follow the playbooks**: Adhere to patterns in `PLAYBOOK-ASTRO.md`
2. **Use mandatory structure**: Every component needs the 3-file structure
3. **Document everything**: JSDoc in Spanish for all components
4. **Test thoroughly**: Run quality checks before committing
5. **Follow Definition of Done**: Complete all checklist items

## 📄 License

This project is licensed under GPL-3.0. See the main repository for full license details.