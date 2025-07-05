# Current TODOs - MKS-IPTV Astro Landing Page Migration

## ✅ Completed Tasks

### Phase 1: Project Setup
- [x] Create commit with current changes to preserve work
- [x] Create new branch 'astro-landing-migration' for the refactor
- [x] Install Bun dependencies with latest versions from refactor doc
- [x] Update astro.config.mjs with GitHub Pages settings
- [x] Configure tsconfig.json with strict TypeScript + path aliases
- [x] Set up tailwind.config.ts with cyberpunk theme
- [x] Clean boilerplate and set up proper directory structure
- [x] Update CLAUDE.md with Astro project information

## 🚧 In Progress

### Phase 2: Core Components Setup
- [ ] Create base components: Layout, Header, Footer, SEO

## 📋 Pending Tasks

### Phase 2: Core Layout Components (High Priority)

#### 2.1 Base Layout System
- [ ] **File**: `src/layouts/MainLayout.astro`
  - Implement HTML5 semantic structure
  - Add ViewTransitions component for page transitions
  - Include SEO meta tags and Open Graph
  - Set up smooth scroll with Lenis

#### 2.2 Navigation Header
- [ ] **File**: `src/components/layout/Header.astro`
  - Responsive navigation with mobile menu
  - Smooth scroll to sections
  - Active section highlighting
  - Dark/light mode toggle

#### 2.3 Footer Component
- [ ] **File**: `src/components/layout/Footer.astro`
  - Links to GitHub, documentation, social media
  - App store badges
  - Copyright and license information

#### 2.4 SEO Component
- [ ] **File**: `src/components/layout/SEO.astro`
  - Meta tags for SEO
  - Open Graph tags
  - Twitter Card meta
  - Structured data (JSON-LD)

### Phase 3: Hero Section Implementation (Medium Priority)

#### 3.1 Hero Component with GSAP
- [ ] **File**: `src/components/sections/Hero.astro`
  - Implement three-stage animation sequence
  - Particle background integration
  - Responsive video/image background
  - Call-to-action buttons

#### 3.2 GSAP Animation Scripts
- [ ] **File**: `src/scripts/gsap-animations.ts`
  - Hero entrance animations
  - ScrollTrigger for scroll-based animations
  - Parallax effects for background elements
  - Text reveal animations

#### 3.3 Particle Background
- [ ] **File**: `src/components/ui/ParticleBackground.astro`
  - tsParticles configuration
  - Cyberpunk-themed particle effects
  - Performance optimized settings
  - Responsive particle density

### Phase 4: Content Sections (Medium Priority)

#### 4.1 Features Showcase
- [ ] **File**: `src/components/sections/Features.astro`
  - Grid layout with feature cards
  - Icon animations on scroll
  - Responsive design for all devices
  - Interactive hover effects

#### 4.2 Screenshots Gallery
- [ ] **File**: `src/components/sections/Screenshots.astro`
  - PhotoSwipe lightbox integration
  - Platform-specific filtering (iOS, macOS, tvOS)
  - Lazy loading for performance
  - Thumbnail optimization

#### 4.3 Download Section
- [ ] **File**: `src/components/sections/Downloads.astro`
  - Platform-specific download buttons
  - File size and version information
  - Installation requirements
  - Direct download links

### Phase 5: Interactive Components (Low Priority)

#### 5.1 Image Gallery with PhotoSwipe
- [ ] **File**: `src/components/ui/Gallery.astro`
  - TypeScript integration
  - Responsive thumbnail grid
  - Zoom and pan functionality
  - Touch gesture support

#### 5.2 Carousel Component
- [ ] **File**: `src/components/ui/Carousel.astro`
  - Embla carousel implementation
  - Autoplay functionality
  - Navigation dots and arrows
  - Touch/swipe support

#### 5.3 Smooth Scroll Setup
- [ ] **File**: `src/scripts/smooth-scroll.ts`
  - Lenis initialization
  - GSAP ScrollTrigger integration
  - Performance optimization
  - Accessibility considerations

### Phase 6: Data and Content (Low Priority)

#### 6.1 Static Data Files
- [ ] **File**: `src/data/features.ts` - App features data
- [ ] **File**: `src/data/screenshots.ts` - Screenshot gallery data
- [ ] **File**: `src/data/downloads.ts` - Download links data

#### 6.2 Page-Specific Implementation
- [ ] **File**: `src/pages/index.astro` - Homepage combining all sections
- [ ] **File**: `src/pages/download.astro` - Detailed download page
- [ ] **File**: `src/pages/installation.astro` - Installation guide
- [ ] **File**: `src/pages/screenshots.astro` - Screenshots gallery page

### Phase 7: GitHub Pages Deployment (Low Priority)

#### 7.1 GitHub Actions Workflow
- [ ] **File**: `.github/workflows/deploy.yml`
  - Setup Bun in CI/CD
  - Build Astro project
  - Deploy to GitHub Pages
  - Configure deployment permissions

#### 7.2 Repository Configuration
- [ ] Enable GitHub Pages in repository settings
- [ ] Configure deployment source as GitHub Actions
- [ ] Set up custom domain if needed
- [ ] Configure branch protection rules

### Phase 8: Performance & SEO (Low Priority)

#### 8.1 Performance Optimization
- [ ] Image optimization with Astro Image component
- [ ] Implement lazy loading
- [ ] Code splitting and bundle optimization
- [ ] Add loading states

#### 8.2 SEO Implementation
- [ ] Add structured data (JSON-LD)
- [ ] Create XML sitemap
- [ ] Add robots.txt
- [ ] Implement meta tag optimization

#### 8.3 Testing & QA
- [ ] Cross-browser testing
- [ ] Performance testing with Lighthouse
- [ ] Core Web Vitals optimization
- [ ] Accessibility testing

## 🎯 Next Steps

1. **Immediate**: Complete base components (Layout, Header, Footer, SEO)
2. **Next**: Implement Hero section with GSAP animations
3. **Then**: Add content sections (Features, Screenshots, Downloads)
4. **Finally**: Set up deployment and optimization

## 📊 Progress Summary

- **Completed**: 8/10 initial setup tasks (80%)
- **In Progress**: 1 task (Core components)
- **Pending**: 35+ implementation tasks
- **Current Phase**: Phase 2 - Core Layout Components

## 🔧 Technical Notes

- **Working Directory**: `docs/mks-iptv-landing/`
- **Tech Stack**: Astro 5.11 + TypeScript 5.8 + Tailwind CSS 3.4 + Bun
- **Build Target**: Static site for GitHub Pages
- **Animation Libraries**: GSAP 3.13, Lenis 1.3.4, tsParticles 3.8.1
- **UI Components**: Embla Carousel, PhotoSwipe, Keen Slider