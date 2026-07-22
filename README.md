# DelivEcosys 🚀
El ecosistema definitivo de reparto y seguimiento en tiempo real, diseñado con **Flutter** e integrado con **Firebase Cloud Firestore**.

Este repositorio unifica las aplicaciones cliente, repartidor y notificaciones en reloj inteligente, simplificando la arquitectura y permitiendo una sincronización en tiempo real fluida y robusta.

---

## 📱 Estructura del Proyecto

El ecosistema está dividido en dos aplicaciones principales:

1. **[`cliente_celular/`](./cliente_celular)**: Aplicación Flutter unificada. Sirve tanto para los clientes como para los repartidores (drivers) mediante control de accesos por roles.
2. **[`watch_notification/`](./watch_notification)**: Aplicación complementaria para smartwatches que maneja alertas y estados de entrega en dispositivos vestibles.

---

## ✨ Características Principales

### 🔑 Autenticación y Enrutamiento por Roles
- Pantalla de inicio de sesión unificada (`LoginScreen`) que permite alternar dinámicamente entre el rol de **Cliente** y **Repartidor**.
- Autenticación rápida integrada para perfiles de prueba preconfigurados.

### 🚴 Panel de Control del Repartidor (`RiderDashboardScreen`)
- **Simulación Multiruta Concurrente**: Cada entrega cuenta con un temporizador GPS independiente en segundo plano. El repartidor puede iniciar, pausar y realizar el seguimiento de múltiples envíos simultáneamente sin interferencias.
- **Validación de Entrega por PIN OTP**: Flujo de seguridad donde el cliente recibe un código PIN de 4 dígitos y el repartidor lo valida para finalizar el pedido.
- **Chat Bidireccional Integrado**: Comunicación instantánea y directa por mensaje con cada cliente asignado.
- **Diseño Adaptativo Premium**: Optimizado estéticamente con temas claros, acentos esmeralda (`#10B981`) y escalado automático para evitar desbordamientos visuales en tablets y smartphones.

### 📦 Interfaz de Seguimiento del Cliente (`CustomerPhoneScreen`)
- **Rastreo en Vivo en Mapa Vectorial**: Movimiento del repartidor renderizado fluidamente sobre mapas interactivos tácticos.
- **Barra de Progreso (Stepper)**: Estado de la orden visible en todo momento.
- **Indicador de Estado de Conexión**: 
  - Un punto brillante al lado del selector de orden indica el estado de la base de datos (Verde = Datos en Tiempo Real de Firestore, Amarillo = Modo Simulado Local/Offline).
  - Un banner informativo en color ámbar alerta al cliente si el pedido actual está corriendo localmente por falta de conexión o desincronización en la nube.

---

## 🛠️ Requisitos e Instalación

### Requisitos Previos
- **Flutter SDK**: `>=3.0.0`
- **Dart SDK**: `>=3.0.0`
- Dispositivo Android, iOS o Emulador para pruebas.

### Configuración del Entorno

1. **Clonar el repositorio**:
   ```bash
   git clone https://github.com/manolokogamerx45-beep/DelivEcosys.git
   cd DelivEcosys
   ```

2. **Configurar Firebase en `cliente_celular`**:
   Asegúrate de inicializar Firebase y añadir tu archivo de configuración `google-services.json` (para Android) o `GoogleService-Info.plist` (para iOS) en las carpetas nativas correspondientes de `cliente_celular/`.

3. **Instalar dependencias**:
   ```bash
   cd cliente_celular
   flutter pub get
   ```

4. **Ejecutar la aplicación**:
   ```bash
   flutter run
   ```

---

## 🧭 Flujo de Pruebas Recomendado

1. **Sembrado de Datos (Tablet / Repartidor)**:
   - Inicia sesión como Repartidor (`carlos@repartidor.com`).
   - Haz clic en **"Reset DB"** en la barra superior. Esto cargará las órdenes de demostración en tu instancia de Cloud Firestore.
2. **Aceptar Orden**:
   - Selecciona un pedido pendiente de la lista lateral y presiona **"Aceptar Pedido"**.
3. **Inicio de Ruta**:
   - Presiona **"Iniciar Ruta GPS"** para iniciar la simulación del vehículo.
4. **Seguimiento del Cliente (Celular / Cliente)**:
   - Inicia sesión como el Cliente correspondiente al pedido aceptado.
   - Observa el indicador en **Verde** (conexión en vivo) y sigue la ruta en tiempo real en el mapa.
5. **Chat y Entrega**:
   - Envía un mensaje desde cualquiera de los dos roles y verifica la recepción instantánea en el otro dispositivo.
   - Introduce el código OTP en el panel del repartidor para marcar la orden como completada.
