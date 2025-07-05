# ⚛️ Playbook de Desarrollo React / Next.js

Este documento complementa el `PLAYBOOK-GENERAL.md` y proporciona directrices específicas para el desarrollo de aplicaciones utilizando React y Next.js. Se enfoca en la creación de componentes modulares, reutilizables y de alto rendimiento, optimizados para la mantenibilidad y la colaboración.

## 🏗️ Arquitectura de Componentes

Adoptamos una adaptación de los principios de **Atomic Design** para estructurar nuestros componentes, promoviendo la modularidad, la reutilización y una clara separación de responsabilidades.

### 1. Filosofía de Diseño

-   **Componentes Puros y Reutilizables:** Los componentes deben ser lo más genéricos posible. La lógica de negocio específica o el estado acoplado a un caso de uso particular deben pasarse a través de las `props` o gestionarse en capas superiores (hooks, contextos).
-   **Composición sobre Herencia:** Preferir la composición de componentes pequeños y enfocados para construir interfaces complejas. Un componente debe hacer una sola cosa y hacerla bien.
-   **Agnosticismo de Framework (cuando sea posible):** Minimizar la dependencia directa de APIs de Next.js dentro de los componentes reutilizables. Las dependencias como `next/link` o `usePathname` deben inyectarse como `props` o manejarse en componentes de nivel superior (ej. en páginas o *layouts*).

### 2. Estructura de Carpetas Estándar (`components/`)

Cada componente debe residir en su propia carpeta, siguiendo el patrón:

```
components/
└── ComponentName/
    ├── index.tsx             # Lógica y renderizado del componente principal.
    ├── ComponentNameStyles.ts # Estilos del componente (clases de Tailwind).
    └── types.ts              # Definiciones de tipos para las props y tipos internos.
```

-   **`index.tsx`:** Es el punto de entrada del componente. Contiene la lógica React y el renderizado. Importa estilos y tipos desde los archivos locales.
-   **`ComponentNameStyles.ts`:** Exporta un objeto `styles` donde cada clave es un elemento del componente y su valor es una cadena de clases de Tailwind CSS. Esto centraliza y organiza los estilos. **No se utilizan CSS Modules (`.module.css`)** a menos que sea estrictamente necesario y justificado por un aislamiento de estilos muy específico.
-   **`types.ts`:** Define y exporta las interfaces de TypeScript para las `props` del componente y cualquier tipo específico interno. Se prioriza la importación de tipos globales (`@/types/`) cuando sea posible.

### 3. Categorización de Componentes (Atomic Design Adaptado)

Los componentes se organizan en subdirectorios dentro de `components/` según su nivel de abstracción y función:

-   **`atoms/`**: Elementos UI básicos e indivisibles (ej. `Button`, `Icon`, `Input`).
    -   `icons/`: Iconos SVG o componentes de iconos.
    -   `inputs/`: Campos de entrada genéricos.
    -   `buttons/`: Botones reutilizables.
    -   `feedback/`: Elementos de feedback visual (ej. spinners, barras de progreso).

-   **`molecules/`**: Combinaciones de átomos que forman unidades funcionales (ej. `SearchForm`, `UserProfileMenu`).
    -   `forms/`: Formularios o partes de formularios.
    -   `navigation/`: Elementos de navegación (ej. `VersionSwitcher`).
    -   `toggles/`: Componentes de alternancia (ej. `SoundToggle`, `ThemeSwitcher`).
    -   `cards/`: Tarjetas de información (ej. `GitHubRepoInfo`).
    -   `markdown/`: Renderizadores de Markdown (unificados y configurables).

-   **`organisms/`**: Secciones complejas de la interfaz, compuestas por moléculas y átomos (ej. `AppSidebar`, `KanbanBoard`).
    -   `navigation/`: Barras laterales, cabeceras, pies de página.
    -   `settings/`: Secciones de configuración complejas.
    -   `kanban/`: Tableros Kanban completos.

-   **`providers/`**: Componentes de orden superior que proveen contexto o funcionalidad global (ej. `ThemeProvider`).

-   **`debug/`**: Herramientas y componentes exclusivos para depuración y desarrollo. Deben ser excluibles del *build* de producción.

## 🎨 Estilado

-   **Tailwind CSS:** Es el framework CSS principal. Se prioriza el uso de clases de utilidad de Tailwind para el estilado.
-   **`cn` Utility:** Utilizar la función `cn` (`@/lib/utils`) para combinar y condicionalmente aplicar clases de Tailwind, manteniendo el código limpio y legible.
-   **Variables CSS:** Para temas y personalización, se utilizan variables CSS (`--primary`, `--background`, etc.) definidas en los archivos de estilo globales o de tema.

## 🔄 Gestión de Estado

-   **React Context API:** Preferencia para la gestión de estado global y la inyección de dependencias a través del árbol de componentes.
-   **`useState` y `useReducer`:** Para el estado local de los componentes o para lógica de estado más compleja dentro de un componente.
-   **Hooks Personalizados (`hooks/`):** Extraer lógica reutilizable y con estado a hooks personalizados para mejorar la modularidad y la legibilidad.

## 📊 Carga de Datos

-   **Separación de Intereses:** La lógica de carga de datos debe estar separada de los componentes de UI. Utilizar hooks personalizados o servicios dedicados (`lib/`) para manejar la obtención y manipulación de datos.
-   **Next.js Data Fetching:** Aprovechar las capacidades de Next.js para la carga de datos (Server Components, Route Handlers) cuando sea apropiado, pero asegurando que los componentes de UI sigan siendo agnósticos a la fuente de datos.

## 🧪 Pruebas

-   **Jest y React Testing Library:** Son las herramientas preferidas para las pruebas unitarias y de integración de componentes React.
-   **Enfoque en el Comportamiento:** Las pruebas deben centrarse en el comportamiento del componente desde la perspectiva del usuario, no en los detalles de implementación internos.

## 🚀 Rendimiento

-   **Memoización:** Utilizar `React.memo`, `useMemo` y `useCallback` para evitar renderizados innecesarios en componentes y funciones costosas.
-   **Carga Diferida (Lazy Loading):** Emplear `next/dynamic` para cargar componentes de forma diferida, especialmente aquellos que no son críticos para la carga inicial de la página.

## 📄 Documentación

-   **JSDoc:** Todos los componentes y hooks deben estar documentados con JSDoc en castellano, siguiendo el formato estándar para Storybook. Esto facilita la comprensión, el mantenimiento y la generación automática de documentación.

---

## 🔗 Referencias Adicionales

-   **`../../GEMINI.md`**: Memoria principal del proyecto y visión general.
-   **`../PLAYBOOK-GENERAL.md`**: Guía metodológica general para el desarrollo de software.
-   **`currentProjectTaskManageManifest/REFACTOR_MANIFEST.json`**: Plan detallado y seguimiento de la refactorización actual.
-   **`./current-refactor/CURRENT_REFACTOR_TODOS.md`**: Checklist en tiempo real del progreso de la refactorización.
-   **`./current-refactor/CURRENT-REFACTOR-PLAN.md`**: Plan de alto nivel para la refactorización actual.
