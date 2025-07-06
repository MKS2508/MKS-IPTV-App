/**
 * @file Stories simplificadas para el componente Button
 * @author MKS
 */

import type { Meta, StoryObj } from '@storybook/react';
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

Componente Button universal con soporte para múltiples variantes, tamaños, estados e iconos.

## Características
- **7 variantes**: primary, secondary, outline, ghost, danger, success, highlight
- **4 tamaños**: sm, md, lg, xl
- **Iconos**: Lucide React y Simple Icons
- **Estados**: loading, disabled
- **Animaciones**: Framer Motion integrado
        `,
      },
    },
  },
  argTypes: {
    variant: {
      control: { type: 'select' },
      options: ['primary', 'secondary', 'outline', 'ghost', 'danger', 'success', 'highlight'],
    },
    size: {
      control: { type: 'select' },
      options: ['sm', 'md', 'lg', 'xl'],
    },
    width: {
      control: { type: 'select' },
      options: ['auto', 'full', 'fit'],
    },
    loading: {
      control: { type: 'boolean' },
    },
    disabled: {
      control: { type: 'boolean' },
    },
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

// ===== COMPARATIVA DE VARIANTES =====
export const AllVariants: Story = {
  render: () => (
    <div className="space-y-8">
      <div>
        <h3 className="text-lg font-semibold mb-4 text-app-text">Todas las Variantes</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Button variant="primary">Primary</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="outline">Outline</Button>
          <Button variant="ghost">Ghost</Button>
          <Button variant="danger">Danger</Button>
          <Button variant="success">Success</Button>
          <Button variant="highlight">Highlight</Button>
          <Button variant="ghost" disabled>Disabled</Button>
        </div>
      </div>
    </div>
  ),
};

// ===== TAMAÑOS COMPARADOS =====
export const Sizes: Story = {
  render: () => (
    <div className="space-y-6">
      <div className="flex items-end gap-4 flex-wrap">
        <Button size="sm" variant="primary">Small</Button>
        <Button size="md" variant="primary">Medium</Button>
        <Button size="lg" variant="primary">Large</Button>
        <Button size="xl" variant="primary">Extra Large</Button>
      </div>
    </div>
  ),
};

// ===== BOTONES CON ICONOS =====
export const WithIcons: Story = {
  render: () => (
    <div className="space-y-8">
      {/* Iconos a la izquierda */}
      <div>
        <h3 className="text-sm font-medium mb-4 text-app-text-muted">Iconos Lucide</h3>
        <div className="flex flex-wrap gap-3">
          <Button 
            variant="primary" 
            icon={{ lucide: 'Download', position: 'left' }}
          >
            Download
          </Button>
          <Button 
            variant="secondary" 
            icon={{ lucide: 'Play', position: 'left' }}
          >
            Play Video
          </Button>
          <Button 
            variant="outline" 
            icon={{ lucide: 'ExternalLink', position: 'right' }}
          >
            Open Link
          </Button>
          <Button 
            variant="success" 
            icon={{ lucide: 'Check', position: 'left' }}
          >
            Confirm
          </Button>
        </div>
      </div>

      {/* Iconos de marcas */}
      <div>
        <h3 className="text-sm font-medium mb-4 text-app-text-muted">Iconos de Marcas</h3>
        <div className="flex flex-wrap gap-3">
          <Button 
            variant="outline" 
            icon={{ simple: 'github', position: 'left' }}
          >
            GitHub
          </Button>
          <Button 
            variant="primary" 
            icon={{ simple: 'apple', position: 'left' }}
          >
            App Store
          </Button>
          <Button 
            variant="secondary" 
            icon={{ simple: 'react', position: 'left' }}
          >
            React App
          </Button>
        </div>
      </div>

      {/* Solo iconos */}
      <div>
        <h3 className="text-sm font-medium mb-4 text-app-text-muted">Solo Iconos</h3>
        <div className="flex flex-wrap gap-3">
          <Button 
            variant="primary" 
            size="sm"
            icon={{ lucide: 'Settings', position: 'only' }}
            aria-label="Settings"
          />
          <Button 
            variant="secondary" 
            size="md"
            icon={{ lucide: 'Menu', position: 'only' }}
            aria-label="Menu"
          />
          <Button 
            variant="outline" 
            size="lg"
            icon={{ lucide: 'Plus', position: 'only' }}
            aria-label="Add"
          />
          <Button 
            variant="danger" 
            size="sm"
            icon={{ lucide: 'X', position: 'only' }}
            aria-label="Close"
          />
        </div>
      </div>
    </div>
  ),
};

// ===== ESTADOS ESPECIALES =====
export const States: Story = {
  render: () => (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-medium mb-4 text-app-text-muted">Estados de Carga</h3>
        <div className="flex flex-wrap gap-3">
          <Button loading variant="primary">Loading Primary</Button>
          <Button loading variant="secondary">Loading Secondary</Button>
          <Button loading variant="outline">Loading Outline</Button>
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium mb-4 text-app-text-muted">Estados Deshabilitados</h3>
        <div className="flex flex-wrap gap-3">
          <Button disabled variant="primary">Disabled Primary</Button>
          <Button disabled variant="secondary">Disabled Secondary</Button>
          <Button disabled variant="outline">Disabled Outline</Button>
        </div>
      </div>
    </div>
  ),
};

// ===== CASOS DE USO COMUNES =====
export const CommonUseCases: Story = {
  render: () => (
    <div className="space-y-8 max-w-2xl">
      {/* Call to Actions */}
      <div className="border border-app-border rounded-lg p-6 bg-app-surface/50">
        <h3 className="text-lg font-semibold mb-4 text-app-text">Hero Call to Actions</h3>
        <div className="flex gap-3">
          <Button 
            variant="primary" 
            size="lg"
            icon={{ lucide: 'Download', position: 'left' }}
          >
            Get Started
          </Button>
          <Button 
            variant="outline" 
            size="lg"
            icon={{ lucide: 'BookOpen', position: 'left' }}
          >
            Documentation
          </Button>
        </div>
      </div>

      {/* Formularios */}
      <div className="border border-app-border rounded-lg p-6 bg-app-surface/50">
        <h3 className="text-lg font-semibold mb-4 text-app-text">Form Actions</h3>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" size="md">Cancel</Button>
          <Button variant="primary" size="md">Save Changes</Button>
        </div>
      </div>

      {/* Acciones de tabla */}
      <div className="border border-app-border rounded-lg p-6 bg-app-surface/50">
        <h3 className="text-lg font-semibold mb-4 text-app-text">Table Actions</h3>
        <div className="flex gap-2">
          <Button 
            variant="ghost" 
            size="sm"
            icon={{ lucide: 'Eye', position: 'only' }}
            aria-label="View"
          />
          <Button 
            variant="ghost" 
            size="sm"
            icon={{ lucide: 'Edit', position: 'only' }}
            aria-label="Edit"
          />
          <Button 
            variant="ghost" 
            size="sm"
            icon={{ lucide: 'Trash2', position: 'only' }}
            aria-label="Delete"
          />
        </div>
      </div>

      {/* Enlaces externos */}
      <div className="border border-app-border rounded-lg p-6 bg-app-surface/50">
        <h3 className="text-lg font-semibold mb-4 text-app-text">External Links</h3>
        <div className="flex flex-wrap gap-3">
          <Button 
            as="link"
            href="https://github.com"
            external
            variant="outline" 
            size="sm"
            icon={{ simple: 'github', position: 'left' }}
          >
            View on GitHub
          </Button>
          <Button 
            as="link"
            href="#"
            variant="ghost" 
            size="sm"
            icon={{ lucide: 'ExternalLink', position: 'right' }}
          >
            Learn More
          </Button>
        </div>
      </div>
    </div>
  ),
};

// ===== PLAYGROUND =====
export const Playground: Story = {
  args: {
    children: 'Playground Button',
    variant: 'primary',
    size: 'md',
    width: 'auto',
    loading: false,
    disabled: false,
  },
};