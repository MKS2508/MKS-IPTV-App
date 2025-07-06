# Hero Component Implementation Guide

## Overview

Implementation guide for creating a Hero component with GSAP animations, scroll effects, and modern interactions following the project's architectural patterns.

## Technical Stack

### Core Libraries
- **Astro 5.11**: Component framework with islands architecture
- **GSAP 3.13**: Animation library for smooth transitions and effects
- **Lenis 1.3.4**: Smooth scrolling library
- **tsParticles 3.8.1**: Particle system for background effects
- **Tailwind CSS 3.4**: Utility-first CSS framework with custom color system

### Architecture Pattern
Following the mandatory 3-file component structure:
- `index.astro` - Main component template
- `styles.ts` - Organized Tailwind classes and component styles
- `types.ts` - TypeScript interfaces and type definitions

## Implementation Tasks

### 1. Create Hero Component Structure

#### 1.1 Create Base Files
```bash
mkdir -p src/components/sections/Hero
touch src/components/sections/Hero/index.astro
touch src/components/sections/Hero/styles.ts
touch src/components/sections/Hero/types.ts
```

#### 1.2 Define Types Interface
**File:** `src/components/sections/Hero/types.ts`
```typescript
export interface HeroProps {
  title?: string;
  subtitle?: string;
  description?: string;
  ctaText?: string;
  ctaLink?: string;
  backgroundImage?: string;
  showParticles?: boolean;
  enableScrollAnimations?: boolean;
  className?: string;
}

export interface HeroAnimation {
  timeline: gsap.core.Timeline;
  scrollTrigger?: ScrollTrigger;
}

export interface ParticleConfig {
  count: number;
  speed: number;
  color: string;
  size: { min: number; max: number };
}
```

#### 1.3 Create Styles Configuration
**File:** `src/components/sections/Hero/styles.ts`
```typescript
export const heroStyles = {
  container: "relative min-h-screen flex items-center justify-center overflow-hidden",
  background: {
    overlay: "absolute inset-0 bg-gradient-to-br from-app-background via-app-surface to-app-primary/20",
    particles: "absolute inset-0 z-0",
    image: "absolute inset-0 object-cover w-full h-full opacity-30"
  },
  content: {
    wrapper: "relative z-10 text-center max-w-4xl mx-auto px-4 sm:px-6 lg:px-8",
    title: "text-5xl md:text-7xl font-bold mb-6 text-app-text-primary",
    subtitle: "text-xl md:text-2xl mb-4 text-app-highlight font-medium",
    description: "text-lg md:text-xl mb-8 text-app-text-secondary leading-relaxed max-w-2xl mx-auto",
    cta: {
      primary: "inline-flex items-center px-8 py-4 bg-app-accent hover:bg-app-accent/90 text-white font-semibold rounded-lg transform transition-all duration-300 hover:scale-105 shadow-lg hover:shadow-xl",
      secondary: "inline-flex items-center px-8 py-4 border-2 border-app-primary hover:border-app-highlight text-app-text-primary hover:text-app-highlight font-semibold rounded-lg transform transition-all duration-300 hover:scale-105 ml-4"
    }
  },
  scroll: {
    indicator: "absolute bottom-8 left-1/2 transform -translate-x-1/2 text-app-text-secondary animate-bounce",
    arrow: "w-6 h-6 mx-auto mb-2"
  }
};

export const animationClasses = {
  fadeInUp: "opacity-0 translate-y-12",
  fadeInDown: "opacity-0 -translate-y-12",
  fadeInLeft: "opacity-0 -translate-x-12",
  fadeInRight: "opacity-0 translate-x-12",
  scaleIn: "opacity-0 scale-95"
};
```

### 2. Implement Hero Component

#### 2.1 Main Component Template
**File:** `src/components/sections/Hero/index.astro`
```astro
---
/**
 * Hero Component with GSAP animations and scroll effects
 * 
 * @component
 * @param {HeroProps} props - Component properties
 * 
 * Features:
 * - GSAP timeline animations
 * - Scroll-triggered effects
 * - Particle background system
 * - Responsive design
 * - Smooth scrolling integration
 * 
 * @example
 * <Hero 
 *   title="Welcome to MKS-IPTV"
 *   subtitle="v1.0-beta"
 *   description="The Ultimate IPTV Experience"
 *   ctaText="Download Now"
 *   ctaLink="/download"
 *   showParticles={true}
 *   enableScrollAnimations={true}
 * />
 */

import { heroStyles, animationClasses } from './styles';
import type { HeroProps } from './types';
import { strings } from '../../../i18n/strings/es-es';
import { homeContent } from '../../../data/legacy-content';

const {
  title = homeContent.hero.title,
  subtitle = homeContent.hero.subtitle,
  description = homeContent.hero.description,
  ctaText = strings.cta.download,
  ctaLink = '/MKS-IPTV-App/download',
  backgroundImage,
  showParticles = true,
  enableScrollAnimations = true,
  className = ''
}: HeroProps = Astro.props;

const heroClasses = [heroStyles.container, className].filter(Boolean).join(' ');
---

<section class={heroClasses} id="hero-section">
  <!-- Background Elements -->
  <div class={heroStyles.background.overlay}></div>
  
  {backgroundImage && (
    <img 
      src={backgroundImage}
      alt="Hero Background"
      class={heroStyles.background.image}
      loading="eager"
    />
  )}
  
  {showParticles && (
    <div id="particles-container" class={heroStyles.background.particles}></div>
  )}
  
  <!-- Hero Content -->
  <div class={heroStyles.content.wrapper}>
    <div class={`${animationClasses.fadeInDown} hero-subtitle`}>
      <span class={heroStyles.content.subtitle}>{subtitle}</span>
    </div>
    
    <h1 class={`${animationClasses.fadeInUp} hero-title`}>
      <span class={heroStyles.content.title}>{title}</span>
    </h1>
    
    <p class={`${animationClasses.fadeInUp} hero-description`}>
      {description}
    </p>
    
    <div class={`${animationClasses.scaleIn} hero-cta`}>
      <a href={ctaLink} class={heroStyles.content.cta.primary}>
        {ctaText}
        <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
        </svg>
      </a>
      
      <a href="/MKS-IPTV-App/screenshots" class={heroStyles.content.cta.secondary}>
        {strings.cta.viewScreenshots}
      </a>
    </div>
  </div>
  
  <!-- Scroll Indicator -->
  {enableScrollAnimations && (
    <div class={heroStyles.scroll.indicator} id="scroll-indicator">
      <svg class={heroStyles.scroll.arrow} fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
      </svg>
      <span class="text-sm">{strings.ui.scrollDown}</span>
    </div>
  )}
</section>

<!-- GSAP Animation Script -->
<script>
  import { gsap } from 'gsap';
  import { ScrollTrigger } from 'gsap/ScrollTrigger';

  // Register GSAP plugins
  gsap.registerPlugin(ScrollTrigger);

  document.addEventListener('DOMContentLoaded', () => {
    // Hero animations timeline
    const heroTl = gsap.timeline({ delay: 0.5 });
    
    // Animate hero elements
    heroTl
      .from('.hero-subtitle', { 
        duration: 1, 
        y: -50, 
        opacity: 0, 
        ease: 'back.out(1.7)' 
      })
      .from('.hero-title', { 
        duration: 1.2, 
        y: 50, 
        opacity: 0, 
        ease: 'power3.out' 
      }, '-=0.3')
      .from('.hero-description', { 
        duration: 1, 
        y: 30, 
        opacity: 0, 
        ease: 'power2.out' 
      }, '-=0.5')
      .from('.hero-cta', { 
        duration: 0.8, 
        scale: 0.8, 
        opacity: 0, 
        ease: 'back.out(1.7)' 
      }, '-=0.3');

    // Scroll-triggered animations
    ScrollTrigger.create({
      trigger: '#hero-section',
      start: 'top top',
      end: 'bottom top',
      scrub: 1,
      onUpdate: (self) => {
        const progress = self.progress;
        gsap.set('#hero-section .hero-title', {
          y: progress * 100,
          opacity: 1 - progress * 0.5
        });
      }
    });

    // Scroll indicator animation
    const scrollIndicator = document.getElementById('scroll-indicator');
    if (scrollIndicator) {
      gsap.to(scrollIndicator, {
        y: 10,
        duration: 1.5,
        ease: 'power2.inOut',
        repeat: -1,
        yoyo: true
      });
      
      // Hide scroll indicator on scroll
      ScrollTrigger.create({
        trigger: '#hero-section',
        start: 'top top',
        end: 'bottom top',
        onUpdate: (self) => {
          gsap.to(scrollIndicator, {
            opacity: 1 - self.progress,
            duration: 0.3
          });
        }
      });
    }
  });
</script>

<!-- Particles Script -->
{showParticles && (
  <script>
    import { tsParticles } from 'tsparticles-engine';
    import { loadFull } from 'tsparticles';

    document.addEventListener('DOMContentLoaded', async () => {
      await loadFull(tsParticles);
      
      const particlesContainer = document.getElementById('particles-container');
      if (particlesContainer) {
        await tsParticles.load('particles-container', {
          background: {
            color: 'transparent'
          },
          fpsLimit: 120,
          particles: {
            color: {
              value: '#C62790'
            },
            links: {
              color: '#C62790',
              distance: 150,
              enable: true,
              opacity: 0.2,
              width: 1
            },
            move: {
              direction: 'none',
              enable: true,
              outModes: {
                default: 'bounce'
              },
              random: false,
              speed: 1,
              straight: false
            },
            number: {
              density: {
                enable: true,
                area: 800
              },
              value: 50
            },
            opacity: {
              value: 0.3
            },
            shape: {
              type: 'circle'
            },
            size: {
              value: { min: 1, max: 3 }
            }
          },
          detectRetina: true
        });
      }
    });
  </script>
)}
</section>
```

### 3. Integration Tasks

#### 3.1 Update Localization Strings
**File:** `src/i18n/strings/es-es.ts`
```typescript
// Add to existing strings object
export const strings = {
  // ... existing strings
  cta: {
    download: 'Descargar Ahora',
    viewScreenshots: 'Ver Capturas',
    learnMore: 'Saber Más',
    getStarted: 'Comenzar'
  },
  ui: {
    scrollDown: 'Desplázate hacia abajo'
  }
};
```

#### 3.2 Update Legacy Content Data
**File:** `src/data/legacy-content.ts`
```typescript
// Add to existing content
export const homeContent = {
  // ... existing content
  hero: {
    title: 'MKS-IPTV',
    subtitle: 'v1.0-beta',
    description: 'La experiencia IPTV definitiva para dispositivos Apple',
    tagline: 'Streaming de alta calidad con diseño Liquid Glass'
  }
};
```

#### 3.3 Integrate Hero in Layout
**File:** `src/pages/index.astro`
```astro
---
import Layout from '../layouts/Layout.astro';
import Header from '../components/layout/Header/index.astro';
import Hero from '../components/sections/Hero/index.astro';
import Footer from '../components/layout/Footer/index.astro';
---

<Layout title="MKS-IPTV - Home">
  <Header currentPath="/" transparent={true} />
  <main>
    <Hero 
      showParticles={true}
      enableScrollAnimations={true}
    />
    <!-- Other sections -->
  </main>
  <Footer />
</Layout>
```

### 4. Advanced Features

#### 4.1 Smooth Scrolling Integration
```typescript
// Add to Hero component script
import Lenis from '@studio-freight/lenis';

const lenis = new Lenis({
  duration: 1.2,
  easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
  smooth: true
});

function raf(time: number) {
  lenis.raf(time);
  requestAnimationFrame(raf);
}

requestAnimationFrame(raf);
```

#### 4.2 Responsive Animations
```typescript
// Add responsive breakpoints to animations
const mm = gsap.matchMedia();

mm.add("(min-width: 768px)", () => {
  // Desktop animations
  heroTl.from('.hero-title', { 
    duration: 1.5, 
    y: 80, 
    opacity: 0 
  });
});

mm.add("(max-width: 767px)", () => {
  // Mobile animations
  heroTl.from('.hero-title', { 
    duration: 1.2, 
    y: 40, 
    opacity: 0 
  });
});
```

#### 4.3 Performance Optimizations
```typescript
// Intersection Observer for animation triggers
const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      // Trigger animations only when visible
      heroTl.play();
    }
  });
}, { threshold: 0.1 });

observer.observe(document.getElementById('hero-section'));
```

## Testing and Validation

### 5.1 Component Testing
- Test responsive behavior across devices
- Verify GSAP animations performance
- Check particle system loading
- Validate scroll effects smoothness

### 5.2 Performance Checks
- Lighthouse audit for Core Web Vitals
- Animation frame rate monitoring
- Memory usage with particles
- Mobile performance testing

### 5.3 Accessibility
- Screen reader compatibility
- Keyboard navigation
- Reduced motion preferences
- Color contrast validation

## Deployment Considerations

- Ensure GSAP and tsParticles are properly bundled
- Optimize particle configuration for mobile
- Test on different network conditions
- Monitor animation performance in production

## Architecture Benefits

This implementation follows the project's established patterns:
- **3-file component structure** for organization
- **Localized strings** for internationalization
- **Legacy color system** integration
- **TypeScript interfaces** for type safety
- **Responsive design** with Tailwind CSS
- **Performance-first** approach with modern libraries