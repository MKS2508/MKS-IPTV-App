# 📚 Playbook de Desarrollo de Software

Este documento es la guía maestra que establece la metodología, los estándares y las mejores prácticas para el desarrollo de software en cualquier proyecto. Su propósito es asegurar la máxima calidad, consistencia y mantenibilidad del código, facilitando la colaboración entre desarrolladores y optimizando la interacción con agentes de codificación (LLMs).

## 🎯 Filosofía Central: Ingeniería Rigurosa

Abordamos cada tarea con una disciplina de ingeniería, priorizando la calidad y la previsión.

> 1.  **Analizar antes de actuar.**
> 2.  **Planificar antes de construir.**
> 3.  **Verificar antes de finalizar.**

---

## Fase 1: Análisis y Planificación (El Manifiesto del Proyecto)

Todo proyecto o refactorización significativa comienza con un plan detallado. El primer paso es la creación de un **`PROJECT_MANIFEST.md`**.

### 1.1. Análisis Forense del Código

Antes de proponer cualquier solución, se realiza un análisis exhaustivo del código afectado. Los puntos clave a investigar y documentar en el manifiesto son:

-   **Funcionalidad y Responsabilidad:** ¿Qué hace el componente/módulo y cuál es su propósito principal?
-   **Manejo de Estado y Efectos:** ¿Cómo se gestiona el estado (local, global) y los efectos secundarios (`useEffect`)? ¿Hay riesgos de bucles o dependencias incorrectas?
-   **Calidad del Código:**
    -   **Duplicidad:** Identificación de lógica, JSX o estilos repetidos.
    -   **Código Inactivo:** Detección de importaciones, variables o funciones no utilizadas.
    -   **Anti-patrones:** Reconocimiento de prácticas subóptimas (ej. *prop drilling*, `useEffect` mal configurados).
-   **Abstracción y Acoplamiento:** ¿Qué tan genérico es el componente? ¿Depende fuertemente de un *framework* o de un caso de uso específico?
-   **Tipado (`TypeScript`):** ¿Son las interfaces y tipos robustos, claros y reutilizables?

### 1.2. El Plan de Acción Detallado

El manifiesto debe incluir un plan claro y conciso, que contenga:

-   **Acciones Específicas:** Pasos concretos para la implementación o refactorización (ej. "Extraer `useDataFetching`", "Unificar `CardA` y `CardB`").
-   **Estructura Propuesta:** Un esquema visual de la organización de archivos resultante.
-   **Seguimiento:** Una tabla para monitorizar el progreso de cada tarea (`Pendiente`, `En Progreso`, `Hecho`).

---

## Fase 2: Gestión de Versiones (Git y Commits)

La trazabilidad y la colaboración se basan en una gestión de versiones impecable.

### 2.1. Ramas de Trabajo

Todo desarrollo se realiza en ramas dedicadas, nunca directamente en `main`.

-   **Convención de Nombres:** `tipo/descripcion-corta-descriptiva`
    -   `feature/autenticacion-oauth`
    -   `refactor/sistema-temas-unificado`
    -   `fix/bug-login-mobile`

-   **Comando:**
    ```bash
    git checkout -b tipo/descripcion-corta
    ```

### 2.2. Estrategia de Commits: Atómicos y Descriptivos

Cada commit representa una unidad lógica de trabajo. Se utiliza el estándar **Conventional Commits** para facilitar la generación automática de `CHANGELOGs` y la revisión del historial.
NUNCA DEBE AGREGAR CO-AUTHORS

-   **Formato:** `tipo(alcance): mensaje corto en imperativo`

    | Tipo       | Descripción                                     | Ejemplo                                         |
    | :--------- | :---------------------------------------------- | :---------------------------------------------- |
    | `feat`     | Nueva funcionalidad                             | `feat(auth): Añadir inicio de sesión con Google` |
    | `fix`      | Corrección de un error                          | `fix(ui): Corregir desbordamiento en tabla`     |
    | `refactor` | Reestructuración de código sin cambio de func. | `refactor(components): Unificar botones`         |
    | `docs`     | Cambios en la documentación                     | `docs(readme): Actualizar sección de instalación`|
    | `style`    | Formato de código (linting, prettier)           | `style(lint): Aplicar reglas de formato`         |
    | `test`     | Añadir o corregir tests                         | `test(auth): Cubrir casos de borde en login`    |
    | `chore`    | Tareas de mantenimiento, sin impacto en código  | `chore(deps): Actualizar dependencias`          |
    | `perf`     | Mejora de rendimiento                           | `perf(api): Optimizar consulta de usuarios`     |

-   **Cuerpo del Commit (Opcional pero Recomendado):** Para cambios significativos, se debe incluir un cuerpo que explique el **"porqué"** del cambio, el enfoque adoptado y cualquier implicación relevante.

    ```
    refactor(themes): Unificar la gestión de temas en un único proveedor

    Se centraliza toda la lógica de temas (color y modo) en un nuevo
    ThemeProvider para eliminar la duplicación de código y simplificar
    el mantenimiento.

    Este cambio resuelve la deuda técnica relacionada con la existencia
    de múltiples contextos de tema que generaban inconsistencias en la UI.
    ```

---

## Fase 3: Ejecución y Verificación (Definition of Done)

Una tarea o componente se considera "hecho" solo cuando cumple con todos los siguientes criterios:

-   [ ] **Ubicación Correcta:** El archivo reside en la ruta definida en el `docs/current-refactor/REFACTOR_MANIFEST.json`.
-   [ ] **Código Refactorizado:** Se han aplicado todas las acciones del plan (eliminación de duplicados, extracción de hooks, inyección de dependencias, etc.).
-   [ ] **Documentación JSDoc:** El código está completamente documentado en castellano, siguiendo el estándar para herramientas como Storybook.
    ```typescript
    /**
     * Un botón personalizable que soporta varios estilos y tamaños.
     *
     * @component
     * @param {ButtonProps} props Las propiedades del botón.
     * @returns {JSX.Element} El componente de botón renderizado.
     */
    ```
-   [ ] **Importaciones Actualizadas:** Todas las referencias al archivo/componente original en el proyecto han sido actualizadas a la nueva ruta.
-   [ ] **Verificación Pasada:** Los comandos de calidad (`npm run lint`, `npm run test`) se ejecutan sin errores.
-   [ ] **Manifiesto y Checklist Actualizados:** La tarea se marca como `Hecho` en `currentProjectTaskManageManifest/REFACTOR_MANIFEST.json` y en `docs/current-refactor/CURRENT_REFACTOR_TODOS.md`.
-   [ ] **Commit Realizado:** El trabajo se encapsula en un commit atómico y descriptivo.

---

## Anexo: Comandos y Herramientas Útiles

-   **Crear estructura de carpetas anidada:**
    ```bash
    mkdir -p components/atoms/{icons,inputs,buttons}
    ```
-   **Verificar y auto-corregir el formato (ESLint):**
    ```bash
    npm run lint -- --fix
    ```
-   **Ejecutar tests en modo "watch" durante el desarrollo (Jest):**
    ```bash
    npm run test -- --watch
    ```
-   **Buscar todas las importaciones de un componente/módulo (grep):**
    ```bash
    grep -r "components/OldComponent" .
    ```
-   **Renombrar y mover un archivo (mv):**
    ```bash
    mv old/path/file.tsx new/path/index.tsx
    ```
