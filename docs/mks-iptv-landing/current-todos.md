# Current TODOs - MKS-IPTV Astro Landing Page Migration

## 📚 Methodology Reference
Following the engineering approach from:
- **General**: `src/PLAYBOOK-GENERAL.md` - 3-phase development methodology
- **Astro**: `PLAYBOOK-ASTRO.md` - Astro-specific patterns and guidelines

## ✅ Completed Tasks

### Phase 1: Project Setup & Documentation
- [x] Create commit with current changes to preserve work
- [x] Create new branch 'astro-landing-migration' for the refactor
- [x] Install Bun dependencies with latest versions from refactor doc
- [x] Update astro.config.mjs with GitHub Pages settings
- [x] Configure tsconfig.json with strict TypeScript + path aliases
- [x] Set up tailwind.config.ts with cyberpunk theme
- [x] Clean boilerplate and set up proper directory structure
- [x] Update main CLAUDE.md with Astro project information
- [x] Create landing-specific CLAUDE.md with proper references
- [x] Generate PLAYBOOK-ASTRO.md with development patterns
- [x] Align documentation with playbook methodology

## 🚧 In Progress

### Phase 2: Core Components Setup
- [x] Fix compilation error (Welcome.astro import removed)
- [ ] Create MainLayout.astro with SEO and ViewTransitions
- [ ] Create Header component with navigation
- [ ] Create Footer component
- [ ] Create 4 essential pages
- [ ] Setup basic navigation between pages

## 📋 Pending Tasks

### Phase 2: Core Layout Components (High Priority)

#### 2.0 IMMEDIATE: Project Compilation & Basic Structure
- [x] **Fix Compilation Error**: Remove Welcome.astro import from index.astro
- [ ] **Create 4 Essential Pages**: Home, Installation, Download, Screenshots
- [ ] **Basic Navigation**: Working navigation between all pages
- [ ] **Quality Verification**: Run bun run check and bun run build
- [ ] **Project Commit**: Commit working project with navigation
- [ ] **GitHub Pages Migration**: Setup proper deployment with Actions

#### 2.1 Documentation & LLM Support
- [ ] **Update GEMINI.md Files**: Create copies of CLAUDE.md for Gemini LLM
  - Main project: `/Users/mks/Documents/GitHub/MKS-IPTV-App/GEMINI.md`
  - Landing project: `/Users/mks/Documents/GitHub/MKS-IPTV-App/docs/mks-iptv-landing/GEMINI.md`
- [ ] **Add Development Rules**: Never run npm run dev (user handles in IDE)
- [ ] **Content Migration Reference**: Document original content location `/Users/mks/Documents/GitHub/MKS-IPTV-App/docs/`

#### 2.1 Base Layout System
- [ ] **Structure**: `src/layouts/MainLayout.astro` (Following PLAYBOOK-ASTRO.md mandatory structure)
  - **Implementation**: HTML5 semantic structure with ViewTransitions
  - **File Structure**: No additional files needed for layouts (different from components)
  - **Types**: TypeScript interfaces for layout props inline
  - **Responsive**: Mobile-first responsive design
  - **Accessibility**: ARIA landmarks and semantic HTML
  - **Performance**: Optimized for Core Web Vitals
  - **Documentation**: JSDoc in Spanish
  - **Integration**: SEO component integration
  - **Features**: Smooth scroll with Lenis, meta tags, Open Graph

#### 2.2 Navigation Header
- [ ] **Structure**: `src/components/layout/Header/` (MANDATORY: index.astro + styles.ts + types.ts)
  - **Implementation**: Responsive navigation with mobile menu
  - **Styles**: `styles.ts` with navigation, mobile menu, and theme toggle classes
  - **Types**: `types.ts` with NavigationItem, ThemeToggle interfaces  
  - **Responsive**: Breakpoint-aware navigation (mobile/desktop)
  - **Accessibility**: Keyboard navigation and ARIA support
  - **Performance**: Minimal JavaScript, smooth animations
  - **Documentation**: JSDoc in index.astro file
  - **Integration**: Theme system and smooth scroll integration
  - **Features**: Active section highlighting, dark/light mode toggle

#### 2.3 Footer Component
- [ ] **Structure**: `src/components/layout/Footer/` (MANDATORY: index.astro + styles.ts + types.ts)
  - **Implementation**: Footer with links and app store badges
  - **Styles**: `styles.ts` with footer layout, links, badges, and responsive classes
  - **Types**: `types.ts` with FooterLink, SocialMedia, AppStoreBadge interfaces
  - **Responsive**: Stacked mobile, columns desktop
  - **Accessibility**: Link descriptions and alt text
  - **Performance**: Optimized images and icons
  - **Documentation**: JSDoc in index.astro file
  - **Integration**: Theme consistency with header
  - **Features**: GitHub links, social media, copyright, license info

#### 2.4 SEO Component
- [ ] **Structure**: `src/components/layout/SEO/` (MANDATORY: index.astro + styles.ts + types.ts)
  - **Implementation**: Meta tags, Open Graph, Twitter Cards
  - **Styles**: `styles.ts` with any CSS-in-JS meta tag helpers (minimal)
  - **Types**: `types.ts` with SEOData, OpenGraphData, StructuredData interfaces
  - **Responsive**: Viewport meta configuration
  - **Accessibility**: Page title and meta descriptions
  - **Performance**: Critical SEO optimization
  - **Documentation**: JSDoc with SEO best practices
  - **Integration**: Layout integration with props
  - **Features**: JSON-LD structured data, social sharing optimization

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

- **Completed**: 12/16 setup and documentation tasks (75%)
- **In Progress**: 1 task (Core components implementation)
- **Pending**: 35+ implementation tasks following playbook patterns
- **Current Phase**: Phase 2 - Core Layout Components
- **Methodology**: Following PLAYBOOK-ASTRO.md Definition of Done criteria

## 🔧 Technical Notes

### Development Environment
- **Working Directory**: `docs/mks-iptv-landing/`
- **Tech Stack**: Astro 5.11 + TypeScript 5.8 + Tailwind CSS 3.4 + Bun
- **Build Target**: Static site optimized for GitHub Pages
- **Animation Libraries**: GSAP 3.13, Lenis 1.3.4, tsParticles 3.8.1
- **UI Components**: Embla Carousel, PhotoSwipe, Keen Slider

### Architecture Approach
- **Component Organization**: Atomic Design (layout/ → sections/ → ui/ → animations/)
- **Astro Patterns**: Static-first with Islands for interactivity
- **TypeScript**: Strict typing with path aliases (`@/components/*`)
- **Styling**: Tailwind CSS with organized style objects
- **Documentation**: JSDoc in Spanish for all components
- **Performance**: Core Web Vitals optimization priority

### Quality Assurance
- **Type Checking**: `bun run check` (must pass)
- **Build Verification**: `bun run build` (must pass)
- **Code Style**: `bun run lint` and `bun run format`
- **Accessibility**: ARIA compliance and keyboard navigation
- **Responsive**: Mobile-first, tested on all breakpoints