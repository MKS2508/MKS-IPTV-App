# MUST-FOLLOW-GUIDELINES.md

> **IMPORTANTE**: Este documento es la fuente de verdad para todas las reglas de desarrollo en este proyecto.
> **El incumplimiento de estas reglas sera motivo de correccion obligatoria en code review.**

---

## Stack Definitivo

| Herramienta | Version/Configuracion | Uso |
|-------------|----------------------|-----|
| **Runtime** | Bun v1.1.43+ | Package manager + runtime |
| **Bundling** | Rolldown v1.0.0-beta.58 | Build de packages |
| **Type Checking** | TSGO v7.0.0-dev (@typescript/native-preview) | TypeScript compiler |
| **Linting** | Oxlint v0.11.1 | Linting rapido (OxC-based) |
| **Formatting** | Prettier v3.4.2 + organize-imports | Formato de codigo |
| **Validation** | Arktype | Validacion de esquemas |
| **Versioning** | Changesets v2.27.11 | Versionado de packages |
| **Logging** | @mks2508/better-logger v4.0.0 | Logging estructurado |
| **Error Handling** | @mks2508/no-throw v0.1.0 | Result pattern |
| **Commit Generation** | gemini-commit-wizard v1.1.3 | Commits estructurados con IA multi-provider |

---

## Commit Workflow — gemini-commit-wizard

**OBLIGATORIO**: Usar `bun run commit` para TODOS los commits. NUNCA hacer commits manuales sin formato estructurado.

### Providers Disponibles

| Provider | Variable de Entorno | Modelo Default | Velocidad |
|----------|-------------------|---------------|-----------|
| **Gemini SDK** | `GEMINI_API_KEY` | `gemini-2.5-flash` | Rapido |
| **Groq** | `GROQ_API_KEY` | `llama-3.3-70b-versatile` | Ultra-rapido |
| **OpenRouter** | `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4` | Variable |
| **Gemini CLI** | _(necesita binario `gemini`)_ | CLI default | Moderado |

**Auto-deteccion**: Gemini SDK > Groq > OpenRouter > Gemini CLI. El primer provider con API key valida se usa automaticamente.

### Comandos

```bash
# Commit interactivo con IA (auto-detecta provider)
bun run commit

# Modo rapido sin prompts
bun run commit:quick

# Auto-aprobar sin push
bun run commit:auto

# Provider especifico
bun run commit -- --provider groq

# Provider + modelo especifico
bun run commit -- --provider openrouter --model anthropic/claude-sonnet-4
```

### Formato de Commit Estructurado

```
type(scope): description

Body text (en idioma configurado)

<technical>
- Detalles tecnicos: archivos, funciones, tipos modificados
</technical>

<changelog>
## [Type] [Emoji]
Entrada de changelog orientada al usuario
</changelog>
```

**Types validos**: `feat`, `fix`, `refactor`, `docs`, `test`, `feat-phase` (feature incompleta)

### Configuracion por Proyecto

Crear `.commit-wizard.json` en la raiz del proyecto:

```json
{
  "name": "mi-proyecto",
  "description": "Descripcion breve",
  "techStack": ["TypeScript", "Bun"],
  "components": [
    { "id": "api", "path": "src/api/", "name": "REST API" }
  ],
  "commitFormat": {
    "titleLanguage": "english",
    "bodyLanguage": "spanish",
    "includeTechnical": true,
    "includeChangelog": true
  },
  "provider": "groq",
  "model": "llama-3.3-70b-versatile"
}
```

### Prohibido

- `git commit -m "mensaje"` sin formato estructurado
- Commits sin `<technical>` y `<changelog>` sections
- Usar providers sin API key configurada (el wizard valida automaticamente)

---

## Estructura de Carpetas Obligatoria

### Root del Monorepo
```
mks-dev-environment/
├── docs/                    # Documentacion del proyecto
├── tools/                   # Scripts y herramientas de desarrollo
├── core/
│   └── packages/
│       ├── main/
│       └── utils/
└── apps/
    └── example/
```

### Estructura de un Package
```
core/packages/main/
├── src/
│   ├── utils/               # Utilidades locales del package
│   │   └── index.ts         # Barrel export
│   ├── types/               # Tipos del dominio del package
│   │   ├── *.types.ts       # Tipos especificos
│   │   ├── constants.ts     # Constantes del package
│   │   └── index.ts         # Barrel export
│   ├── *.ts                 # Codigo fuente principal
│   └── index.ts             # Export principal
├── dist/                    # Build output
├── package.json
├── rolldown.config.ts
└── tsconfig.json
```

---

## REGLA 1: JSDoc Completo Profesional

### Requerimientos Obligatorios

TODA funcion, clase, metodo, interface, type, y constante exportada DEBE tener JSDoc completo:

```typescript
/**
 * Descripcion clara y concisa de que hace y por que.
 *
 * @example
 * ```typescript
 * // Codigo ejecutable que demuestra uso tipico
 * const result = await myFunction('example');
 * if (result.isErr()) {
 *   log.error('Failed', result.error);
 *   return;
 * }
 * console.log(result.value);
 * ```
 *
 * @param paramName - Descripcion del parametro
 * @returns Result<T, E> Descripcion del valor de retorno
 * @throws {AppError} Cuando y por que se lanza este error
 * @see {@link IOptions} Referencias a tipos relacionados
 */
export async function myFunction(
  param: string,
  options?: IOptions
): Promise<Result<string, AppError>> {
  // ...
}
```

### Tags Obligatorios

| Tag | Cuando usar | Formato |
|-----|-------------|---------|
| `@description` | Siempre | Primera linea (implicita) |
| `@param` | Cada parametro | `@param name - Description` |
| `@returns` | Siempre | `@returns Type - Description` |
| `@example` | Funciones publicas | Codigo TypeScript ejecutable |
| `@throws` | Si puede lanzar | `@throws {ErrorType} Cuando` |
| `@see` | Referencias | `@see {@link ISomething}` |

---

## REGLA 2: Logging - NUNCA console.log

Usar `@mks2508/better-logger` para todo el logging.

### Imports y Setup Basico

```typescript
// Singleton (recomendado para la mayoria de casos)
import logger from '@mks2508/better-logger';

// O crear instancia personalizada
import { Logger } from '@mks2508/better-logger';
const log = new Logger({
  verbosity: 'debug',          // 'debug' | 'info' | 'warn' | 'error' | 'silent'
  enableStackTrace: true,       // Muestra archivo:linea
  bufferSize: 1000,             // Para exportacion de logs
});
```

### Metodos de Logging

```typescript
// Niveles basicos
logger.debug('Debug message', { context });
logger.info('Info message');
logger.warn('Warning message');
logger.error('Error message', errorObject);
logger.success('Operation completed');
logger.critical('System failure!');
logger.trace('Trace from nested function');
```

### Scoped Loggers (USAR SIEMPRE en servicios)

```typescript
// ComponentLogger - Para componentes UI y servicios
const authLog = logger.component('AuthService');
authLog.info('Usuario autenticando...');   // [COMPONENT] [AuthService] Usuario...
authLog.success('Login exitoso');
authLog.lifecycle('mount', 'Component mounted');
authLog.stateChange('idle', 'loading');

// APILogger - Para endpoints y llamadas HTTP
const apiLog = logger.api('UserAPI');
apiLog.info('GET /users');                 // [API] [UserAPI] GET /users
apiLog.slow('Response slow', 2500);        // [API] [SLOW] Response slow (2500ms)
apiLog.rateLimit('Too many requests');     // [API] [RATE_LIMIT]
apiLog.deprecated('Use /v2/users instead');

// ScopedLogger - Generico con contextos anidados
const dbLog = logger.scope('Database');
dbLog.info('Query executing');
dbLog.context('transactions').run(() => {
  dbLog.info('Inside transaction');        // [Database:transactions] Inside...
});
```

### Timing y Performance

```typescript
// Medir operaciones
logger.time('db-query');
await db.query('SELECT * FROM users');
logger.timeEnd('db-query');  // Timer: db-query - 234.56ms

// En scoped loggers
const serviceLog = logger.component('ProductService');
serviceLog.time('fetch-products');
const products = await fetchProducts();
serviceLog.timeEnd('fetch-products');
```

### Badges para Contexto

```typescript
// Badges encadenables
logger.badges(['CACHE', 'HIT']).info('Data from cache');
logger.badge('v2').badge('stable').info('API response');

// En scoped loggers
const api = logger.api('GraphQL');
api.badges(['mutation', 'user']).info('createUser executed');
```

### Transports (Envio de Logs)

```typescript
import logger, {
  FileTransport,
  HttpTransport,
  addTransport
} from '@mks2508/better-logger';

// Transport a archivo (solo Node.js/Bun)
logger.addTransport({
  target: 'file',
  options: {
    destination: '/var/log/app.log',
    batchSize: 100,
    flushInterval: 5000  // ms
  },
  level: 'warn'  // Solo warn+ van al archivo
});

// Transport HTTP (envia a servidor de logs)
logger.addTransport({
  target: 'http',
  options: {
    url: 'https://logs.example.com/ingest',
    headers: { 'Authorization': 'Bearer xxx' },
    batchSize: 50,
    flushInterval: 10000
  }
});

// Flush manual antes de cerrar
await logger.flushTransports();
await logger.closeTransports();
```

### Hooks y Middleware

```typescript
// Hook beforeLog - agregar metadata
logger.on('beforeLog', (entry) => {
  entry.correlationId = getCorrelationId();
  entry.userId = getCurrentUserId();
  return entry;
});

// Hook afterLog - side effects
logger.on('afterLog', (entry) => {
  if (entry.level === 'error') {
    sendToErrorTracking(entry);
  }
});

// Middleware - pipeline de procesamiento
logger.use((entry, next) => {
  // Enriquecer con request context
  const store = asyncLocalStorage.getStore();
  if (store?.requestId) {
    entry.requestId = store.requestId;
  }
  next();
});
```

### Serializers Personalizados

```typescript
// Serializar errores de forma estructurada
logger.addSerializer(Error, (err) => ({
  name: err.name,
  message: err.message,
  stack: err.stack?.split('\n').slice(0, 5),
  code: (err as any).code
}));

// Serializar objetos custom
logger.addSerializer(User, (user) => ({
  id: user.id,
  email: '[REDACTED]',
  role: user.role
}));
```

### Configuracion Frontend vs Backend

```typescript
// === BACKEND (Node.js/Bun) ===
import logger from '@mks2508/better-logger';

// Preset optimizado para terminal
logger.preset('cyberpunk');
logger.showTimestamp();
logger.showLocation();

// Transport a archivo
logger.addTransport({
  target: 'file',
  options: { destination: './logs/app.log' }
});

// === FRONTEND (Browser) ===
import logger from '@mks2508/better-logger';

// Preset con colores CSS
logger.preset('default');
logger.hideLocation();  // No util en browser

// Transport HTTP para enviar errores
logger.addTransport({
  target: 'http',
  options: { url: '/api/logs' },
  level: 'error'  // Solo errores al servidor
});
```

### Verbosity y Filtrado

```typescript
// Cambiar nivel de verbosidad
logger.setVerbosity('warn');   // Solo warn, error, critical
logger.setVerbosity('silent'); // Desactiva todo
logger.setVerbosity('debug');  // Muestra todo

// Configuracion condicional
if (process.env.NODE_ENV === 'production') {
  logger.setVerbosity('warn');
  logger.hideLocation();
}
```

### Utilidades de Grupos y Tablas

```typescript
// Tablas de datos
logger.table([
  { name: 'Alice', age: 30 },
  { name: 'Bob', age: 25 }
]);

// Grupos colapsables
logger.group('Database Operations');
logger.info('Connecting...');
logger.info('Querying...');
logger.groupEnd();

// Grupo colapsado por defecto
logger.group('Debug Details', true);
logger.debug('Verbose info here');
logger.groupEnd();
```

### Prohibido

```typescript
// INCORRECTO - NUNCA usar
console.log('Started');
console.error('Failed');
console.info('Info');
console.warn('Warning');
console.debug('Debug');
```

---

## REGLA 3: Result Pattern - SIEMPRE

### Obligatorio

TODA operacion que pueda fallar DEBE usar `Result<T, E>` del package `@mks2508/no-throw`:

```typescript
import {
  ok, err, fail,
  isOk, isErr,
  map, mapErr, flatMap,
  match,
  tryCatch, tryCatchAsync, fromPromise,
  unwrap, unwrapOr, unwrapOrElse,
  tap, tapErr,
  collect, all,
  type Result, type ResultError
} from '@mks2508/no-throw';
```

### Constructores

```typescript
// Crear resultado exitoso
const success = ok(42);                    // Result<number, never>
const success2 = ok({ name: 'John' });     // Result<{name: string}, never>

// Crear resultado de error
const error = err('Something failed');     // Result<never, string>

// Crear error estructurado con fail()
const structuredError = fail(
  'NETWORK_ERROR',           // code
  'Failed to fetch data',    // message
  originalError              // cause (opcional)
);
// Retorna: Result<never, ResultError<'NETWORK_ERROR'>>
```

### Type Guards

```typescript
const result = await fetchData(url);

if (isOk(result)) {
  console.log(result.value);  // Tipo: T
}

if (isErr(result)) {
  console.log(result.error);  // Tipo: E
}
```

### Transformaciones

```typescript
// map - transforma el valor si es Ok
const doubled = map(result, (n) => n * 2);

// mapErr - transforma el error si es Err
const mappedErr = mapErr(result, (e) => ({ ...e, timestamp: Date.now() }));

// flatMap - encadena operaciones que retornan Result
const chained = flatMap(result, (value) => {
  if (value > 100) return err('Too large');
  return ok(value * 2);
});
```

### Pattern Matching

```typescript
const message = match(result, {
  ok: (value) => `Success: ${value}`,
  err: (error) => `Error: ${error.message}`
});
```

### Manejo de Excepciones

```typescript
// tryCatch - para operaciones sincronas
const syncResult = tryCatch(
  () => JSON.parse(jsonString),
  'PARSE_ERROR'
);

// tryCatchAsync - para operaciones async
const asyncResult = await tryCatchAsync(
  async () => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  },
  'NETWORK_ERROR'
);

// fromPromise - convierte Promise a Result
const promiseResult = await fromPromise(
  fetch(url).then(r => r.json()),
  'FETCH_ERROR'
);
```

### Unwrap

```typescript
// unwrap - obtiene valor o lanza error
const value = unwrap(result);  // Throws si es Err

// unwrapOr - valor por defecto
const valueOrDefault = unwrapOr(result, 0);

// unwrapOrElse - valor calculado
const valueOrComputed = unwrapOrElse(result, (error) => {
  log.error('Using fallback due to:', error);
  return defaultValue;
});
```

### Efectos Secundarios

```typescript
// tap - ejecuta efecto si es Ok (no modifica resultado)
const logged = tap(result, (value) => {
  log.info('Got value:', value);
});

// tapErr - ejecuta efecto si es Err
const errorLogged = tapErr(result, (error) => {
  log.error('Operation failed:', error);
});
```

### Colecciones

```typescript
// collect - convierte array de Results en Result de array
const results: Result<number, string>[] = [ok(1), ok(2), ok(3)];
const collected = collect(results);  // Result<number[], string>

// all - igual que collect (alias)
const allResults = all([ok(1), ok(2), ok(3)]);
```

### Ejemplo Completo

```typescript
import { ok, fail, isErr, tryCatchAsync, match } from '@mks2508/no-throw';
import logger from '@mks2508/better-logger';

const log = logger.component('UserService');

async function fetchUser(
  id: string
): Promise<Result<IUser, ResultError<'NOT_FOUND' | 'NETWORK_ERROR'>>> {
  const result = await tryCatchAsync(
    async () => {
      const response = await fetch(`/api/users/${id}`);
      if (response.status === 404) {
        throw { code: 'NOT_FOUND' };
      }
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return await response.json();
    },
    'NETWORK_ERROR'
  );

  if (isErr(result)) {
    const error = result.error;
    if (error.cause?.code === 'NOT_FOUND') {
      return fail('NOT_FOUND', `User ${id} not found`);
    }
    return fail('NETWORK_ERROR', `Failed to fetch user ${id}`, error);
  }

  return ok(result.value);
}

// Uso
const userResult = await fetchUser('123');
const message = match(userResult, {
  ok: (user) => {
    log.success(`User loaded: ${user.name}`);
    return user;
  },
  err: (error) => {
    log.error(`Failed: ${error.message}`);
    return null;
  }
});
```

### Prohibido

```typescript
// INCORRECTO - NUNCA usar try/catch directo sin Result
try {
  const data = await fetchData();
} catch (e) {
  console.error(e);
}

// INCORRECTO - NUNCA lanzar excepciones
throw new Error('Something failed');

// CORRECTO - Siempre retornar Result
return fail('ERROR_CODE', 'Description', cause);
```

---

## REGLA 4: Nomenclatura - Prefijo I

### Interfaces

```typescript
// CORRECTO - Prefijo I
export interface IOptions {
  url: string;
  timeout?: number;
}

export interface ICallback {
  onSuccess: () => void;
  onError: (error: Error) => void;
}
```

### Types (sin prefijo)

```typescript
// CORRECTO - Sin prefijo
export type Options = {
  url: string;
  timeout?: number;
};

export type ErrorCode =
  | 'NETWORK_ERROR'
  | 'NOT_FOUND'
  | 'PERMISSION_DENIED';
```

---

## REGLA 5: Barrel Exports - SIEMPRE

TODA carpeta con multiples archivos DEBE tener un `index.ts` que exporte todo:

```typescript
// src/types/index.ts
export * from './main.types';
export * from './constants';
```

---

## REGLA 6: Async/Await - Preferencia

```typescript
// CORRECTO - Async/await
async function processFile(path: string): Promise<void> {
  const content = await readFile(path);
  const processed = await transform(content);
  await writeFile(path, processed);
}

// INCORRECTO - Promise chaining
function processFile(path: string) {
  return readFile(path)
    .then(content => transform(content))
    .then(processed => writeFile(path, processed));
}
```

---

## Checklist Pre-Commit

Antes de hacer commit de codigo, verificar:

- [ ] Todo codigo nuevo tiene JSDoc completo
- [ ] No hay `console.log/debug/error/info/warn`
- [ ] Todo lo que puede fallar usa `Result<T, E>`
- [ ] Interfaces tienen prefijo `I`
- [ ] Barrel exports en todas las carpetas
- [ ] Async/await en lugar de Promise chaining
- [ ] `bun run typecheck` pasa
- [ ] `bun run lint` pasa
- [ ] `bun run format` aplicado

---

## REGLA 7: TransactionState - Estados de UI

### Estados Soportados

| Estado | Uso |
|--------|-----|
| `initial` | Estado inicial, sin datos |
| `loading` | Primera carga en progreso |
| `revalidating` | Recargando con datos previos |
| `success` | Operacion completada con exito |
| `failed` | Error en la operacion |

### Factories y Guards

```typescript
// Factories
createInitialState()
createLoadingState(message?: string)
createRevalidatingState(previousData: T)
createSuccessState(data: T, message?: string)
createFailedState(error: E)

// Guards
isInitial(state)    // true si initial
isLoading(state)    // true si loading
isRevalidating(state)
isSuccess(state)
isFailed(state)
isPending(state)    // loading OR revalidating
isCompleted(state)  // success OR failed
hasData(state)      // success OR revalidating
```

### Patron en Hooks

```typescript
const [state, setState] = useState<TransactionState<T, E>>(createInitialState);

const load = useCallback(async () => {
  setState(createLoadingState('Cargando...'));
  const result = await service.fetch();
  if (isSuccess(result)) {
    setState(createSuccessState(result.data));
  } else {
    setState(createFailedState(result.error));
  }
}, []);
```

---

## REGLA 8: Arquitectura BLO (Business Logic Layer)

### Principios Fundamentales

| Principio | Descripcion |
|-----------|-------------|
| **Separacion clara** | UI y logica de negocio en capas distintas |
| **Handlers** | Clases puras TypeScript sin dependencias React |
| **Hooks** | Puente reactivo entre handlers y componentes |
| **Componentes** | Solo UI y eventos, sin logica de negocio |

### Clasificacion de Componentes

#### Componentes UI Reutilizables (`components/ui/`)
- **Alta reusabilidad** en diferentes contextos
- **Baja complejidad** y focalizacion especifica
- **Estructura simplificada** (archivo unico o pocos archivos)
- Ejemplos: Button, Input, Card, Modal

#### Componentes de Dominio (`components/`)
- **Alta complejidad** y logica de negocio especifica
- **Estructura completa** con handler y hook
- **Subcomponentes** si es necesario
- Ejemplos: ProductCard, UserProfile, OrderDetails

### Estructura Completa (Componentes Complejos)

```
components/
└── ProductCard/
    ├── index.tsx              # Componente React puro
    ├── ProductCard.types.ts   # Interfaces y tipos
    ├── ProductCard.styles.ts  # Clases Tailwind con CVA
    ├── ProductCard.handler.ts # Logica de negocio (BLO)
    ├── ProductCard.hook.ts    # Hook React con estado
    └── components/            # Subcomponentes (opcional)
        ├── ProductImage/
        └── ProductActions/
```

### Componente React (`index.tsx`)

```typescript
import React from 'react';
import { IProductCardProps } from './ProductCard.types';
import { styles } from './ProductCard.styles';
import { useProductCard } from './ProductCard.hook';

export const ProductCard: React.FC<IProductCardProps> = (props) => {
  const { state, actions } = useProductCard(props);

  return (
    <div className={styles.container}>
      {/* Solo UI y eventos - sin logica de negocio */}
      <h3 className={styles.title}>{state.data?.name}</h3>
      <button onClick={actions.addToCart}>Agregar</button>
    </div>
  );
};
```

**Reglas del componente:**
- ✅ Solo UI: renderizado y eventos
- ✅ Props inmutables: no modificar props directamente
- ✅ Estado delegado: usar hook para estado y acciones
- ❌ Sin logica: no business logic en el componente

### Tipos TypeScript (`.types.ts`)

```typescript
export interface IProductCardProps {
  productId: string;
  initialData?: IProduct;
  autoLoad?: boolean;
  className?: string;
  onAddToCart?: (id: string) => void;
}

export interface IProductCardState {
  isLoading: boolean;
  data: IProduct | null;
  error: string | null;
}

export interface IProductCardActions {
  loadProduct: () => Promise<void>;
  addToCart: () => void;
  reset: () => void;
}
```

### Estilos Tailwind con CVA (`.styles.ts`)

```typescript
import { cva } from 'class-variance-authority';

export const containerVariants = cva(
  "w-full p-4 bg-white border rounded-lg transition-shadow",
  {
    variants: {
      variant: {
        default: "border-gray-200 hover:shadow-md",
        featured: "border-blue-200 bg-blue-50 hover:shadow-lg",
        compact: "p-2 border-gray-100",
      },
      size: {
        sm: "max-w-xs",
        md: "max-w-sm",
        lg: "max-w-md",
      }
    },
    defaultVariants: {
      variant: "default",
      size: "md",
    }
  }
);

export const styles = {
  container: containerVariants,
  header: "flex items-center justify-between mb-4",
  title: "text-lg font-semibold text-gray-900",
  content: "text-gray-600 min-h-[100px]",
  actions: "flex gap-2 mt-4 pt-4 border-t border-gray-200",
  loading: "flex items-center justify-center py-8 text-gray-500",
  error: "flex items-center justify-center py-8 text-red-500 bg-red-50 rounded",
};
```

### Handler BLO (`.handler.ts`)

```typescript
import { IProductCardState } from './ProductCard.types';

export class ProductCardHandler {
  private state: IProductCardState = {
    isLoading: false,
    data: null,
    error: null,
  };

  constructor(initialData?: IProduct) {
    if (initialData) {
      this.state.data = initialData;
    }
  }

  getState(): IProductCardState {
    return { ...this.state };  // Siempre retornar copia
  }

  async loadProduct(productId: string): Promise<void> {
    this.state.isLoading = true;
    this.state.error = null;

    try {
      // Logica de negocio pura - sin React
      const response = await fetch(`/api/products/${productId}`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      this.state.data = await response.json();
    } catch (error) {
      this.state.error = error instanceof Error ? error.message : 'Error';
    } finally {
      this.state.isLoading = false;
    }
  }

  reset(): void {
    this.state = { isLoading: false, data: null, error: null };
  }
}
```

**Reglas del handler:**
- ✅ Clase pura TypeScript: sin dependencias de React
- ✅ Estado inmutable: siempre retornar copias
- ✅ Logica de negocio: validaciones, transformaciones, API calls
- ✅ Testing facil: sin dependencias externas
- ❌ Sin React: no hooks, no JSX, no estado React

### Hook React (`.hook.ts`)

```typescript
import { useState, useCallback, useEffect } from 'react';
import { IProductCardProps, IProductCardState, IProductCardActions } from './ProductCard.types';
import { ProductCardHandler } from './ProductCard.handler';

export const useProductCard = (props: IProductCardProps) => {
  const [handler] = useState(() => new ProductCardHandler(props.initialData));
  const [state, setState] = useState<IProductCardState>(handler.getState());

  const loadProduct = useCallback(async () => {
    await handler.loadProduct(props.productId);
    setState(handler.getState());
  }, [handler, props.productId]);

  const addToCart = useCallback(() => {
    if (state.data && props.onAddToCart) {
      props.onAddToCart(state.data.id);
    }
  }, [state.data, props.onAddToCart]);

  const reset = useCallback(() => {
    handler.reset();
    setState(handler.getState());
  }, [handler]);

  useEffect(() => {
    if (props.autoLoad) {
      loadProduct();
    }
  }, [props.autoLoad, loadProduct]);

  return {
    state,
    actions: { loadProduct, addToCart, reset } as IProductCardActions,
  };
};
```

**Reglas del hook:**
- ✅ Puente reactivo: entre handler y componente
- ✅ Estado React: sincronizado con handler
- ✅ Callbacks memorizados: useCallback para optimizacion
- ✅ Efectos controlados: auto-load, dependencies
- ✅ Interface consistente: siempre retorna `{ state, actions }`

### Nombres de Archivos

```typescript
// CORRECTO - PascalCase
ProductCard.tsx
UserProfile.tsx
DataTable.tsx

// INCORRECTO
my-component.tsx
user_profile.tsx
dataTable.tsx
```

### Generacion con mks-ui CLI

```bash
# Componente UI simple (archivo unico)
mks-ui component Button --ui

# Componente complejo con BLO
mks-ui component ProductCard --complex

# Vista previa sin crear
mks-ui component TestComponent --dry-run

# Servicio backend
mks-ui service ProductService
```

---

## REGLA 9: Zustand con Slices

### Store Central por Dominio

```typescript
// stores/app.store.ts
import { create } from 'zustand';

interface IAppStore {
  // UI Slice
  ui: { sidebarOpen: boolean; theme: 'light' | 'dark' };
  toggleSidebar: () => void;

  // Data Slice
  users: IUser[];
  setUsers: (users: IUser[]) => void;
}

export const useAppStore = create<IAppStore>((set) => ({
  ui: { sidebarOpen: true, theme: 'light' },
  toggleSidebar: () => set((s) => ({
    ui: { ...s.ui, sidebarOpen: !s.ui.sidebarOpen }
  })),

  users: [],
  setUsers: (users) => set({ users }),
}));
```

### Selectores Puros

```typescript
// CORRECTO - Selector especifico previene renders
const theme = useAppStore((s) => s.ui.theme);

// INCORRECTO - Re-render en cualquier cambio
const store = useAppStore();
const theme = store.ui.theme;
```

---

## REGLA 10: Handler Pattern

### Fachada de Orquestacion

```typescript
// handlers/useUserHandler.ts
export const useUserHandler = (service: UserService) => {
  const { state, load } = useUserLoader(service);
  const setUsers = useAppStore((s) => s.setUsers);

  const refresh = useCallback(async (id: string) => {
    const result = await load(id);
    if (isSuccess(result)) {
      setUsers([result.data]);
    }
    return result;
  }, [load, setUsers]);

  return useMemo(() => ({
    isLoading: isPending(state),
    hasError: isFailed(state),
    user: hasData(state) ? state.data : null,
    refresh,
  }), [state, refresh]);
};
```

### Reglas del Handler

- API publica memorizada con `useMemo`
- Callbacks con `useCallback`
- No exponer detalles internos (state crudo)
- No usar `useEffect` salvo sincronizacion externa

---

## REGLA 11: BaseService para HTTP

### Clase Base

```typescript
export abstract class BaseService {
  constructor(
    protected readonly baseUrl: string,
    protected readonly fetchImpl = fetch
  ) {}

  protected async request<T>({
    path,
    method = 'GET',
    body,
    timeoutMs = 15000,
    signal,
  }: IRequestOptions): Promise<Response> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    try {
      return await this.fetchImpl(`${this.baseUrl}${path}`, {
        method,
        headers: { 'content-type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined,
        signal: signal ?? controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }
  }
}
```

### Error Taxonomy

```typescript
export type ServiceError =
  | { kind: 'timeout'; message: string }
  | { kind: 'unauthorized'; message: string }      // 401
  | { kind: 'forbidden'; message: string }         // 403
  | { kind: 'not_found'; message: string }         // 404
  | { kind: 'conflict'; message: string }          // 409
  | { kind: 'too_many_requests'; message: string } // 429
  | { kind: 'server_error'; message: string; status: number } // 5xx
  | { kind: 'decode_error'; message: string }
  | { kind: 'unexpected'; message: string };
```

### Servicio Tipado

```typescript
export class UserService extends BaseService {
  async getUser(id: string): Promise<Result<IUser, ServiceError>> {
    try {
      const res = await this.request({ path: `/users/${id}` });

      if (res.status === 401) return err({ kind: 'unauthorized', message: 'No autenticado' });
      if (res.status === 403) return err({ kind: 'forbidden', message: 'No autorizado' });
      if (res.status === 404) return err({ kind: 'not_found', message: 'Usuario no encontrado' });
      if (!res.ok) return err({ kind: 'server_error', message: 'Error servidor', status: res.status });

      const json = await res.json();
      const parsed = UserSchema.safeParse(json);
      if (!parsed.success) return err({ kind: 'decode_error', message: parsed.error.message });

      return ok(parsed.data);
    } catch (e) {
      if ((e as Error)?.name === 'AbortError') {
        return err({ kind: 'timeout', message: 'Timeout' });
      }
      return err({ kind: 'unexpected', message: (e as Error)?.message ?? 'Error inesperado' });
    }
  }
}
```

---

## REGLA 12: React Best Practices

### Minimizar useEffect

```typescript
// CORRECTO - useMemo para derivar datos
const filteredUsers = useMemo(
  () => users.filter(u => u.active),
  [users]
);

// INCORRECTO - useEffect para derivar datos
const [filteredUsers, setFiltered] = useState([]);
useEffect(() => {
  setFiltered(users.filter(u => u.active));
}, [users]);
```

### memo para Componentes Puros

```typescript
// CORRECTO
export const UserCard = memo(({ user }: IUserCardProps) => (
  <div>{user.name}</div>
));

// useState solo para estado efimero local
const [inputValue, setInputValue] = useState('');
```

---

## Checklist Pre-Commit

Antes de hacer commit de codigo, verificar:

- [ ] Todo codigo nuevo tiene JSDoc completo
- [ ] No hay `console.log/debug/error/info/warn`
- [ ] Todo lo que puede fallar usa `Result<T, E>`
- [ ] Interfaces tienen prefijo `I`
- [ ] Barrel exports en todas las carpetas
- [ ] Async/await en lugar de Promise chaining
- [ ] Componentes UI siguen estructura de archivos
- [ ] Estados de UI usan TransactionState
- [ ] Stores usan selectores puros
- [ ] Handlers exponen API memorizada
- [ ] `bun run typecheck` pasa
- [ ] `bun run lint` pasa
- [ ] `bun run format` aplicado

---

## REGLA 13: UI Components - Shadcn MCP + React Bits + lucide-animated

### Stack de Componentes UI

**OBLIGATORIO**: Usar Shadcn MCP Server para instalar componentes via registries externos.

| Registry | URL | Tipo | Prioridad |
|----------|-----|------|-----------|
| **@animate-ui** | `https://animate-ui.com/r/{name}.json` | Componentes Shadcn con animaciones | **1º PREFERIDO** |
| **@react-bits** | `https://reactbits.dev/r/{name}.json` | Componentes interactivos/efectos | **2º PREFERIDO** |
| **@lucide-animated** | `https://lucide-animated.com/r/{name}.json` | Iconos animados (350+) | **PREFERIDO** |
| **@prompt-kit** | `https://prompt-kit.com/c/{name}.json` | Chat/Prompt UI | **PREFERIDO** para agents |
| **@shadcn** | Registry base | Componentes base estándar | Fallback |

### Configuracion MCP Server (Primera vez)

```bash
# En el directorio del proyecto
npx shadcn@latest mcp init --client claude

# Esto genera .mcp.json en la raiz del proyecto:
{
  "mcpServers": {
    "shadcn": {
      "command": "npx",
      "args": ["shadcn@latest", "mcp"]
    }
  }
}

# Reiniciar Claude Code y verificar con /mcp
```

### Configuracion de components.json

**OBLIGATORIO**: Agregar registries externos al `components.json`:

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "new-york",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "",
    "css": "src/app/globals.css",
    "baseColor": "zinc",
    "cssVariables": true,
    "prefix": ""
  },
  "iconLibrary": "lucide",
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui",
    "lib": "@/lib",
    "hooks": "@/hooks"
  },
  "registries": {
    "@animate-ui": "https://animate-ui.com/r/{name}.json",
    "@react-bits": "https://reactbits.dev/r/{name}.json",
    "@lucide-animated": "https://lucide-animated.com/r/{name}.json",
    "@prompt-kit": "https://prompt-kit.com/c/{name}.json"
  }
}
```

### Comandos de Instalacion

```bash
# 1º Animate UI (componentes Shadcn con animaciones - PREFERIDO)
bunx --bun shadcn@latest add @animate-ui/sliding-number
bunx --bun shadcn@latest add @animate-ui/morphing-text
bunx --bun shadcn@latest add @animate-ui/animated-card
bunx --bun shadcn@latest add @animate-ui/progress-reveal

# 2º React Bits (efectos interactivos)
bunx --bun shadcn@latest add @react-bits/fade-content
bunx --bun shadcn@latest add @react-bits/magnet
bunx --bun shadcn@latest add @react-bits/dock

# 3º Iconos animados lucide-animated
bunx --bun shadcn@latest add @lucide-animated/check-circle
bunx --bun shadcn@latest add @lucide-animated/loader
bunx --bun shadcn@latest add @lucide-animated/play

# 4º prompt-kit (chat/agent UI)
bunx --bun shadcn@latest add @prompt-kit/prompt-input
bunx --bun shadcn@latest add @prompt-kit/response-stream

# 5º Shadcn base (solo si no hay alternativa animada)
bunx --bun shadcn@latest add button card dialog
```

### Uso con Claude Code MCP

Despues de configurar el MCP, usar prompts naturales:

```
# React Bits
"Show me all available backgrounds from @react-bits"
"Add the Dither background from React Bits to the page, make it purple"
"Add FadeContent from @react-bits for scroll animations"

# lucide-animated
"Show me all available icons from @lucide-animated"
"Add the check-circle animated icon from lucide-animated"

# Combinados
"Create a hero section with FadeContent animation and animated icons"
```

### Componentes React Bits Recomendados

| Componente | Categoria | Uso |
|-----------|-----------|-----|
| `fade-content` | Animations | Fade in/out con scroll |
| `text-pressure` | Text Effects | Texto con efecto presion |
| `magnet` | Interactions | Efecto magnetico cursor |
| `dock` | Components | Dock estilo macOS |
| `tilted-card` | Components | Cards con tilt 3D |
| `spotlight-card` | Components | Cards con spotlight |
| `dither` | Backgrounds | Fondo con efecto dither |
| `hyperspeed` | Backgrounds | Efecto velocidad |

### Iconos lucide-animated Recomendados

| Icono | Uso |
|-------|-----|
| `check-circle` | Confirmacion, exito |
| `x-circle` | Error, cerrar |
| `loader` | Loading states |
| `play` / `pause` | Media controls |
| `arrow-up` / `arrow-down` | Navegacion |
| `settings` | Configuracion |
| `bell` | Notificaciones |

### Patrones de Importacion

```typescript
// CORRECTO - Componentes React Bits
import { FadeContent } from '@/components/ui/fade-content';
import { TextPressure } from '@/components/ui/text-pressure';
import { Dock } from '@/components/ui/dock';

// CORRECTO - Iconos animados lucide-animated
import { CheckCircle } from '@/components/icons/check-circle';
import { Loader } from '@/components/icons/loader';

// CORRECTO - Componentes base Shadcn
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';

// CORRECTO - Iconos estaticos (fallback)
import { Settings } from 'lucide-react';

// INCORRECTO - Importar directo desde node_modules
import { FadeContent } from 'react-bits';
```

### Estructura de Carpetas

```
components/
├── ui/                      # Componentes UI (Shadcn + React Bits)
│   ├── button.tsx
│   ├── card.tsx
│   ├── fade-content.tsx     # React Bits
│   ├── text-pressure.tsx    # React Bits
│   ├── dock.tsx             # React Bits
│   └── index.ts             # Barrel export
├── icons/                   # Iconos animados (lucide-animated)
│   ├── check-circle.tsx
│   ├── loader.tsx
│   ├── play.tsx
│   └── index.ts             # Barrel export
└── agent/                   # Componentes de dominio
    └── ...
```

### Ejemplo Completo de Uso

```typescript
// components/agent/MessageItem.tsx
import { FadeContent } from '@/components/ui/fade-content';
import { Card } from '@/components/ui/card';
import { CheckCircle } from '@/components/icons/check-circle';
import { Loader } from '@/components/icons/loader';
import type { IMessageItemProps } from './MessageItem.types';

export function MessageItem({ message, isLoading }: IMessageItemProps) {
  return (
    <FadeContent direction="up" duration={0.4}>
      <Card className="p-4">
        <div className="flex items-center gap-2">
          {isLoading ? (
            <Loader className="w-5 h-5 animate-spin" />
          ) : (
            <CheckCircle className="w-5 h-5 text-green-500" />
          )}
          <span>{message.content}</span>
        </div>
      </Card>
    </FadeContent>
  );
}
```

### Debug MCP

```bash
# En Claude Code, usar /mcp para verificar conexion
/mcp

# Debe mostrar "shadcn" en la lista de servers activos
# Si hay problemas, reiniciar Claude Code
```

### Referencias

- **React Bits**: https://reactbits.dev/
- **lucide-animated**: https://lucide-animated.com/
- **Shadcn MCP**: https://ui.shadcn.com/docs/mcp
- **Shadcn Registry**: https://ui.shadcn.com/

---

## REGLA 14: Package UI Compartido

### Estructura del Package UI

El monorepo tiene un package UI compartido en `core/packages/ui/` para componentes reutilizables:

```
core/packages/ui/
├── src/
│   ├── components/
│   │   ├── ui/              # Componentes Shadcn + React Bits
│   │   ├── icons/           # Iconos lucide-animated
│   │   └── agent/           # Componentes de dominio
│   ├── lib/
│   │   └── utils.ts         # cn() y utilidades
│   ├── hooks/               # Hooks compartidos
│   └── index.ts             # Barrel export
├── components.json          # Config Shadcn con registries
├── package.json
├── rolldown.config.ts
└── tsconfig.json
```

### Uso del Package UI

```typescript
// Importar desde el package compartido
import { Button, Card, FadeContent } from 'mks-dev-environment/ui';
import { CheckCircle, Loader } from 'mks-dev-environment/ui/icons';
import { cn } from 'mks-dev-environment/ui/lib/utils';
```

### Instalacion de Componentes en Package UI

```bash
# Ir al directorio del package UI
cd core/packages/ui

# Instalar componentes (se guardan en src/components/ui/)
bunx --bun shadcn@latest add @react-bits/fade-content
bunx --bun shadcn@latest add @lucide-animated/check-circle
bunx --bun shadcn@latest add button card
```

### Referencias

- **Shadcn/UI Documentation**: https://ui.shadcn.com/
- **Shadcn MCP Registry**: https://ui.shadcn.com/docs/mcp
- **Animate UI Gallery**: https://animate.ui/
- **Radix UI Primitives**: https://www.radix-ui.com/
- **CLI Documentation**: https://ui.shadcn.com/docs/cli

---

## REGLA 15: Testing - Vitest (NO bun test)

### Runner Correcto

**OBLIGATORIO**: Usar `vitest` o `bunx vitest` para ejecutar tests. NUNCA `bun test`.

```bash
# CORRECTO - Vitest runner
vitest                           # Modo watch
vitest run                       # Single run
bunx vitest run                  # Con bunx
bunx vitest run src/hooks/       # Tests específicos

# INCORRECTO - Bun test runner
bun test                         # NO USAR
bun test src/                    # NO USAR
```

### Configuración Base

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/tests/setupTests.ts'],
    globals: true,
  },
});
```

### Setup con MSW

```typescript
// src/tests/setupTests.ts
import '@testing-library/jest-dom';
import { beforeAll, afterEach, afterAll } from 'vitest';
import { server } from './mocks/server';

beforeAll(() => server.listen());
afterEach(() => {
  server.resetHandlers();
  localStorage.clear();
});
afterAll(() => server.close());
```

### Documentación Completa

Ver documentación detallada en:
- `~/dotfiles/mks-ui/docs/testing-architecture.md`
- `~/dotfiles/mks-ui/docs/testing-strategy.md`

---

## REGLA 16: Sistema de Themes - CSS Variables + Theme Manager

### Stack de Theming

**OBLIGATORIO**: Usar sistema de CSS variables con tokens apropiados.

| Package | Uso | Instalación |
|---------|-----|-------------|
| **@mks2508/theme-manager-react** | Theme switching con animaciones | `bun add @mks2508/theme-manager-react` |
| **@mks2508/shadcn-basecoat-theme-manager** | Core de gestión de temas | `bun add @mks2508/shadcn-basecoat-theme-manager` |

### Variables CSS Requeridas

```css
:root {
  /* Colores base */
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --primary: 222.2 47.4% 11.2%;
  --primary-foreground: 210 40% 98%;
  --secondary: 210 40% 96%;
  --secondary-foreground: 222.2 84% 4.9%;
  --muted: 210 40% 96%;
  --muted-foreground: 215.4 16.3% 46.9%;
  --accent: 210 40% 96%;
  --accent-foreground: 222.2 84% 4.9%;
  --destructive: 0 84.2% 60.2%;
  --destructive-foreground: 210 40% 98%;

  /* UI Elements */
  --card: var(--background);
  --card-foreground: var(--foreground);
  --popover: var(--background);
  --popover-foreground: var(--foreground);
  --border: 214.3 31.8% 91.4%;
  --input: 214.3 31.8% 91.4%;
  --ring: 222.2 84% 4.9%;
  --radius: 0.5rem;
}

.dark {
  --background: 222.2 84% 4.9%;
  --foreground: 210 40% 98%;
  /* ... dark variants */
}
```

### Uso con Next.js

```tsx
// app/layout.tsx
import { ThemeProvider } from '@mks2508/theme-manager-react/nextjs'

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        <ThemeProvider
          registryUrl="/themes/registry.json"
          defaultTheme="default"
          defaultMode="auto"
          enableTransitions={true}
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  )
}
```

### Componentes de Theme

```tsx
import {
  ModeToggle,           // Toggle light/dark
  AnimatedThemeToggler, // Toggle con animaciones
  ThemeSelector         // Selector completo de temas
} from '@mks2508/theme-manager-react/nextjs'
```

---

## REGLA 17: Sidebar y Bottom Navigation - sidebar-headless

### Package Oficial

**OBLIGATORIO**: Usar `@mks2508/sidebar-headless` para sidebars y bottom navigation.

```bash
bun add @mks2508/sidebar-headless
```

### Características

- Headless sidebar y mobile bottom navigation
- Animaciones fluidas
- Keyboard navigation completa
- WAI-ARIA accessibility
- Soporte glassmorphism
- Mobile-first design

### Ejemplo de Uso

```tsx
import {
  Sidebar,
  SidebarItem,
  BottomNavigation
} from '@mks2508/sidebar-headless';

export function AppLayout({ children }) {
  return (
    <div className="flex">
      {/* Desktop Sidebar */}
      <Sidebar className="hidden md:flex">
        <SidebarItem icon={<Home />} label="Home" href="/" />
        <SidebarItem icon={<Settings />} label="Settings" href="/settings" />
      </Sidebar>

      {/* Mobile Bottom Nav */}
      <BottomNavigation className="md:hidden">
        <SidebarItem icon={<Home />} label="Home" href="/" />
        <SidebarItem icon={<Settings />} label="Settings" href="/settings" />
      </BottomNavigation>

      <main>{children}</main>
    </div>
  );
}
```

---

## REGLA 18: Glassmorphism - Guía de Implementación

### Principios Fundamentales

Glassmorphism es la combinación controlada de:
- **Transparencia parcial** (RGBA / alpha 10-30%)
- **Backdrop blur** (difuminar lo que hay detrás)
- **Bordes sutiles** (simular refracción)
- **Sombras suaves** (profundidad)
- **isolation: isolate** (stacking context)

### Receta Base (Tailwind)

```html
<div class="
  isolate
  rounded-xl
  bg-white/20
  backdrop-blur-lg
  border border-white/30
  shadow-xl shadow-black/10
">
</div>
```

### Clases Glassmorphism Disponibles

```css
/* Paneles principales */
.glass-panel          /* blur-16px, borde primary */
.glass-panel-subtle   /* blur-8px, más transparente */
.glass-panel-heavy    /* blur-24px, más opaco */

/* Cards de producto */
.product-card-glass          /* blur-12px con hover */
.product-card-glass-enhanced /* blur-16px con glow */

/* Badges */
.badge-glass-featured  /* Primary con glow */
.badge-glass-subtle    /* Sutil, borde transparente */
.badge-glass-outline   /* Solo borde */

/* Inputs y formularios */
.input-glass           /* Blur sutil con focus glow */

/* Headers */
.bg-glass-header       /* Desktop header */
.bg-glass-header-mobile /* Mobile header más transparente */
```

### Reglas de Uso

| Usar en | Evitar en |
|---------|-----------|
| Headers flotantes | Tablas densas |
| Modales | Formularios largos |
| Sidebars | Texto extenso |
| Cards destacadas | Listas largas |

### Performance

```css
/* Fallback obligatorio */
@supports not (backdrop-filter: blur(1px)) {
  .glass-panel { background: rgba(255,255,255,0.9); }
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  .glass-panel { transition: none; }
}
```

### Documentación Completa

- `~/dotfiles/mks-ui/docs/glassmorphism-guide.md` - Guía teórica
- `~/dotfiles/mks-ui/docs/glassmorphism.css` - Implementación CSS completa

---

## Fuentes de Referencia

- **CLAUDE.md** - Guia de arquitectura del monorepo
- **@mks2508/better-logger** - Documentacion del logger
- **@mks2508/no-throw** - Documentacion del Result pattern
- **@mks2508/theme-manager-react** - Sistema de themes
- **@mks2508/sidebar-headless** - Sidebar y bottom navigation
- **Arktype** - https://arktype.io/
- **Rolldown** - https://rollup.rs/
- **Oxlint** - https://oxlint.com/
- **Zustand** - https://zustand-demo.pmnd.rs/
- **Shadcn/UI** - https://ui.shadcn.com/
- **Shadcn MCP** - https://ui.shadcn.com/docs/mcp
- **React Bits** - https://reactbits.dev/
- **lucide-animated** - https://lucide-animated.com/

### Documentación en Dotfiles

| Documento | Ubicación | Contenido |
|-----------|-----------|-----------|
| **Glassmorphism Guide** | `~/dotfiles/mks-ui/docs/glassmorphism-guide.md` | Teoría y best practices |
| **Glassmorphism CSS** | `~/dotfiles/mks-ui/docs/glassmorphism.css` | Implementación completa |
| **Testing Architecture** | `~/dotfiles/mks-ui/docs/testing-architecture.md` | Arquitectura de tests |
| **Testing Strategy** | `~/dotfiles/mks-ui/docs/testing-strategy.md` | Estrategia de testing |

### CLI mks-ui

Generador de componentes disponible globalmente:

```bash
mks-ui component Button --ui       # Componente UI simple
mks-ui component ProductCard --complex  # BLO completo
mks-ui service ProductService      # Servicio Elysia
mks-ui hook useProducts            # Custom hook
mks-ui type Product                # Tipos TypeScript
```
