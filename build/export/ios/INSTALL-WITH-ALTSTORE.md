# Instalación con AltStore

El archivo IPA está listo para instalar: `mks-multiplatform-iptv.ipa`

## Pasos para instalar en tu iPhone con AltStore:

### 1. Transferir el IPA a tu iPhone

Elige una de estas opciones:

#### Opción A: AirDrop (Más rápido)
1. En tu Mac: Abre Finder
2. Navega a: `/Users/mks/Documents/GitHub/mks-multiplatform-iptv/build/ios/`
3. Haz clic derecho en `mks-multiplatform-iptv.ipa`
4. Selecciona "Compartir" → "AirDrop"
5. Selecciona tu iPhone

#### Opción B: iCloud Drive
1. Copia el archivo a iCloud Drive
2. En tu iPhone: Abre la app Archivos
3. Navega hasta el archivo IPA

#### Opción C: Correo/Mensajes
1. Envíate el archivo por email o iMessage
2. Ábrelo en tu iPhone

### 2. Instalar con AltStore

1. En tu iPhone: Cuando recibas el archivo IPA
2. Toca "Compartir" 
3. Selecciona "AltStore" (si no aparece, busca en "Más")
4. AltStore se abrirá automáticamente
5. Toca "Install"
6. Ingresa tu Apple ID si es necesario
7. Espera a que se complete la instalación

### 3. Confiar en el certificado (Primera vez)

1. Ve a: Ajustes → General → VPN y gestión de dispositivos
2. En "PERFILES DE DESARROLLADOR" verás tu Apple ID
3. Toca tu Apple ID
4. Toca "Confiar en [tu email]"
5. Confirma tocando "Confiar"

### 4. Abrir la app

La app aparecerá en tu pantalla de inicio como "mks-multiplatform-iptv"

## Renovación Automática

- AltStore renovará la app automáticamente cada 7 días
- Requisitos:
  - AltServer ejecutándose en tu Mac
  - iPhone y Mac en la misma red WiFi
  - Background App Refresh activado para AltStore

## Solución de Problemas

### "Unable to install"
- Verifica que tienes menos de 3 apps sideloaded
- Revoca certificados antiguos en appleid.apple.com

### La app no se renueva automáticamente
1. Abre AltStore
2. Ve a "My Apps"
3. Toca "Refresh All" manualmente
4. Verifica que AltServer esté ejecutándose en tu Mac

### "Developer cannot be verified"
- Ve a Ajustes → General → VPN y gestión de dispositivos
- Confía en el desarrollador

## Información del IPA

- **Archivo**: mks-multiplatform-iptv.ipa
- **Tamaño**: 7.0 MB
- **Bundle ID**: dev.mks2508.mks-multiplatform-iptv
- **Versión mínima iOS**: 18.6
- **Dispositivos**: iPhone y iPad

## Actualización de la app

Para actualizar la app con una nueva versión:
1. Genera un nuevo IPA siguiendo los mismos pasos
2. Instala sobre la versión existente
3. Tus datos se mantendrán