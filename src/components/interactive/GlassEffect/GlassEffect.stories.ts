/**
 * Stories para el componente GlassEffect
 * Configuración para Astrobook/Storybook
 */

import type { Meta, StoryObj } from '@storybook/react';
import { GlassEffect } from './GlassEffect.tsx';

const meta: Meta<typeof GlassEffect> = {
  title: 'Interactive/GlassEffect',
  component: GlassEffect,
  parameters: {
    layout: 'fullscreen',
    docs: {
      description: {
        component: `
# GlassEffect

Componente de efecto vidrio con filtros SVG avanzados y funcionalidad de arrastre.

## Características

- **4 Presets**: dock, pill, bubble, free
- **Filtros SVG**: feDisplacementMap, turbulencia, blur gaussiano
- **Draggable**: Arrastreable con GSAP y física realista
- **Responsive**: Adaptable a diferentes tamaños de pantalla
- **Personalizable**: Configuración completa mediante props

## Basado en

CodePen: https://codepen.io/mks2508/pen/QwbeKja

## Uso

\`\`\`tsx
<GlassEffect preset="dock">
  <span>Contenido aquí</span>
</GlassEffect>
\`\`\`
        `,
      },
    },
  },
  argTypes: {
    preset: {
      control: 'select',
      options: ['dock', 'pill', 'bubble', 'free'],
      description: 'Preset predefinido a utilizar',
    },
    className: {
      control: 'text',
      description: 'Clases CSS adicionales',
    },
    id: {
      control: 'text',
      description: 'ID único del componente',
    },
    children: {
      control: 'text',
      description: 'Contenido a mostrar',
    },
  },
  decorators: [
    (Story) => (
      <div style={{ 
        padding: '2rem', 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <Story />
      </div>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof GlassEffect>;

/**
 * Preset Dock - Barra tipo macOS Dock
 */
export const Dock: Story = {
  args: {
    preset: 'dock',
    children: (
      <div className="flex items-center gap-3">
        <div className="w-6 h-6 bg-red-500 rounded-full"></div>
        <div className="w-6 h-6 bg-yellow-500 rounded-full"></div>
        <div className="w-6 h-6 bg-green-500 rounded-full"></div>
        <span className="text-white/80 ml-2">macOS Dock</span>
      </div>
    ),
  },
};

/**
 * Preset Pill - Forma píldora
 */
export const Pill: Story = {
  args: {
    preset: 'pill',
    children: (
      <div className="flex items-center gap-2">
        <div className="w-4 h-4 bg-blue-400 rounded-full"></div>
        <span className="text-white/90 text-sm">Pill Effect</span>
      </div>
    ),
  },
};

/**
 * Preset Bubble - Forma circular
 */
export const Bubble: Story = {
  args: {
    preset: 'bubble',
    children: (
      <div className="text-center">
        <div className="w-8 h-8 bg-gradient-to-br from-pink-400 to-purple-500 rounded-full mx-auto mb-2"></div>
        <span className="text-white/90 text-xs">Bubble</span>
      </div>
    ),
  },
};

/**
 * Preset Free - Forma libre
 */
export const Free: Story = {
  args: {
    preset: 'free',
    children: (
      <div className="text-center">
        <h3 className="text-white/90 text-lg font-semibold mb-1">Free Form</h3>
        <p className="text-white/70 text-sm">Drag me around!</p>
      </div>
    ),
  },
};

/**
 * Configuración personalizada
 */
export const Custom: Story = {
  args: {
    preset: 'dock',
    customConfig: {
      width: 400,
      height: 120,
      borderRadius: 32,
      blurAmount: 25,
      displacementScale: 30,
      borderColor: 'rgba(255, 255, 255, 0.4)',
      borderWidth: 2,
      backgroundOpacity: 0.25,
    },
    children: (
      <div className="text-center">
        <h3 className="text-white/90 text-xl font-bold mb-2">Custom Glass</h3>
        <p className="text-white/70">Configuración personalizada</p>
      </div>
    ),
  },
};

/**
 * Múltiples componentes
 */
export const Multiple: Story = {
  render: () => (
    <div className="flex flex-col gap-8">
      <GlassEffect preset="dock">
        <span className="text-white/80">Dock Style</span>
      </GlassEffect>
      <GlassEffect preset="pill">
        <span className="text-white/80">Pill Style</span>
      </GlassEffect>
      <GlassEffect preset="bubble">
        <span className="text-white/80">Bubble</span>
      </GlassEffect>
      <GlassEffect preset="free">
        <span className="text-white/80">Free Form</span>
      </GlassEffect>
    </div>
  ),
};

/**
 * Con contenido complejo
 */
export const ComplexContent: Story = {
  args: {
    preset: 'free',
    customConfig: {
      width: 320,
      height: 180,
    },
    children: (
      <div className="p-4 text-center">
        <div className="w-12 h-12 bg-gradient-to-br from-cyan-400 to-blue-500 rounded-full mx-auto mb-3"></div>
        <h3 className="text-white/90 text-lg font-semibold mb-2">Glass Component</h3>
        <p className="text-white/70 text-sm mb-3">
          Efecto vidrio con filtros SVG avanzados
        </p>
        <div className="flex justify-center gap-2">
          <div className="w-2 h-2 bg-green-400 rounded-full"></div>
          <div className="w-2 h-2 bg-yellow-400 rounded-full"></div>
          <div className="w-2 h-2 bg-red-400 rounded-full"></div>
        </div>
      </div>
    ),
  },
};

/**
 * No draggable
 */
export const Static: Story = {
  args: {
    preset: 'pill',
    customConfig: {
      draggable: false,
    },
    children: (
      <span className="text-white/80">Static Glass (No Draggable)</span>
    ),
  },
};