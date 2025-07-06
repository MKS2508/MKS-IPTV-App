/**
 * @file Stories completas para el componente Button.tsx
 * @author MKS
 */

import type { Meta, StoryObj } from '@storybook/react';
import { expect, userEvent, within } from '@storybook/test';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  parameters: {
    layout: 'centered',
    docs: {
      description: {
        component: `
# Button Component

Componente Button universal con soporte completo para:
- **6 variantes**: primary, secondary, outline, ghost, danger, success
- **4 tamaños**: sm, md, lg, xl  
- **Estados**: loading, disabled
- **Iconos**: Lucide React y Simple Icons
- **Animaciones**: Framer Motion con presets configurables
- **Enlaces**: Soporte para links internos y externos

## Ejemplos de Uso

\`\`\`tsx
// Botón básico
<Button variant="primary">Click me</Button>

// Con icono y animación
<Button 
  variant="secondary" 
  icon={{ lucide: 'Download', position: 'left' }}
  motionConfig={{ hover: { scale: 1.05, y: -2 } }}
>
  Download
</Button>

// Como enlace externo
<Button 
  as="link" 
  href="https://example.com" 
  external
  variant="outline"
>
  External Link
</Button>
\`\`\`
        `,
      },
    },
  },
  argTypes: {
    variant: {
      control: { type: 'select' },
      options: ['primary', 'secondary', 'outline', 'ghost', 'danger', 'success'],
      description: 'Variante visual del botón',
      table: {
        type: { summary: 'string' },
        defaultValue: { summary: 'primary' },
      },
    },
    size: {
      control: { type: 'select' },
      options: ['sm', 'md', 'lg', 'xl'],
      description: 'Tamaño del botón',
      table: {
        type: { summary: 'string' },
        defaultValue: { summary: 'md' },
      },
    },
    width: {
      control: { type: 'select' },
      options: ['auto', 'full', 'fit'],
      description: 'Ancho del botón',
      table: {
        type: { summary: 'string' },
        defaultValue: { summary: 'auto' },
      },
    },
    loading: {
      control: { type: 'boolean' },
      description: 'Estado de carga con spinner',
      table: {
        type: { summary: 'boolean' },
        defaultValue: { summary: 'false' },
      },
    },
    disabled: {
      control: { type: 'boolean' },
      description: 'Estado deshabilitado',
      table: {
        type: { summary: 'boolean' },
        defaultValue: { summary: 'false' },
      },
    },
    children: {
      control: { type: 'text' },
      description: 'Contenido del botón',
      table: {
        type: { summary: 'ReactNode' },
      },
    },
    onClick: {
      action: 'clicked',
      description: 'Función que se ejecuta al hacer click',
      table: {
        type: { summary: '() => void' },
      },
    },
  },
  args: {
    children: 'Button',
    variant: 'primary',
    size: 'md',
    width: 'auto',
    loading: false,
    disabled: false,
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

// ===== VARIANTES BÁSICAS =====
export const Primary: Story = {
  args: {
    children: 'Primary Button',
    variant: 'primary',
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    
    // Verificar que el botón existe y tiene la clase correcta
    await expect(button).toBeInTheDocument();
    await expect(button).toHaveClass('variant-primary');
  },
};

export const Secondary: Story = {
  args: {
    children: 'Secondary Button',
    variant: 'secondary',
  },
};

export const Outline: Story = {
  args: {
    children: 'Outline Button',
    variant: 'outline',
  },
};

export const Ghost: Story = {
  args: {
    children: 'Ghost Button',
    variant: 'ghost',
  },
};

export const Danger: Story = {
  args: {
    children: 'Danger Button',
    variant: 'danger',
  },
};

export const Success: Story = {
  args: {
    children: 'Success Button',
    variant: 'success',
  },
};

// ===== TAMAÑOS =====
export const Sizes: Story = {
  render: () => (
    <div className="flex items-center gap-4 flex-wrap">
      <Button size="sm" variant="primary">Small</Button>
      <Button size="md" variant="primary">Medium</Button>
      <Button size="lg" variant="primary">Large</Button>
      <Button size="xl" variant="primary">Extra Large</Button>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: 'Diferentes tamaños disponibles: sm, md, lg, xl',
      },
    },
  },
};

// ===== ESTADOS =====
export const Loading: Story = {
  args: {
    children: 'Loading...',
    loading: true,
    variant: 'primary',
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    
    // Verificar que el botón está en estado loading
    await expect(button).toHaveAttribute('disabled');
    await expect(button).toHaveClass('loading');
  },
};

export const Disabled: Story = {
  args: {
    children: 'Disabled Button',
    disabled: true,
    variant: 'primary',
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    
    // Verificar que el botón está deshabilitado
    await expect(button).toBeDisabled();
  },
};

// ===== ANIMACIONES =====
export const WithMotion: Story = {
  args: {
    children: 'Hover me!',
    variant: 'primary',
    motionConfig: {
      hover: { scale: 1.05, y: -2, transition: { duration: 0.2 } },
      tap: { scale: 0.95 },
    },
  },
  parameters: {
    docs: {
      description: {
        story: 'Botón con animaciones Framer Motion personalizadas. Haz hover para ver el efecto.',
      },
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    
    // Simular hover
    await userEvent.hover(button);
    
    // Esperar un momento para la animación
    await new Promise(resolve => setTimeout(resolve, 300));
  },
};

// ===== ANCHOS =====
export const Widths: Story = {
  render: () => (
    <div className="w-full space-y-4">
      <div>
        <h4 className="text-sm font-medium mb-2 text-app-text-muted">Auto Width</h4>
        <Button width="auto" variant="primary">Auto Width</Button>
      </div>
      <div>
        <h4 className="text-sm font-medium mb-2 text-app-text-muted">Fit Content</h4>
        <Button width="fit" variant="secondary">Fit</Button>
      </div>
      <div>
        <h4 className="text-sm font-medium mb-2 text-app-text-muted">Full Width</h4>
        <Button width="full" variant="outline">Full Width Button</Button>
      </div>
    </div>
  ),
  parameters: {
    layout: 'padded',
    docs: {
      description: {
        story: 'Diferentes opciones de ancho: auto, fit, full',
      },
    },
  },
};

// ===== GALERÍA DE VARIANTES =====
export const VariantsGallery: Story = {
  render: () => (
    <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
      <Button variant="primary">Primary</Button>
      <Button variant="secondary">Secondary</Button>
      <Button variant="outline">Outline</Button>
      <Button variant="ghost">Ghost</Button>
      <Button variant="danger">Danger</Button>
      <Button variant="success">Success</Button>
    </div>
  ),
  parameters: {
    docs: {
      description: {
        story: 'Galería completa de todas las variantes disponibles',
      },
    },
  },
};

// ===== CASOS DE USO REALES =====
export const RealWorldExamples: Story = {
  render: () => (
    <div className="space-y-6">
      <div>
        <h4 className="text-lg font-semibold mb-3 text-app-text">Call to Action</h4>
        <div className="flex gap-3">
          <Button 
            variant="primary" 
            size="lg"
            motionConfig={{ hover: { scale: 1.02, y: -1 } }}
          >
            Get Started
          </Button>
          <Button 
            variant="outline" 
            size="lg"
          >
            Learn More
          </Button>
        </div>
      </div>
      
      <div>
        <h4 className="text-lg font-semibold mb-3 text-app-text">Form Actions</h4>
        <div className="flex gap-2">
          <Button variant="success" size="sm">Save</Button>
          <Button variant="secondary" size="sm">Cancel</Button>
          <Button variant="danger" size="sm">Delete</Button>
        </div>
      </div>
      
      <div>
        <h4 className="text-lg font-semibold mb-3 text-app-text">Navigation</h4>
        <div className="flex gap-2">
          <Button variant="ghost" size="sm">Home</Button>
          <Button variant="ghost" size="sm">About</Button>
          <Button variant="ghost" size="sm">Contact</Button>
        </div>
      </div>
    </div>
  ),
  parameters: {
    layout: 'padded',
    docs: {
      description: {
        story: 'Ejemplos de uso en contextos reales: CTAs, formularios, navegación',
      },
    },
  },
};

// ===== PLAYGROUND INTERACTIVO =====
export const Playground: Story = {
  args: {
    children: 'Playground Button',
    variant: 'primary',
    size: 'md',
    width: 'auto',
    loading: false,
    disabled: false,
    motionConfig: {
      hover: { scale: 1.02, y: -1 },
      tap: { scale: 0.98 },
    },
  },
  parameters: {
    docs: {
      description: {
        story: 'Playground interactivo. Usa los controles de abajo para probar todas las opciones disponibles.',
      },
    },
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    
    // Test de interacción básica
    if (!args.disabled && !args.loading) {
      await userEvent.click(button);
      
      // Verificar que se puede hacer hover
      await userEvent.hover(button);
      await new Promise(resolve => setTimeout(resolve, 200));
      await userEvent.unhover(button);
    }
  },
};