# ASTROBOOK-DOCS.md

Documentación exhaustiva sobre Astrobook para el proyecto MKS-IPTV Landing Page.

## 🔍 Qué es Astrobook

**Astrobook** es una herramienta de documentación de componentes específicamente diseñada para **Astro**, NO es Storybook tradicional. Funciona de manera similar a Storybook pero con APIs y formatos completamente diferentes.

### Diferencias Clave con Storybook React

| Aspecto | Storybook React | Astrobook |
|---------|----------------|-----------|
| **API** | `Meta`, `StoryObj`, `render` functions | Exports simples con `args` |
| **Archivos** | `*.stories.tsx` | `*.stories.ts` |
| **Importación** | Componentes React/JSX | Componentes `.astro` |
| **Tipos** | `@storybook/react` types | `ComponentProps<typeof Component>` |
| **Complejidad** | Funciones de render complejas | Configuración de props simple |

## 📝 Formato Correcto de Stories

### ❌ INCORRECTO (Storybook React)
```typescript
import type { Meta, StoryObj } from '@storybook/react';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  // ... configuración compleja
};

export const Primary: Story = {
  render: () => <Button variant="primary">Primary</Button>
};
```

### ✅ CORRECTO (Astrobook)
```typescript
import type { ComponentProps } from 'astro/types'
import Button from './index.astro'

type ButtonProps = ComponentProps<typeof Button>

export default {
  component: Button,
}

export const Primary = {
  args: {
    variant: 'primary',
    children: 'Primary Button',
  } satisfies ButtonProps,
}
```

## 🎯 Reglas Fundamentales

### 1. **Importación de Componentes**
```typescript
// ✅ CORRECTO - Importar componente .astro
import Button from './index.astro'
import type { ComponentProps } from 'astro/types'

// ❌ INCORRECTO - No importar componente React
import { Button } from './Button.tsx'
```

### 2. **Definición de Tipos**
```typescript
// ✅ CORRECTO - Usar ComponentProps de Astro
type ButtonProps = ComponentProps<typeof Button>

// ❌ INCORRECTO - Usar tipos de React
type ButtonProps = React.ComponentProps<typeof Button>
```

### 3. **Export Default**
```typescript
// ✅ CORRECTO - Export simple
export default {
  component: Button,
}

// ❌ INCORRECTO - Meta completa de Storybook
const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  parameters: { ... }
}
```

### 4. **Exports de Stories**
```typescript
// ✅ CORRECTO - Args con satisfies
export const Primary = {
  args: {
    variant: 'primary',
    children: 'Primary Button',
  } satisfies ButtonProps,
}

// ❌ INCORRECTO - Render function
export const Primary: Story = {
  render: () => <Button variant="primary">Primary</Button>
}
```

## 📁 Convenciones de Archivos

### Estructura Recomendada
```
Component/
├── index.astro                # Componente principal
├── Component.tsx              # Lógica React (si necesaria)
├── Component.stories.ts       # Stories para Astrobook ✅
├── Component.storybook.tsx    # Stories para Storybook React (opcional)
├── ComponentShowcase.astro    # Componente para comparativas
├── ComponentShowcase.stories.ts # Stories del showcase
├── styles.ts                  # Estilos Tailwind
└── types.ts                   # Definiciones TypeScript
```

### Nomenclatura de Archivos
- **Stories de Astrobook**: `*.stories.ts` (NO `.tsx`)
- **Stories de Storybook**: `*.storybook.tsx` (para desarrollo local)
- **Showcases**: `*Showcase.astro` + `*Showcase.stories.ts`

## 🎨 Patrón Showcase para Comparativas

### Problema
Astrobook está diseñado para mostrar **estados individuales** de componentes, no comparativas múltiples como galerías.

### Solución: Componente Showcase
```astro
---
// ButtonShowcase.astro
import Button from './index.astro';

export interface Props {
  section?: 'all' | 'variants' | 'sizes' | 'icons';
}

const { section = 'all' } = Astro.props;
---

<div class="space-y-8">
  {(section === 'all' || section === 'variants') && (
    <section>
      <h3>Variantes</h3>
      <div class="grid grid-cols-4 gap-4">
        <Button variant="primary">Primary</Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
      </div>
    </section>
  )}
  
  {/* Más secciones... */}
</div>
```

### Stories del Showcase
```typescript
// ButtonShowcase.stories.ts
import type { ComponentProps } from 'astro/types'
import ButtonShowcase from './ButtonShowcase.astro'

type ShowcaseProps = ComponentProps<typeof ButtonShowcase>

export default {
  component: ButtonShowcase,
}

export const Complete = {
  args: {
    section: 'all',
  } satisfies ShowcaseProps,
}

export const VariantsOnly = {
  args: {
    section: 'variants',
  } satisfies ShowcaseProps,
}
```

## ⚙️ Configuración de Astrobook

### En `astro.config.mjs`
```javascript
import astrobook from 'astrobook';

export default defineConfig({
  integrations: [
    // ... otras integraciones
    astrobook({
      css: ['./src/styles/globals.css'],
      subpath: '/astrobook',
    }),
  ],
});
```

### En `package.json`
```json
{
  "dependencies": {
    "astrobook": "^0.8.3"
  }
}
```

## 🐛 Errores Comunes y Soluciones

### 1. **Error de Import Path**
```
Could not import `./index.astro`
```

**Causa**: Ruta de importación incorrecta o archivo inexistente
**Solución**: Verificar que el archivo existe y la ruta es correcta

```typescript
// ✅ CORRECTO - Archivo en la misma carpeta
import Button from './index.astro'

// ❌ INCORRECTO - Ruta equivocada
import Button from '../Button/index.astro'
```

### 2. **Error de Tipos**
```
Type 'X' is not assignable to type 'Y'
```

**Causa**: Usar tipos de React en lugar de Astro
**Solución**: Usar `ComponentProps<typeof Component>`

### 3. **Stories No Aparecen**
**Causas Comunes**:
- Archivo nombrado `*.stories.tsx` en lugar de `*.stories.ts`
- Export default mal formado
- Componente no exportado correctamente

### 4. **Nombres de Archivo con Espacios**
**Problema**: `index 2.astro` con espacios
**Solución**: Renombrar sin espacios `index.astro`

## 📚 Ejemplos Prácticos Completos

### Story Básica
```typescript
// Button.stories.ts
import type { ComponentProps } from 'astro/types'
import Button from './index.astro'

type ButtonProps = ComponentProps<typeof Button>

export default {
  component: Button,
}

export const Primary = {
  args: {
    variant: 'primary',
    children: 'Primary Button',
  } satisfies ButtonProps,
}

export const WithIcon = {
  args: {
    variant: 'secondary',
    icon: { lucide: 'Download', position: 'left' },
    children: 'Download',
  } satisfies ButtonProps,
}

export const Loading = {
  args: {
    loading: true,
    variant: 'primary',
    children: 'Loading...',
  } satisfies ButtonProps,
}
```

### Story con Props Complejas
```typescript
// Card.stories.ts
import type { ComponentProps } from 'astro/types'
import Card from './index.astro'

type CardProps = ComponentProps<typeof Card>

export default {
  component: Card,
}

export const WithImage = {
  args: {
    title: 'Card Title',
    description: 'Card description with some text',
    image: {
      src: '/images/placeholder.jpg',
      alt: 'Placeholder image'
    },
    badge: {
      text: 'New',
      variant: 'success'
    },
    cta: {
      text: 'Read More',
      href: '#',
      variant: 'primary'
    }
  } satisfies CardProps,
}
```

### Showcase Completo
```astro
---
// ComponentShowcase.astro
import Component from './index.astro';

export interface Props {
  section?: 'all' | 'variants' | 'sizes' | 'states';
  title?: string;
}

const { 
  section = 'all',
  title = 'Component Showcase'
} = Astro.props;

const showAll = section === 'all';
---

<div class="p-6 bg-app-surface rounded-xl">
  <h2 class="text-2xl font-bold mb-6">{title}</h2>
  
  {(showAll || section === 'variants') && (
    <section class="mb-8">
      <h3 class="text-lg font-semibold mb-4">Variantes</h3>
      <div class="grid grid-cols-3 gap-4">
        <Component variant="primary">Primary</Component>
        <Component variant="secondary">Secondary</Component>
        <Component variant="outline">Outline</Component>
      </div>
    </section>
  )}
  
  {(showAll || section === 'sizes') && (
    <section class="mb-8">
      <h3 class="text-lg font-semibold mb-4">Tamaños</h3>
      <div class="flex items-end gap-4">
        <Component size="sm">Small</Component>
        <Component size="md">Medium</Component>
        <Component size="lg">Large</Component>
      </div>
    </section>
  )}
  
  {(showAll || section === 'states') && (
    <section>
      <h3 class="text-lg font-semibold mb-4">Estados</h3>
      <div class="flex gap-4">
        <Component loading>Loading</Component>
        <Component disabled>Disabled</Component>
      </div>
    </section>
  )}
</div>
```

## 🚀 Mejores Prácticas

### 1. **Organización de Stories**
- Una story por variante principal
- Agrupar states relacionados
- Usar nombres descriptivos para exports

### 2. **Props por Defecto**
- Siempre incluir `children` cuando sea relevante
- Usar valores realistas para props
- Considerar casos edge

### 3. **Showcases Estratégicos**
- Crear showcases para componentes con muchas variantes
- Secciones configurables para flexibilidad
- Mantener showcases visuales y organizados

### 4. **Documentación en Código**
```typescript
export const ComplexExample = {
  args: {
    // Props principales
    variant: 'primary',
    size: 'lg',
    
    // Props de estado
    loading: false,
    disabled: false,
    
    // Props de contenido
    children: 'Complex Button',
    
    // Props de icono
    icon: { 
      lucide: 'Download', 
      position: 'left' 
    },
  } satisfies ButtonProps,
}
```

## 🔧 Debugging y Troubleshooting

### Verificar Configuración
1. Astrobook está en `package.json`
2. Integración configurada en `astro.config.mjs`
3. Servidor corriendo con `npm run dev`
4. Acceder a `/astrobook` en el navegador

### Verificar Stories
1. Archivos nombrados `*.stories.ts`
2. Import de componente `.astro` correcto
3. Export default con `component`
4. Exports nombrados con `args`

### Logs Útiles
```bash
# Verificar que Astrobook carga
[astrobook] Found X stories

# Error de import típico
Could not import `./Component.astro`

# Error de tipo típico
Type 'X' is not assignable to parameter of type 'Y'
```

## 📋 Checklist para Nuevas Stories

- [ ] Archivo nombrado `Component.stories.ts`
- [ ] Import del componente `.astro`
- [ ] Import de `ComponentProps` de Astro
- [ ] Type alias con `ComponentProps<typeof Component>`
- [ ] Export default con `{ component }`
- [ ] Al menos una story con `args` y `satisfies`
- [ ] Props realistas y casos de uso relevantes
- [ ] Consideración de showcase si hay muchas variantes

## 🎯 Cuándo Usar Qué

### Stories Individuales ✅
- Testing de props específicas
- Estados únicos del componente
- Casos edge o especiales
- Desarrollo iterativo

### Showcase Component ✅
- Comparación visual de variantes
- Documentación completa
- Galería de estados
- Presentación a stakeholders

### Páginas Separadas ❌
- No necesario con Astrobook
- Mantiene toda la documentación centralizada
- Astrobook ya provee navegación y organización

## 🔗 Referencias

- **Astrobook Oficial**: [GitHub](https://github.com/astrojs-group/astrobook)
- **Astro ComponentProps**: [Docs](https://docs.astro.build/en/guides/typescript/#component-props-type)
- **Configuración del Proyecto**: `astro.config.mjs` línea 18-21

---

**Nota**: Esta documentación está basada en el descubrimiento práctico durante la implementación del componente Button en el proyecto MKS-IPTV Landing Page. Todos los ejemplos son funcionales y probados.