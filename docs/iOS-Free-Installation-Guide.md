# Guía de Instalación Gratuita en iOS

Esta guía explica cómo instalar tu app IPTV en dispositivos iOS de forma gratuita, minimizando la necesidad de reinstalación.

## Tabla de Comparación

| Método | Duración | Renovación | Límite Apps | Requisitos |
|--------|----------|------------|-------------|------------|
| AltStore | 7 días | Automática (WiFi) | 3 apps | Mac + WiFi |
| Sideloadly | 7 días | Manual | Sin límite | Mac/Windows |
| TrollStore | Permanente | No necesaria | Sin límite | iOS 14.0-16.6.1 |
| Xcode | 7 días | Manual | 3 apps | Mac + Cable |

## Método 1: AltStore (Recomendado)

### Ventajas
- Renovación automática sin cables
- Interfaz amigable
- Soporte activo

### Requisitos
- Mac con macOS 10.14.4+
- iPhone/iPad con iOS 12.2+
- Apple ID gratuito
- Misma red WiFi

### Paso 1: Preparar el IPA

```bash
# Crear archive para iOS
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
           -scheme mks-multiplatform-iptv \
           -sdk iphoneos \
           -configuration Release \
           -archivePath ./build/ios/mks-iptv.xcarchive \
           archive

# Crear ExportOptions-iOS.plist
cat > ./build/ios/ExportOptions-iOS.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>QL3NVUPD27</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

# Exportar IPA
xcodebuild -exportArchive \
           -archivePath ./build/ios/mks-iptv.xcarchive \
           -exportPath ./build/ios/export \
           -exportOptionsPlist ./build/ios/ExportOptions-iOS.plist
```

### Paso 2: Instalar AltServer

1. Descarga AltServer desde [altstore.io](https://altstore.io)
2. Instala AltServer en tu Mac
3. Abre AltServer (aparecerá en la barra de menú)
4. Ve a AltServer → Preferences
5. Habilita "Enable JIT compilation"

### Paso 3: Instalar AltStore en iPhone

1. Conecta tu iPhone por cable USB
2. Confía en el ordenador si es necesario
3. En Mac: AltServer → Install AltStore → [Tu iPhone]
4. Ingresa tu Apple ID y contraseña
5. En iPhone: Ajustes → General → VPN y gestión de dispositivos
6. Confía en tu Apple ID
7. Abre AltStore en tu iPhone

### Paso 4: Habilitar Renovación Automática

1. En iPhone: Ajustes → AltStore
2. Activa "Background App Refresh"
3. En Mac: AltServer debe estar ejecutándose
4. Ambos dispositivos en la misma red WiFi

### Paso 5: Instalar tu App

1. Copia el archivo .ipa a tu iPhone:
   - AirDrop
   - iCloud Drive
   - Correo electrónico
2. En iPhone: Abre el .ipa con AltStore
3. Toca "Install"
4. La app se instalará y aparecerá en la pantalla de inicio

## Método 2: Sideloadly

### Instalación Rápida

1. Descarga [Sideloadly](https://sideloadly.io)
2. Conecta tu iPhone
3. Arrastra el .ipa a Sideloadly
4. Ingresa tu Apple ID
5. Haz clic en "Start"
6. Confía en el certificado en Ajustes

### Renovación (cada 7 días)
- Conecta el iPhone
- Abre Sideloadly
- Reinstala la app

## Método 3: TrollStore (iOS 14.0-16.6.1)

### ⚠️ Verificar Compatibilidad

| iOS Version | Compatibilidad |
|-------------|----------------|
| 14.0-14.8.1 | ✅ Completa |
| 15.0-15.4.1 | ✅ Completa |
| 15.5-15.6.1 | ⚠️ Limitada |
| 15.7-15.7.1 | ❌ No compatible |
| 16.0-16.1.2 | ✅ Completa |
| 16.2-16.6.1 | ⚠️ Requiere MacDirtyCow |
| 16.7+ | ❌ No compatible |

### Instalación

1. Visita [TrollStore GitHub](https://github.com/opa334/TrollStore)
2. Sigue las instrucciones específicas para tu versión
3. Una vez instalado TrollStore:
   - Abre TrollStore
   - Toca "+"
   - Selecciona tu .ipa
   - Instalación permanente

## Método 4: Xcode Directo

### Proceso Básico

```bash
# 1. Conecta tu iPhone
# 2. Abre Xcode
# 3. Selecciona tu dispositivo como destino
# 4. Build and Run (Cmd+R)
```

### Renovación Manual
- Cada 7 días
- Requiere cable y Xcode

## Automatización con Shortcuts

### Crear Recordatorio Automático

1. Abre Shortcuts en iPhone
2. Crea nuevo atajo:
   ```
   - Add "Get Current Date"
   - Add "Add 6 Days"
   - Add "Create Reminder"
     - Title: "Renovar Apps Sideloaded"
     - Alert: Resultado de "Add 6 Days"
   ```
3. Ejecuta después de cada instalación

## Solución de Problemas

### "Unable to verify app"
1. Ajustes → General → VPN y gestión de dispositivos
2. Confía en el desarrollador
3. Si persiste, revoca certificados en appleid.apple.com

### "Maximum apps reached"
- Con Apple ID gratuito: máximo 3 apps
- Elimina apps no usadas en Xcode → Window → Devices

### AltStore no renueva automáticamente
1. Verifica que AltServer esté ejecutándose
2. Ambos dispositivos en la misma red
3. Background App Refresh activado
4. Reinstala AltStore si es necesario

### "Device not supported"
- Verifica la versión de iOS
- Actualiza Xcode/AltStore/Sideloadly

## Consejos Pro

1. **Backup del IPA**: Guarda siempre una copia del .ipa
2. **Apple ID secundario**: Usa un Apple ID dedicado para sideloading
3. **Notificaciones**: Activa notificaciones en AltStore
4. **WiFi Sync**: Habilita sincronización WiFi en iTunes/Finder

## Scripts Útiles

### Crear IPA rápidamente
```bash
#!/bin/bash
# save as: build-ios-ipa.sh

echo "Building iOS IPA..."
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
           -scheme mks-multiplatform-iptv \
           -sdk iphoneos \
           -configuration Release \
           clean archive \
           -archivePath ./build/ios/mks-iptv.xcarchive

xcodebuild -exportArchive \
           -archivePath ./build/ios/mks-iptv.xcarchive \
           -exportPath ./build/ios/ \
           -exportOptionsPlist ./ExportOptions-iOS.plist

echo "IPA created at: ./build/ios/"
```

### Verificar firma del IPA
```bash
unzip -q yourapp.ipa
codesign -dv Payload/*.app
```

## Enlaces Útiles

- [AltStore](https://altstore.io) - Sitio oficial
- [Sideloadly](https://sideloadly.io) - Descarga directa
- [TrollStore Releases](https://github.com/opa334/TrollStore/releases)
- [iOS Sideloading Guide](https://ios.cfw.guide/sideloading)

## Notas Finales

- **Seguridad**: Solo instala apps de fuentes confiables
- **Actualizaciones**: Las apps sideloaded no se actualizan automáticamente
- **Datos**: Los datos se mantienen al renovar (excepto si desinstalas)
- **Notificaciones**: Funcionan normalmente en apps sideloaded