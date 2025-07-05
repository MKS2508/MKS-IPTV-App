# 🚀 Playbook de Desarrollo Astro

Este documento adapta los principios del `PLAYBOOK-GENERAL.md` y `PLAYBOOK-REACT.md` para el desarrollo específico con Astro, proporcionando directrices para crear componentes modulares, performantes y mantenibles en el ecosistema Astro + TypeScript + Tailwind CSS.

## 🏗️ Arquitectura de Componentes Astro

Adoptamos una adaptación de **Atomic Design** optimizada para Astro, aprovechando las características únicas del framework como los componentes de isla, el rendering estático y la integración híbrida.

### 1. Filosofía de Desarrollo Astro

- **Componentes Estáticos Primero**: Aprovechar el rendering estático de Astro para máximo rendimiento. Los componentes interactivos se implementan como "islas" solo cuando es necesario.
- **TypeScript Estricto**: Utilizar el sistema de tipos de Astro con TypeScript para máxima seguridad de tipos y mejor experiencia de desarrollo.
- **Performance por Defecto**: Cada decisión de diseño debe priorizar la velocidad de carga y la experiencia del usuario final.
- **Composición y Reutilización**: Preferir la composición de componentes pequeños y enfocados para construir interfaces complejas.

### 2. Estructura de Archivos Astro Estándar

#### 2.1 Estructura Estándar Recomendada
**TODOS los componentes** deben seguir esta estructura consistente:

```
components/
└── ComponentName/
    ├── index.astro           # Componente principal (.astro)
    ├── styles.ts             # Estilos de Tailwind organizados
    └── types.ts              # Definiciones de tipos
```

**Ejemplo de styles.ts:**
```typescript
export const componentStyles = {
  container: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
  button: {
    base: "rounded-lg font-medium transition-all duration-200",
    variants: {
      primary: "bg-blue-600 text-white hover:bg-blue-700",
      secondary: "bg-gray-200 text-gray-900 hover:bg-gray-300"
    },
    sizes: {
      sm: "px-3 py-1 text-sm",
      md: "px-4 py-2 text-base", 
      lg: "px-6 py-3 text-lg"
    }
  },
  animations: {
    fadeIn: "opacity-0 transform translate-y-8",
    slideUp: "opacity-0 transform translate-y-12"
  }
} as const;
```

#### 2.2 Estructura para Componentes Interactivos
Para componentes que requieren interactividad client-side:

```
components/
└── InteractiveComponent/
    ├── index.astro           # Componente contenedor Astro
    ├── Interactive.tsx       # Lógica React/Vue (islas)
    ├── styles.ts             # Estilos compartidos Astro + React
    └── types.ts              # Tipos compartidos
```

#### 2.3 Estructura de Layouts y Páginas

```
layouts/
└── MainLayout.astro          # Layout principal con SEO y estructura base

pages/
├── index.astro               # Página principal
├── download.astro            # Páginas específicas
└── [...slug].astro           # Rutas dinámicas (si es necesario)
```

#### 2.4 Ventajas de la Estructura Estándar

**¿Por qué archivos separados para estilos y tipos?**

1. **Mantenibilidad**: Fácil localización y modificación de estilos sin tocar la lógica del componente
2. **Reutilización**: Los estilos pueden ser importados y extendidos por otros componentes
3. **Consistencia**: Estructura uniforme en todo el proyecto facilita la navegación
4. **Colaboración**: Desarrolladores pueden trabajar en estilos y lógica independientemente
5. **TypeScript**: Mejor autocompletado y validación de tipos con archivos dedicados
6. **Performance**: Bundlers pueden optimizar mejor con archivos separados
7. **Testing**: Estilos y tipos pueden ser probados independientemente

**Ejemplo de reutilización:**
```typescript
// components/ui/Button/styles.ts
export const buttonStyles = { /* ... */ };

// components/ui/Card/styles.ts  
import { buttonStyles } from '../Button/styles';

export const cardStyles = {
  container: "bg-white rounded-lg shadow-lg p-6",
  button: buttonStyles.button // Reutilización
};
```

### 3. Categorización de Componentes (Atomic Design para Astro)

Los componentes se organizan según su función y nivel de complejidad:

#### **`components/layout/`**: Componentes de estructura de página
- `Header.astro` - Navegación principal
- `Footer.astro` - Pie de página
- `SEO.astro` - Meta tags y SEO
- `Navigation.astro` - Elementos de navegación

#### **`components/sections/`**: Secciones de página completas
- `Hero.astro` - Sección hero con animaciones
- `Features.astro` - Showcase de características
- `Screenshots.astro` - Galería de imágenes
- `Downloads.astro` - Sección de descargas

#### **`components/ui/`**: Elementos reutilizables
- `Button.astro` - Botones estilizados
- `Card.astro` - Tarjetas de información
- `Gallery.astro` - Galerías de imágenes
- `Modal.astro` - Modales y overlays

#### **`components/animations/`**: Componentes con animaciones GSAP
- `FadeIn.astro` - Animaciones de aparición
- `SlideUp.astro` - Animaciones de deslizamiento
- `ParticleBackground.astro` - Fondos animados con tsParticles

#### **`components/interactive/`**: Componentes con lógica client-side
- `Carousel.tsx` - Carruseles interactivos (Embla)
- `Lightbox.tsx` - Galerías con PhotoSwipe
- `ScrollHandler.tsx` - Manejo de scroll suave (Lenis)

## 🎨 Sistema de Estilos Astro

### 1. Tailwind CSS como Base
- **Utility-First**: Priorizar clases de utilidad de Tailwind
- **Componentes Customizados**: Crear componentes CSS solo cuando sea necesario
- **Variables CSS**: Utilizar custom properties para temas y personalización

### 2. Organización de Estilos

#### Regla Obligatoria: Estilos en Archivos Separados
**TODOS los componentes DEBEN usar un archivo `styles.ts` separado** para mantener consistencia y facilitar el mantenimiento.

#### Archivo styles.ts (OBLIGATORIO):
```typescript
// ComponentName/styles.ts
export const styles = {
  // Clases base del componente
  container: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
  
  // Para componentes con variantes
  button: {
    base: "rounded-lg font-medium transition-all duration-200 focus:outline-none focus:ring-2",
    variants: {
      primary: "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500",
      secondary: "bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500",
      danger: "bg-red-600 text-white hover:bg-red-700 focus:ring-red-500"
    },
    sizes: {
      sm: "px-3 py-1 text-sm",
      md: "px-4 py-2 text-base", 
      lg: "px-6 py-3 text-lg"
    },
    states: {
      disabled: "opacity-50 cursor-not-allowed",
      loading: "cursor-wait"
    }
  },
  
  // Estilos para animaciones GSAP
  animations: {
    fadeIn: "opacity-0 transform translate-y-8",
    slideUp: "opacity-0 transform translate-y-12",
    slideDown: "opacity-0 transform translate-y-[-12px]",
    scale: "opacity-0 transform scale-95"
  },
  
  // Estados responsive
  responsive: {
    mobile: "block md:hidden",
    desktop: "hidden md:block",
    tablet: "hidden md:block lg:hidden"
  }
} as const;

// Función helper para combinar clases (opcional pero recomendada)
export function buildClasses(
  base: string,
  variant?: string,
  size?: string,
  additional?: string
): string {
  return [base, variant, size, additional].filter(Boolean).join(' ');
}
```

#### Uso en Componente Astro:
```astro
---
// ComponentName/index.astro
import { styles, buildClasses } from './styles';
import type { ButtonProps } from './types';

const { 
  variant = 'primary', 
  size = 'md', 
  disabled = false,
  className,
  ...props 
} = Astro.props;

const buttonClasses = buildClasses(
  styles.button.base,
  styles.button.variants[variant],
  styles.button.sizes[size],
  disabled ? styles.button.states.disabled : '',
  className
);
---

<button class={buttonClasses} disabled={disabled} {...props}>
  <slot />
</button>
```

## 🎭 Gestión de Interactividad

### 1. Astro Islands Pattern
Los componentes interactivos se implementan como "islas" que se hidratan en el cliente:

```astro
---
// ParentComponent.astro
---

<div class="static-content">
  <h1>Contenido Estático</h1>
  
  <!-- Isla interactiva -->
  <InteractiveCarousel 
    client:load 
    images={images}
    autoplay={true}
  />
  
  <p>Más contenido estático</p>
</div>
```

### 2. Directivas de Hidratación
- `client:load` - Hidrata inmediatamente al cargar la página
- `client:idle` - Hidrata cuando el browser esté inactivo
- `client:visible` - Hidrata cuando entra en el viewport
- `client:media` - Hidrata según media queries

### 3. Scripts y Eventos
```astro
---
// Component.astro
---

<div id="animated-section" class="opacity-0">
  <slot />
</div>

<script>
  import { gsap } from 'gsap';
  import { ScrollTrigger } from 'gsap/ScrollTrigger';
  
  gsap.registerPlugin(ScrollTrigger);
  
  // Animación que se ejecuta en el cliente
  gsap.to('#animated-section', {
    opacity: 1,
    y: 0,
    duration: 1,
    scrollTrigger: '#animated-section'
  });
</script>
```

## 📊 Gestión de Datos y Estado

### 1. Datos Estáticos
```typescript
// src/data/features.ts
export interface Feature {
  id: string;
  title: string;
  description: string;
  icon: string;
  category: 'streaming' | 'download' | 'platform';
}

export const features: Feature[] = [
  {
    id: 'live-streaming',
    title: 'Streaming en Vivo',
    description: 'Reproduce canales IPTV en tiempo real con alta calidad',
    icon: 'play-circle',
    category: 'streaming'
  },
  // ... más features
];
```

### 2. Uso en Componentes
```astro
---
// Features.astro
import { features } from '@/data/features';
import FeatureCard from '@/components/ui/FeatureCard.astro';

const streamingFeatures = features.filter(f => f.category === 'streaming');
---

<section class="py-16">
  <div class="max-w-7xl mx-auto px-4">
    <h2 class="text-3xl font-bold text-center mb-12">Características</h2>
    <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
      {streamingFeatures.map(feature => (
        <FeatureCard 
          title={feature.title}
          description={feature.description}
          icon={feature.icon}
        />
      ))}
    </div>
  </div>
</section>
```

## 🎬 Integración de Animaciones

### 1. GSAP en Componentes Astro
```astro
---
// AnimatedHero.astro
---

<section id="hero" class="min-h-screen flex items-center justify-center">
  <div class="text-center">
    <h1 id="hero-title" class="text-6xl font-bold opacity-0">
      MKS-IPTV
    </h1>
    <p id="hero-subtitle" class="text-xl mt-4 opacity-0">
      Tu cliente IPTV multiplataforma
    </p>
  </div>
</section>

<script>
  import { gsap } from 'gsap';
  
  // Timeline de animación
  const tl = gsap.timeline();
  
  tl.to('#hero-title', {
    opacity: 1,
    y: 0,
    duration: 1,
    ease: 'power2.out'
  })
  .to('#hero-subtitle', {
    opacity: 1,
    y: 0,
    duration: 0.8,
    ease: 'power2.out'
  }, '-=0.5');
</script>
```

### 2. Lenis Smooth Scroll
```typescript
// src/scripts/smooth-scroll.ts
import Lenis from '@studio-freight/lenis';

export function initSmoothScroll() {
  const lenis = new Lenis({
    duration: 1.2,
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    direction: 'vertical',
    gestureDirection: 'vertical',
    smooth: true,
    smoothTouch: false,
    touchMultiplier: 2
  });

  function raf(time: number) {
    lenis.raf(time);
    requestAnimationFrame(raf);
  }

  requestAnimationFrame(raf);
  
  return lenis;
}
```

## 🧪 Testing y Calidad

### 1. TypeScript Estricto
```json
// tsconfig.json (extracto)
{
  "extends": "astro/tsconfigs/strictest",
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noImplicitReturns": true
  }
}
```

### 2. Verificación de Calidad
```bash
# Comandos de verificación
bun run check      # Verificación de tipos de Astro
bun run lint       # ESLint + Prettier
bun run build      # Build de producción
bun run preview    # Preview del build
```

## 📄 Documentación de Componentes

### 1. JSDoc en Español para Componentes Astro
```astro
---
/**
 * Tarjeta de característica con icono y descripción.
 * 
 * @component
 * @param {string} title - Título de la característica
 * @param {string} description - Descripción detallada
 * @param {string} icon - Nombre del icono a mostrar
 * @param {'primary' | 'secondary'} variant - Variante visual de la tarjeta
 * @example
 * <FeatureCard 
 *   title="Streaming HD" 
 *   description="Calidad de imagen superior"
 *   icon="play-circle"
 *   variant="primary"
 * />
 */

interface Props {
  title: string;
  description: string;
  icon: string;
  variant?: 'primary' | 'secondary';
}

const { title, description, icon, variant = 'primary' } = Astro.props;
---
```

### 2. Tipos Explícitos
```typescript
// types.ts
export interface AstroComponentProps {
  class?: string;
  id?: string;
}

export interface FeatureCardProps extends AstroComponentProps {
  title: string;
  description: string;
  icon: string;
  variant?: 'primary' | 'secondary';
}

export interface GalleryImage {
  src: string;
  alt: string;
  width: number;
  height: number;
  category?: string;
}
```

## 🚀 Optimización y Performance

### 1. Optimización de Imágenes
```astro
---
import { Image } from 'astro:assets';
import heroImage from '@/assets/hero-image.jpg';
---

<Image 
  src={heroImage}
  alt="MKS-IPTV Interface"
  width={1200}
  height={800}
  format="webp"
  quality={80}
  loading="eager"
  class="w-full h-auto rounded-lg shadow-xl"
/>
```

### 2. Code Splitting Automático
```astro
---
// Componente que se carga solo cuando es necesario
const LazyGallery = import('@/components/interactive/Gallery.tsx');
---

<div class="gallery-container">
  <LazyGallery client:visible />
</div>
```

## ⚡ Definition of Done - Astro

Una tarea o componente Astro se considera completado cuando:

- [ ] **Estructura Obligatoria**: Componente organizado en carpeta con `index.astro`, `styles.ts`, y `types.ts`
- [ ] **Implementación Completa**: El componente `.astro` está funcional y respeta la API definida
- [ ] **Estilos Separados**: Todas las clases de Tailwind organizadas en `styles.ts` con estructura consistente
- [ ] **Tipos TypeScript**: Todas las props e interfaces definidas en `types.ts` y correctamente tipadas
- [ ] **Responsive Design**: El componente funciona en mobile, tablet y desktop
- [ ] **Accesibilidad**: ARIA labels, keyboard navigation y semántica HTML apropiada
- [ ] **Performance**: Optimizado para Core Web Vitals (LCP, FID, CLS)
- [ ] **Documentación JSDoc**: Comentarios completos en español en el archivo `.astro`
- [ ] **Build Sin Errores**: `bun run check` y `bun run build` pasan sin errores
- [ ] **Verificación Visual**: El componente se ve correcto en el navegador
- [ ] **Integración**: Se integra correctamente con otros componentes del sistema

## 🔗 Referencias

- **Documentación Principal**: `../../CLAUDE.md`
- **Metodología General**: `./PLAYBOOK-GENERAL.md`
- **Patrones React**: `./PLAYBOOK-REACT.md`
- **Plan Técnico**: `./refactor.astro.md`
- **Tareas Actuales**: `./current-todos.md`
- **Documentación Astro**: https://docs.astro.build/
- **TypeScript en Astro**: https://docs.astro.build/en/guides/typescript/
- **Tailwind CSS**: https://tailwindcss.com/docs