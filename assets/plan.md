# Whiteboard — Plan de desarrollo

## 1. Visión

Construir una aplicación de pizarra digital nativa, **local-first**, portable y sin dependencia obligatoria de una cuenta o servicio cloud.

El usuario debe ser dueño de sus pizarras y poder decidir dónde almacenarlas:

- almacenamiento local;
- carpeta elegida por el usuario;
- Google Drive;
- OneDrive;
- Dropbox;
- WebDAV;
- S3-compatible;
- servidor propio;
- cualquier proveedor compatible que se incorpore posteriormente.

La nube será una capacidad opcional, no un requisito para utilizar la aplicación.

### Principio central

> **La pizarra pertenece al usuario, no al servicio.**

---

## 2. Objetivos

### MVP

- Crear múltiples pizarras.
- Canvas infinito.
- Pan y zoom.
- Selección y transformación de objetos.
- Lápiz/freehand.
- Borrador.
- Líneas y formas básicas.
- Texto.
- Sticky notes.
- Imágenes.
- Copiar/pegar.
- Undo/redo.
- Autosave.
- Persistencia local.
- Importación/exportación.
- Exportación PNG, SVG y PDF.
- Formato `.whiteboard`.
- Funcionamiento completamente offline.
- Recuperación ante cierre inesperado.

### Después del MVP

- Sincronización cloud.
- Multi-dispositivo.
- Compartir pizarras.
- Colaboración en tiempo real.
- Historial/versionado.
- Comentarios.
- Plantillas.
- Atajos configurables.
- Presentación.
- Plugins/extensiones.

---

## 3. Principios de arquitectura

### Local-first

La aplicación debe funcionar correctamente sin conexión.

Toda operación del usuario se aplica primero al estado local:

```text
User action
    ↓
In-memory state
    ↓
Local persistence
    ↓
Optional synchronization
```

Nunca:

```text
User action
    ↓
Cloud
    ↓
Application
```

La ausencia de Internet no debe bloquear la edición.

### Offline-first

La aplicación debe poder:

- abrir pizarras sin Internet;
- editar sin Internet;
- guardar sin Internet;
- exportar sin Internet.

La sincronización ocurre posteriormente.

### User-owned data

El formato de datos debe evitar un lock-in propietario.

El usuario debe poder exportar toda su información sin depender de nuestra infraestructura.

---

# 4. Stack inicial

## Cliente

### Flutter

Target inicial:

- Windows
- Linux
- macOS

Posteriormente:

- Android
- iOS

Flutter permite compartir el núcleo de la aplicación y mantener una experiencia consistente entre plataformas.

## Persistencia local

Evaluar:

- SQLite;
- archivos `.whiteboard`;
- almacenamiento de assets separado.

Recomendación inicial:

```text
SQLite
    ↓
estado/document metadata
    ↓
filesystem
    ↓
assets pesados
```

No almacenar imágenes grandes directamente como blobs si no existe una razón concreta para hacerlo.

## Estado

Separar:

```text
UI state
Document state
Persistence state
Sync state
```

No mezclar la lógica del canvas con la persistencia.

---

# 5. Arquitectura propuesta

```text
whiteboard/
├── apps/
│   └── desktop/
│
├── packages/
│   ├── core/
│   │   ├── domain/
│   │   ├── document/
│   │   ├── geometry/
│   │   ├── history/
│   │   └── commands/
│   │
│   ├── canvas/
│   │   ├── rendering/
│   │   ├── interaction/
│   │   ├── selection/
│   │   └── tools/
│   │
│   ├── persistence/
│   │   ├── local/
│   │   ├── filesystem/
│   │   └── format/
│   │
│   ├── sync/
│   │   ├── engine/
│   │   ├── conflicts/
│   │   └── providers/
│   │
│   └── export/
│       ├── png/
│       ├── svg/
│       └── pdf/
│
└── tests/
```

La estructura final puede cambiar después de validar el dominio.

---

# 6. Modelo de documento

Una pizarra debe tratarse como un documento compuesto por objetos.

Conceptualmente:

```text
Board
├── metadata
├── viewport
├── pages
│   └── Page
│       └── objects
│           ├── Stroke
│           ├── Shape
│           ├── Text
│           ├── StickyNote
│           ├── Image
│           └── Group
└── assets
```

Cada objeto debe tener un identificador estable:

```text
objectId
```

Nunca utilizar la posición dentro de un array como identidad.

---

# 7. Formato `.whiteboard`

El formato debe ser portable y versionado.

Propuesta:

```text
example.whiteboard
```

Internamente:

```text
document.json
assets/
history/
metadata.json
```

Debe incluir una versión de esquema:

```json
{
  "schemaVersion": 1,
  "boardId": "...",
  "createdAt": "...",
  "updatedAt": "...",
  "objects": []
}
```

El formato debe permitir migraciones futuras:

```text
schema v1
   ↓ migration
schema v2
   ↓ migration
schema v3
```

Nunca romper archivos antiguos sin un proceso de migración.

---

# 8. Motor de comandos

Las modificaciones del documento deben pasar por comandos.

Ejemplos:

```text
CreateObject
DeleteObject
MoveObject
ResizeObject
RotateObject
UpdateText
ChangeStyle
GroupObjects
UngroupObjects
```

Esto permitirá construir posteriormente:

- undo/redo;
- historial;
- colaboración;
- sincronización;
- auditoría.

Ejemplo conceptual:

```text
Command
   ↓
Document
   ↓
Change
   ↓
Persistence
```

---

# 9. Undo / Redo

No implementar undo/redo únicamente guardando snapshots completos.

Inicialmente:

```text
Command history
    ↓
Undo
    ↓
Reverse command
```

Evaluar snapshots periódicos para recuperación rápida.

Objetivo:

- undo rápido;
- redo rápido;
- memoria controlada;
- recuperación después de crash.

---

# 10. Canvas

## Navegación

- zoom;
- pan;
- fit to content;
- centrar selección;
- zoom al cursor.

## Herramientas iniciales

1. Selección
2. Mano/pan
3. Lápiz
4. Borrador
5. Línea
6. Rectángulo
7. Círculo
8. Flecha
9. Texto
10. Sticky note
11. Imagen

## Selección

Debe soportar:

- selección individual;
- selección múltiple;
- drag;
- resize;
- rotate;
- duplicar;
- eliminar;
- copiar/pegar.

---

# 11. Rendering

El canvas debe diseñarse pensando en grandes cantidades de objetos.

Evitar reconstruir innecesariamente toda la escena.

Investigar:

- retained rendering;
- scene graph;
- dirty regions;
- caching;
- rasterización selectiva.

Objetivo:

> 60 FPS en uso normal incluso con pizarras grandes.

No optimizar prematuramente, pero diseñar el dominio sin acoplarlo al renderer.

---

# 12. Almacenamiento local

La aplicación debe mantener una copia local fiable.

Propuesta:

```text
Board
  ↓
Document state
  ↓
Local database
  ↓
Asset storage
```

Autosave:

- después de cambios relevantes;
- con debounce;
- flush inmediato en eventos críticos;
- recuperación automática después de crash.

Debe existir un mecanismo de recuperación:

```text
board
board.recovery
```

si el último guardado quedó incompleto.

---

# 13. Assets

Las imágenes y otros archivos binarios deben almacenarse por separado.

Ejemplo:

```text
board/
├── document.json
└── assets/
    ├── a1.png
    ├── a2.jpg
    └── a3.webp
```

El documento solo mantiene referencias:

```json
{
  "assetId": "a1",
  "type": "image"
}
```

---

# 14. Exportación

MVP:

```text
PNG
SVG
PDF
```

Además:

```text
.whiteboard
JSON
```

El usuario debe poder exportar la pizarra completa sin depender de Internet.

---

# 15. Cloud

No construir un cloud propietario inicialmente.

Primero abstraer almacenamiento:

```text
StorageProvider
```

Implementaciones:

```text
LocalStorageProvider
FileSystemProvider
GoogleDriveProvider
OneDriveProvider
DropboxProvider
WebDavProvider
S3Provider
```

La aplicación debe depender de la interfaz, no del proveedor.

---

# 16. Sincronización

La sincronización debe ser independiente del almacenamiento.

```text
Document
   ↓
Change tracking
   ↓
Sync engine
   ↓
Storage provider
```

Cada cambio debería tener:

```text
changeId
objectId
timestamp
deviceId
operation
payload
```

Esto permitirá evolucionar posteriormente hacia sincronización incremental.

---

# 17. Conflictos

No asumir que "última escritura gana" será suficiente.

Escenarios:

```text
PC
 ├── modifica objeto A
 │
 └── offline

Laptop
 ├── modifica objeto B
 │
 └── offline

        ↓

       Sync
        ↓

Merge
```

Como los objetos tienen IDs independientes, muchos cambios podrán fusionarse sin conflicto.

Los conflictos reales deben detectarse explícitamente.

---

# 18. Seguridad

Principios:

- los datos locales pertenecen al usuario;
- no enviar contenido a servidores sin autorización;
- credenciales cloud almacenadas mediante mecanismos seguros del sistema operativo;
- HTTPS obligatorio para servicios remotos;
- mínimo privilegio;
- no almacenar tokens en texto plano.

Para proveedores cloud, utilizar OAuth cuando esté disponible.

---

# 19. UX

La interfaz debe ser simple.

Inspiración funcional:

```text
┌─────────────────────────────────────────┐
│  File     Edit     View                 │
│                                         │
│            Canvas                       │
│                                         │
│                                         │
│                                         │
│     ┌─────────────────────────────┐     │
│     │  Select  Pen  Shape  Text   │     │
│     └─────────────────────────────┘     │
└─────────────────────────────────────────┘
```

No llenar la pantalla de controles.

Las herramientas avanzadas deben aparecer contextualmente.

---

# 20. Atajos

MVP:

```text
Ctrl + Z       Undo
Ctrl + Shift Z Redo
Ctrl + C       Copy
Ctrl + V       Paste
Ctrl + X       Cut
Ctrl + A       Select all
Delete         Delete
Space + drag   Pan
Wheel          Zoom
```

Agregar atajos configurables posteriormente.

---

# 21. Testing

## Unit tests

Cubrir:

- geometría;
- comandos;
- serialización;
- deserialización;
- migraciones;
- undo/redo;
- conflictos;
- sincronización.

## Integration tests

- crear board;
- guardar;
- cerrar;
- abrir;
- recuperar;
- exportar;
- importar.

## Stress tests

Probar:

```text
1,000 objetos
10,000 objetos
100,000 objetos
```

y múltiples strokes grandes.

---

# 22. Fases

## Fase 0 — Investigación

- validar Flutter canvas;
- evaluar SQLite;
- evaluar formato de archivo;
- probar rendering;
- definir modelo de dominio.

**Resultado:** spike técnico funcional.

---

## Fase 1 — Core

Construir:

- Board;
- Page;
- Object;
- IDs;
- comandos;
- serialización;
- undo/redo.

**Resultado:** documento editable sin UI completa.

---

## Fase 2 — Canvas MVP

Implementar:

- pan;
- zoom;
- selección;
- lápiz;
- formas;
- texto;
- sticky notes;
- imágenes.

**Resultado:** primera pizarra usable.

---

## Fase 3 — Persistencia

Implementar:

- SQLite;
- filesystem;
- autosave;
- recuperación;
- `.whiteboard`;
- import/export.

**Resultado:** aplicación offline completa.

---

## Fase 4 — Exportación

Implementar:

- PNG;
- SVG;
- PDF.

**Resultado:** documentos utilizables fuera de la aplicación.

---

## Fase 5 — UX y estabilidad

- shortcuts;
- menú contextual;
- toolbar;
- preferencias;
- accesibilidad;
- crash recovery;
- performance.

**Resultado:** MVP distribuible.

---

## Fase 6 — Cloud providers

Implementar la abstracción:

```text
StorageProvider
```

Después:

1. WebDAV
2. S3-compatible
3. Google Drive
4. OneDrive
5. Dropbox

El orden puede cambiar según demanda.

---

## Fase 7 — Sync

- change log;
- device IDs;
- sync queue;
- retry;
- conflictos;
- merge;
- offline queue.

---

## Fase 8 — Colaboración

Solo después de tener sincronización sólida:

- compartir;
- permisos;
- presencia;
- edición simultánea;
- cursores;
- resolución de conflictos.

---

# 23. Fuera del MVP

No construir inicialmente:

- cuentas;
- servidor propio;
- sistema de suscripciones;
- colaboración;
- chat;
- IA;
- plantillas complejas;
- marketplace;
- administración empresarial;
- analytics invasivo.

Primero debe existir una **excelente aplicación local**.

---

# 24. Roadmap técnico resumido

```text
                    ┌─────────────┐
                    │ Investigación│
                    └──────┬──────┘
                           ↓
                    ┌─────────────┐
                    │ Core Domain │
                    └──────┬──────┘
                           ↓
                    ┌─────────────┐
                    │ Canvas MVP  │
                    └──────┬──────┘
                           ↓
                    ┌─────────────┐
                    │ Local First │
                    └──────┬──────┘
                           ↓
                    ┌─────────────┐
                    │  Export     │
                    └──────┬──────┘
                           ↓
                    ┌─────────────┐
                    │   MVP       │
                    └──────┬──────┘
                           ↓
              ┌────────────┴────────────┐
              ↓                         ↓
       Cloud Providers              Local-only
              ↓
       Sync Engine
              ↓
       Collaboration
```

---

# 25. Primera milestone

## `v0.1 — Local Canvas`

Objetivo:

> Abrir la aplicación, crear una pizarra, dibujar, colocar objetos, deshacer cambios, cerrar la aplicación y volver a encontrar exactamente el mismo estado.

### Definition of Done

- [ ] Aplicación Flutter ejecuta en Windows.
- [ ] Board creado correctamente.
- [ ] Canvas infinito.
- [ ] Pan.
- [ ] Zoom.
- [ ] Lápiz.
- [ ] Selección.
- [ ] Rectángulo.
- [ ] Círculo.
- [ ] Línea.
- [ ] Texto.
- [ ] Delete.
- [ ] Undo.
- [ ] Redo.
- [ ] Autosave.
- [ ] Reapertura del board.
- [ ] Serialización versionada.
- [ ] Tests del dominio.
- [ ] Sin conexión a Internet requerida.

---

# 26. Decisiones que deben permanecer abiertas

No fijar prematuramente:

- SQLite vs otro motor;
- renderer definitivo;
- estructura exacta del paquete `.whiteboard`;
- estrategia final de CRDT;
- proveedor cloud principal;
- backend propietario;
- modelo de monetización;
- colaboración en tiempo real.

Estas decisiones deben tomarse después de los spikes técnicos correspondientes.

---

# 27. Regla del proyecto

> **Local primero. Usuario primero. Formato portable primero. Cloud después.**

Si la aplicación funciona perfectamente sin nuestro servidor, entonces la arquitectura va por buen camino.
