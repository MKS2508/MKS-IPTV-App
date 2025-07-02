# Guía de Distribución con TestFlight

Esta guía describe el proceso completo para distribuir tu app IPTV mediante TestFlight.

## Requisitos Previos

### 1. Cuenta de Desarrollador de Apple
- **Costo**: $99 USD/año
- **Registro**: https://developer.apple.com/programs/
- **Tiempo de aprobación**: 24-48 horas típicamente

### 2. Certificados y Perfiles
- **Certificado de Distribución**: Apple Distribution Certificate
- **Provisioning Profile**: App Store Distribution Profile
- **App ID**: Debe coincidir con tu bundle identifier (`dev.mks2508.mks-multiplatform-iptv`)

### 3. App Store Connect
- Crear una nueva app en https://appstoreconnect.apple.com
- Configurar la información básica de la app

## Paso 1: Configurar App Store Connect

1. Accede a [App Store Connect](https://appstoreconnect.apple.com)
2. Haz clic en "My Apps" → "+"
3. Completa la información:
   ```
   - Platform: macOS
   - App Name: MKS Multiplatform IPTV
   - Primary Language: English
   - Bundle ID: dev.mks2508.mks-multiplatform-iptv
   - SKU: mks-iptv-mac (o cualquier identificador único)
   ```

## Paso 2: Crear el Archive para Distribución

El archive ya está creado. Si necesitas crear uno nuevo:

```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
           -scheme mks-multiplatform-iptv \
           -configuration Release \
           archive \
           -archivePath ./build/mks-iptv-appstore.xcarchive
```

## Paso 3: Crear ExportOptions para App Store

Crea un archivo `ExportOptionsAppStore.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>QL3NVUPD27</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>generateAppStoreInformation</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>provisioningProfiles</key>
    <dict>
        <key>dev.mks2508.mks-multiplatform-iptv</key>
        <string>automatic</string>
    </dict>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

## Paso 4: Exportar para App Store

```bash
xcodebuild -exportArchive \
           -archivePath ./build/mks-iptv.xcarchive \
           -exportPath ./build/appstore-export \
           -exportOptionsPlist ./ExportOptionsAppStore.plist
```

## Paso 5: Subir a App Store Connect

### Opción A: Usando xcrun altool (Línea de comandos)

```bash
xcrun altool --upload-app \
             -f "./build/appstore-export/mks-multiplatform-iptv.pkg" \
             -t macos \
             -u "tu-apple-id@email.com" \
             -p "app-specific-password"
```

### Opción B: Usando Transporter

1. Descarga [Transporter](https://apps.apple.com/app/transporter/id1450874784) desde la Mac App Store
2. Arrastra el archivo `.pkg` a Transporter
3. Inicia sesión con tu Apple ID
4. Haz clic en "Deliver"

### Opción C: Usando Xcode

1. Abre Xcode
2. Ve a Window → Organizer
3. Selecciona tu archive
4. Haz clic en "Distribute App"
5. Selecciona "App Store Connect"
6. Sigue el asistente

## Paso 6: Configurar TestFlight

Una vez subida la app (procesamiento ~5-30 minutos):

1. En App Store Connect, ve a tu app
2. Haz clic en "TestFlight"
3. Completa la información requerida:
   - **Información de cumplimiento de exportación**
   - **Información de prueba beta**
   - **Qué probar**

## Paso 7: Gestionar Testers

### Testers Internos (hasta 100)
- Miembros del equipo de App Store Connect
- Acceso inmediato sin revisión

### Testers Externos (hasta 10,000)
- Requiere revisión de Apple (24-48 horas)
- Crear grupos de prueba
- Enviar invitaciones por email

## Comandos Útiles

### Verificar la firma del archive
```bash
codesign -dv --verbose=4 ./build/mks-iptv.xcarchive/Products/Applications/mks-multiplatform-iptv.app
```

### Ver el contenido del archive
```bash
xcodebuild -exportArchive -archivePath ./build/mks-iptv.xcarchive -exportOptionsPlist ./ExportOptionsAppStore.plist -allowProvisioningUpdates
```

### Validar antes de subir
```bash
xcrun altool --validate-app \
             -f "./build/appstore-export/mks-multiplatform-iptv.pkg" \
             -t macos \
             -u "tu-apple-id@email.com" \
             -p "app-specific-password"
```

## Solución de Problemas

### Error: "No suitable signing identity found"
- Verifica que tienes un certificado de distribución válido
- Revisa Keychain Access para certificados expirados

### Error: "Invalid provisioning profile"
- Regenera el perfil en Apple Developer Portal
- Asegúrate de que incluye tu certificado de distribución

### Error: "Bundle identifier mismatch"
- Verifica que el bundle ID en Xcode coincide con App Store Connect
- Revisa Info.plist

### La app no aparece en TestFlight
- Espera el procesamiento (puede tardar hasta 1 hora)
- Verifica el estado en App Store Connect → Activity
- Revisa tu email por notificaciones de Apple

## Notas Importantes

1. **Primera vez**: La primera subida puede requerir configuración adicional
2. **Revisión**: La primera versión beta externa requiere revisión de Apple
3. **Actualizaciones**: Las actualizaciones posteriores son más rápidas
4. **Caducidad**: Las builds de TestFlight caducan después de 90 días
5. **Feedback**: TestFlight incluye herramientas de feedback integradas

## Enlaces Útiles

- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [Distributing Your App for Beta Testing](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Transporter User Guide](https://help.apple.com/itc/transporter/)