# Current Problem Analysis

**Date:** 2026-03-03
**Session:** 59660C75-71BB-4795-9077-003F467EA8A4

## Summary

**BINARY DESACTUALIZADO** - El ejecutable del CLI no contiene los últimos cambios del código fuente.

## Evidencia de desincronización

| Item | Timestamp | Valor |
|------|-----------|-------|
| Binary compilado | Mar 3 | **16:33** |
| Último commit (a01d2cc) | Mar 3 | **16:43** |
| TransmuxingService.swift modificado | Mar 3 | **16:43** |

**El binary se compiló 10 minutos ANTES del último commit.**

## Lo que el log muestra (código OLD)

```
[17:21:30.580] [INF] [Service] Truncated output to init segment size (7062004 bytes)
[17:21:31.108] [INF] [Service] Seeked input back to beginning
[17:21:31.108] [INF] [Service] Reset lastWrittenDts to start fresh from beginning
[17:21:31.108] [INF] [Service] AC3 init phase reset complete, ready to remux from beginning
```

## Lo que el código fuente dice (código NEW)

```swift
// AC3 init phase produced moov + first fragments. Continue from here.
// DO NOT truncate or rewind -- the muxer's internal DTS state can't be reset.
TransmuxLog.service("AC3 init phase complete, continuing from current position (no truncate/rewind)")
```

**El log muestra mensajes del código antiguo que YA NO EXISTEN en el fuente.**

## Problema original (ya "arreglado" en fuente pero no en binary)

El código OLD hacía:
1. Escribir 230 packets para generar moov (AC3 init phase)
2. **Truncar** el output a 7MB
3. **Seek** del input al principio
4. **Reset** lastWrittenDts
5. Continuar remuxing desde DTS=0

Esto causaba `write_frame ERROR (-22)` porque:
- El muxer fMP4 tiene estado interno
- Al truncar el archivo debajo del muxer, el estado queda inconsistente
- `av_interleaved_write_frame` devuelve EINVAL

El código NEW (commit a01d2cc) elimina el truncate/rewind:
- Continúa desde la posición actual después del init phase
- El init segment incluye moov + primeros fragments
- El scanner del segmenter salta el initSegmentSize

## Acción requerida

```bash
cd /Volumes/KODAK1TB/MKS-IPTV-App/TransmuxCore
swift build --product transmux-cli
```

**Recompilar el CLI para incluir los cambios del commit a01d2cc.**

## Posibles causas de la desincronización

1. **Xcode cache**: Si se compiló desde Xcode en lugar de `swift build`, puede haber caches antiguos
2. **Build incremental fallido**: SwiftPM puede no detectar cambios en algunos casos
3. **Compilación manual**: Se compiló a las 16:33, se hizo commit a las 16:43 sin recompilar

## Limpieza recomendada (si persiste)

```bash
cd /Volumes/KODAK1TB/MKS-IPTV-App/TransmuxCore
rm -rf .build
swift build --product transmux-cli
```

## Estado del problema

- [x] Identificado: Binary desactualizado
- [ ] Acción: Recompilar CLI
- [ ] Verificar: Ejecutar de nuevo y comprobar que el log muestra "continuing from current position (no truncate/rewind)"

---

## Notas adicionales

El commit a01d2cc también cambió:
- Per-stream rebase offsets (en vez de global offset)
- Audio buffering hasta que globalOffsetComputed=true
- MINIMUM DTS en vez de average para el offset

Estos cambios también están ausentes del binary actual.
