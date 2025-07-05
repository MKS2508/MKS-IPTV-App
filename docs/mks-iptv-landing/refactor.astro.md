# 🚀 Technical Implementation Plan: MKS-IPTV-App Landing Page Migration

## 📋 Project Overview

Migration from Jekyll to Astro + TypeScript + Bun for a **landing/project page** featuring downloads, functionality showcase, installation guides, and screenshots. Documentation remains on GitHub Wiki.

## 📚 Development Methodology

This implementation follows the established engineering patterns:
- **General Methodology**: `src/PLAYBOOK-GENERAL.md` - 3-phase development approach
- **Astro Patterns**: `PLAYBOOK-ASTRO.md` - Component structure and quality standards
- **Quality Assurance**: Definition of Done criteria for all components

## 🔧 Technical Stack with Latest 2025 Versions

### Core Framework

- **Astro 5.2** - Static site generator with islands architecture
- **TypeScript 5.8.3** - Type-safe development
- **Bun** - Ultra-fast package manager and runtime
- **Tailwind CSS 4.0** - Utility-first CSS with new Vite plugin

### Animation & Interaction Libraries

- **GSAP 3.13.0** - Animation library (now 100% FREE with all plugins)
- **Lenis 1.3.4** - Smooth scroll library
- **@tsparticles/engine 3.8.1** - Particle system
- **Embla Carousel 8.6.0** - Carousel component
- **PhotoSwipe 5.4.4** - Image lightbox

### Navigation & Transitions

- **@astrojs/view-transitions** - Page transitions
- **CSS View Transitions API** - Native browser transitions

## 📚 Documentation Links

### Core Framework Documentation

- [Astro 5.2 Documentation](https://docs.astro.build/en/getting-started/)
- [Astro TypeScript Guide](https://docs.astro.build/en/guides/typescript/)
- [Astro View Transitions](https://docs.astro.build/en/guides/view-transitions/)
- [Bun with Astro Guide](https://docs.astro.build/en/recipes/bun/)
- [Tailwind CSS 4.0 Documentation](https://tailwindcss.com/docs)
- [Tailwind with Astro Integration](https://docs.astro.build/en/guides/integrations-guide/tailwind/)

### Animation Libraries Documentation

- [GSAP 3.13 Documentation](https://gsap.com/docs/v3/)
- [GSAP ScrollTrigger](https://gsap.com/docs/v3/Plugins/ScrollTrigger/)
- [Lenis Documentation](https://lenis.darkroom.engineering/)
- [tsParticles Documentation](https://particles.js.org/docs/)
- [tsParticles React Integration](https://particles.js.org/docs/integrations/react/)

### UI Components Documentation

- [Embla Carousel Documentation](https://www.embla-carousel.com/)
- [PhotoSwipe Documentation](https://photoswipe.com/)
- [Keen Slider Documentation](https://keen-slider.io/)

### Deployment Documentation

- [Astro GitHub Pages Deployment](https://docs.astro.build/en/guides/deploy/github/)
- [GitHub Actions for Astro](https://docs.astro.build/en/guides/deploy/github/#github-actions)

## 🏗️ Detailed Project Structure (Following PLAYBOOK-ASTRO.md)

This structure implements atomic design principles adapted for Astro development:

```
mks-iptv-landing/
├── src/
│   ├── components/                     # Atomic Design organization
│   │   ├── layout/                     # Layout components (Atomic: Organisms)
│   │   │   ├── BaseLayout.astro        # Main layout wrapper
│   │   │   ├── Header.astro            # Navigation header
│   │   │   ├── Footer.astro            # Site footer
│   │   │   └── SEO.astro               # SEO meta tags
│   │   ├── sections/                   # Page sections (Atomic: Organisms)
│   │   │   ├── Hero.astro              # Hero section with GSAP
│   │   │   ├── Features.astro          # App features showcase
│   │   │   ├── Screenshots.astro       # Screenshot gallery
│   │   │   ├── Downloads.astro         # Download buttons/links
│   │   │   ├── Installation.astro      # Installation guide steps
│   │   │   └── TestFlight.astro        # TestFlight distribution
│   │   ├── ui/                         # Reusable UI components (Atomic: Molecules/Atoms)
│   │   │   ├── Button.astro            # Reusable button component
│   │   │   ├── Card.astro              # Feature cards
│   │   │   ├── Gallery.astro           # PhotoSwipe gallery
│   │   │   ├── Carousel.astro          # Embla carousel
│   │   │   ├── ParticleBackground.astro # tsParticles background
│   │   │   ├── SmoothScroll.astro      # Lenis smooth scroll
│   │   │   └── BackToTop.astro         # Scroll to top button
│   │   ├── animations/                 # GSAP animation components (Atomic: Molecules)
│   │   │   ├── FadeIn.astro            # GSAP fade animations
│   │   │   ├── SlideUp.astro           # GSAP slide animations
│   │   │   └── Parallax.astro          # Parallax scroll effects
│   │   └── interactive/                # Client-side interactive components (Islands)
│   │       ├── Carousel.tsx            # Interactive carousels (React/Vue)
│   │       ├── Lightbox.tsx            # PhotoSwipe integration
│   │       └── ScrollHandler.tsx       # Smooth scroll management
│   ├── layouts/
│   │   └── MainLayout.astro            # Main page layout
│   ├── pages/
│   │   ├── index.astro                 # Homepage
│   │   ├── download.astro              # Download page
│   │   ├── installation.astro          # Installation guide
│   │   ├── screenshots.astro           # Screenshots gallery
│   │   ├── ios-free-installation-guide.astro
│   │   └── testflight-distribution-guide.astro
│   ├── styles/
│   │   ├── globals.css                 # Global styles
│   │   ├── components.css              # Component styles
│   │   └── animations.css              # Animation styles
│   ├── scripts/
│   │   ├── main.ts                     # Main TypeScript entry
│   │   ├── gsap-animations.ts          # GSAP animation configs
│   │   ├── particles-config.ts         # tsParticles configuration
│   │   ├── smooth-scroll.ts            # Lenis smooth scroll setup
│   │   └── lightbox.ts                 # PhotoSwipe lightbox setup
│   ├── types/
│   │   ├── global.d.ts                 # Global type definitions
│   │   ├── components.ts               # Component type definitions
│   │   └── animations.ts               # Animation type definitions
│   └── data/
│       ├── features.ts                 # App features data
│       ├── screenshots.ts              # Screenshot gallery data
│       └── downloads.ts                # Download links data
├── public/
│   ├── images/
│   │   ├── hero/                       # Hero section images
│   │   ├── screenshots/                # App screenshots
│   │   ├── icons/                      # App icons
│   │   └── logos/                      # Brand logos
│   ├── videos/
│   │   └── hero-demo.mp4               # Hero video
│   └── files/
│       ├── MKS-IPTV.ipa                # iOS app file
│       └── MKS-IPTV.app.zip            # macOS app file
├── .github/
│   └── workflows/
│       └── deploy.yml                  # GitHub Actions deployment
├── astro.config.mjs                    # Astro configuration
├── tailwind.config.ts                  # Tailwind CSS configuration
├── tsconfig.json                       # TypeScript configuration
├── bun.lockb                           # Bun lockfile
└── package.json                        # Project dependencies
```

## 📦 Complete Package.json Configuration

```json
{
  "name": "mks-iptv-landing",
  "type": "module",
  "version": "1.0.0",
  "description": "MKS-IPTV-App Landing Page - Native Apple multiplatform IPTV client",
  "scripts": {
    "dev": "bunx --bun astro dev",
    "start": "bunx --bun astro dev",
    "build": "bunx --bun astro build",
    "preview": "bunx --bun astro preview",
    "check": "bunx --bun astro check",
    "sync": "bunx --bun astro sync",
    "lint": "bunx --bun astro check && bunx --bun tsc --noEmit",
    "format": "bunx --bun prettier --write .",
    "deploy": "bunx --bun astro build && bunx --bun gh-pages -d dist"
  },
  "dependencies": {
    "astro": "^5.2.0",
    "@astrojs/tailwind": "^6.0.2",
    "@astrojs/view-transitions": "^1.0.3",
    "@astrojs/sitemap": "^3.2.1",
    "tailwindcss": "^4.0.0",
    "gsap": "^3.13.0",
    "lenis": "^1.3.4",
    "@tsparticles/engine": "^3.8.1",
    "@tsparticles/confetti": "^3.8.1",
    "@tsparticles/basic": "^3.8.1",
    "embla-carousel": "^8.6.0",
    "embla-carousel-autoplay": "^8.6.0",
    "photoswipe": "^5.4.4",
    "keen-slider": "^6.8.6"
  },
  "devDependencies": {
    "typescript": "^5.8.3",
    "@types/node": "^20.14.0",
    "@types/bun": "^1.1.13",
    "bun-types": "^1.1.33",
    "@astrojs/ts-plugin": "^1.10.2",
    "prettier": "^3.3.3",
    "prettier-plugin-astro": "^0.14.1",
    "gh-pages": "^6.1.1"
  }
}
```

## ⚙️ Detailed Configuration Files

### 1. Astro Configuration (astro.config.mjs)

```javascript
import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';
import { viewTransitions } from '@astrojs/view-transitions';

export default defineConfig({
  site: 'https://MKS2508.github.io',
  base: '/MKS-IPTV-App',
  output: 'static',
  
  integrations: [
    tailwind({
      applyBaseStyles: false,
    }),
    sitemap(),
    viewTransitions(),
  ],

  vite: {
    optimizeDeps: {
      include: ['gsap', 'lenis', '@tsparticles/engine'],
    },
    build: {
      cssMinify: true,
      minify: 'esbuild',
      rollupOptions: {
        output: {
          assetFileNames: 'assets/[name].[hash][extname]',
          chunkFileNames: 'assets/[name].[hash].js',
          entryFileNames: 'assets/[name].[hash].js',
        },
      },
    },
  },

  build: {
    assets: 'assets',
  },
});
```

### 2. TypeScript Configuration (tsconfig.json)

```json
{
  "extends": "astro/tsconfigs/strictest",
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "strict": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "types": ["bun-types", "@types/bun", "@types/node"],
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@/components/*": ["src/components/*"],
      "@/layouts/*": ["src/layouts/*"],
      "@/scripts/*": ["src/scripts/*"],
      "@/types/*": ["src/types/*"],
      "@/data/*": ["src/data/*"],
      "@/styles/*": ["src/styles/*"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 3. Tailwind CSS Configuration (tailwind.config.ts)

```typescript
import type { Config } from 'tailwindcss';

export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f0f9ff',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          900: '#1e3a8a',
        },
        cyber: {
          purple: '#8B5CF6',
          pink: '#EC4899',
          blue: '#3B82F6',
          green: '#10B981',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-in-out',
        'slide-up': 'slideUp 0.5s ease-out',
        'slide-down': 'slideDown 0.5s ease-out',
        'scale-in': 'scaleIn 0.3s ease-out',
        'float': 'float 6s ease-in-out infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(30px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        slideDown: {
          '0%': { transform: 'translateY(-30px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        scaleIn: {
          '0%': { transform: 'scale(0.9)', opacity: '0' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-20px)' },
        },
      },
    },
  },
  plugins: [],
} satisfies Config;
```

## 🛠️ Detailed Implementation To-Dos

### Phase 1: Project Setup

#### 1.1 Initialize Astro Project with Bun

```bash
# Create new Astro project
bunx create-astro@latest mks-iptv-landing

# Navigate to project directory
cd mks-iptv-landing

# Install dependencies with Bun
bun install

# Add TypeScript support
bun add -d typescript @types/node @types/bun bun-types

# Add Astro integrations
bun add @astrojs/tailwind @astrojs/view-transitions @astrojs/sitemap

# Add animation libraries
bun add gsap lenis @tsparticles/engine @tsparticles/confetti @tsparticles/basic

# Add UI component libraries
bun add embla-carousel embla-carousel-autoplay photoswipe keen-slider

# Add development dependencies
bun add -d prettier prettier-plugin-astro gh-pages
```

#### 1.2 Configure Base Files

- Create `astro.config.mjs` with GitHub Pages configuration
- Set up `tsconfig.json` with strict TypeScript settings
- Configure `tailwind.config.ts` with custom theme
- Create `src/types/global.d.ts` for type definitions

#### 1.3 Set Up Directory Structure

- Create all directories as specified in project structure
- Set up path aliases in TypeScript configuration
- Create index files for each major directory

### Phase 2: Core Layout Components

#### 2.1 Base Layout System

- **File**: `src/layouts/MainLayout.astro`
  - Implement HTML5 semantic structure
  - Add ViewTransitions component for page transitions
  - Include SEO meta tags and Open Graph
  - Set up smooth scroll with Lenis

#### 2.2 Navigation Header

- **File**: `src/components/layout/Header.astro`
  - Responsive navigation with mobile menu
  - Smooth scroll to sections
  - Active section highlighting
  - Dark/light mode toggle

#### 2.3 Footer Component

- **File**: `src/components/layout/Footer.astro`
  - Links to GitHub, documentation, social media
  - App store badges
  - Copyright and license information

### Phase 3: Hero Section Implementation

#### 3.1 Hero Component with GSAP

- **File**: `src/components/sections/Hero.astro`
  - Implement three-stage animation sequence
  - Particle background integration
  - Responsive video/image background
  - Call-to-action buttons

#### 3.2 GSAP Animation Scripts

- **File**: `src/scripts/gsap-animations.ts`
  - Hero entrance animations
  - ScrollTrigger for scroll-based animations
  - Parallax effects for background elements
  - Text reveal animations

#### 3.3 Particle Background

- **File**: `src/components/ui/ParticleBackground.astro`
  - tsParticles configuration
  - Cyberpunk-themed particle effects
  - Performance optimized settings
  - Responsive particle density

### Phase 4: Content Sections

#### 4.1 Features Showcase

- **File**: `src/components/sections/Features.astro`
  - Grid layout with feature cards
  - Icon animations on scroll
  - Responsive design for all devices
  - Interactive hover effects

#### 4.2 Screenshots Gallery

- **File**: `src/components/sections/Screenshots.astro`
  - PhotoSwipe lightbox integration
  - Platform-specific filtering (iOS, macOS, tvOS)
  - Lazy loading for performance
  - Thumbnail optimization

#### 4.3 Download Section

- **File**: `src/components/sections/Downloads.astro`
  - Platform-specific download buttons
  - File size and version information
  - Installation requirements
  - Direct download links

### Phase 5: Interactive Components

#### 5.1 Image Gallery with PhotoSwipe

- **File**: `src/components/ui/Gallery.astro`
  - TypeScript integration
  - Responsive thumbnail grid
  - Zoom and pan functionality
  - Touch gesture support

#### 5.2 Carousel Component

- **File**: `src/components/ui/Carousel.astro`
  - Embla carousel implementation
  - Autoplay functionality
  - Navigation dots and arrows
  - Touch/swipe support

#### 5.3 Smooth Scroll Setup

- **File**: `src/scripts/smooth-scroll.ts`
  - Lenis initialization
  - GSAP ScrollTrigger integration
  - Performance optimization
  - Accessibility considerations

### Phase 6: Page-Specific Implementation

#### 6.1 Homepage (index.astro)

- Combine all sections: Hero, Features, Screenshots, Downloads
- Implement page-specific animations
- Add structured data for SEO
- Performance optimization

#### 6.2 Download Page

- Detailed download information
- System requirements
- Installation instructions
- Troubleshooting guide

#### 6.3 Installation Guide Pages

- Step-by-step installation process
- Platform-specific instructions
- Screenshots and video guides
- FAQ section

### Phase 7: GitHub Pages Deployment

#### 7.1 GitHub Actions Workflow

- **File**: `.github/workflows/deploy.yml`

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [ main ]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup Bun
        uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest
          
      - name: Install dependencies
        run: bun install
        
      - name: Build with Astro
        run: bun run build
        
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./dist

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

#### 7.2 Repository Configuration

- Enable GitHub Pages in repository settings
- Configure deployment source as GitHub Actions
- Set up custom domain if needed
- Configure branch protection rules

### Phase 8: Performance Optimization

#### 8.1 Image Optimization

- Use Astro's built-in Image component
- Implement lazy loading
- Generate multiple image formats (WebP, AVIF)
- Optimize image sizes for different devices

#### 8.2 JavaScript Optimization

- Implement code splitting
- Use Astro islands for interactive components
- Minimize bundle size
- Add loading states

#### 8.3 CSS Optimization

- Use Tailwind's purge feature
- Implement critical CSS
- Minimize unused styles
- Use CSS custom properties

### Phase 9: SEO & Accessibility

#### 9.1 SEO Implementation

- Add structured data (JSON-LD)
- Implement Open Graph tags
- Create XML sitemap
- Add robots.txt

#### 9.2 Accessibility Features

- Add ARIA labels and descriptions
- Ensure keyboard navigation
- Implement focus management
- Add alt text for images

### Phase 10: Testing & Quality Assurance

#### 10.1 Cross-Browser Testing

- Test on Chrome, Firefox, Safari, Edge
- Verify View Transitions API fallbacks
- Test on different screen sizes
- Validate HTML and CSS

#### 10.2 Performance Testing

- Lighthouse audit
- Core Web Vitals optimization
- Load time optimization
- Bundle size analysis

## 🎯 Key Implementation Notes

1. **File Organization**: Keep components small and focused on single responsibilities
2. **TypeScript Usage**: Use strict typing throughout, especially for data structures
3. **Animation Performance**: Use GSAP for complex animations, CSS for simple ones
4. **Responsive Design**: Mobile-first approach with Tailwind utilities
5. **Accessibility**: Ensure all interactive elements are keyboard accessible
6. **Performance**: Optimize images and use lazy loading extensively
7. **SEO**: Implement structured data and meta tags for better search visibility

## 🚀 Expected Outcomes

- **Loading Speed**: Sub-2 second initial load
- **Bundle Size**: < 500KB gzipped
- **Performance Score**: 95+ Lighthouse score
- **Cross-Browser Support**: 95%+ compatibility
- **Mobile Responsiveness**: Perfect on all devices
- **SEO Score**: 100/100 technical SEO

This detailed plan provides a comprehensive roadmap for migrating from Jekyll to a modern Astro-based landing page with all the latest 2025 technologies and best practices.