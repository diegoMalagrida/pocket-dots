# Sistema Quickshell (rice de diego)

> 🇬🇧 [In English](README.en.md)

Hyprland + **pywal en vivo** (`Colors.qml` vigila `~/.cache/wal/colors.json` →
todo se recolorea al cambiar de fondo, sin recargar nada).

La barra superior sigue la **arquitectura** de caelestia (`modules/drawers/`:
una sola ventana, un solo estado, una sola máscara) pero **no su estética**.
Aquí manda otra idea:

> El notch es la única forma de la pantalla, y el punto de entrada del
> escritorio: los paneles se despliegan **de él**. La barra no es una superficie.

```
 Arch  ●━● ●   Kitty    ╭─ 18:01  Martes        󰂄 99% ─╮
                       ╰─         4 de agosto           ─╯
```

- La barra **no tiene fondo**: ni franja, ni islas, ni pastillas. Son glifos
  sueltos sobre el fondo de pantalla, con un contorno oscuro sutil para leerse
  igual sobre fondos claros y oscuros.
- El notch es una **isla negra suelta** pegada al borde superior, con las
  esquinas superiores invertidas del MacBook. **El reloj vive dentro de él**:
  es lo que le da sentido en reposo en vez de ser un hueco negro.
- **En reposo mide exactamente la banda reservada (32 px)**, así que no tapa
  nunca ninguna ventana. Solo sobresale cuando tú lo provocas.

Las cuatro ampliaciones del 9-ago-2026 —modo lectura, salud de batería, acento
de carátula y wifi empresarial— nacen de ideas de
[`surface-dots`](https://github.com/snes19xx/surface-dots), pero están
reimplementadas para este rice: sin rutas BAT hardcodeadas, sin un generador de
paleta externo, sin contraseñas en `argv` y sin pisar el estado previo de
Hyprland. No se copió su shell ni su estética.

## Ajustes (`SettingsWindow.qml`)
**No es un panel del notch, y es a propósito.** Los paneles del notch son
transitorios: abres, haces una cosa, se cierran al pinchar fuera. Unos ajustes
son lo contrario — exploras, tocas un slider y quieres mirar el terminal a ver
si funcionó. Cerrarse al pinchar fuera sería hostil, y anclado arriba taparía
media pantalla. Así que es una **ventana flotante de verdad** (`FloatingWindow`,
xdg-toplevel), con el mismo lenguaje visual que el notch y lanzada desde él.

Se abre con `Super+A` (A de Ajustes) o `Super+,` (como `Cmd+,` en macOS), desde
el engranaje del centro de control, o `qs ipc call notch settings`.

**Siempre sale flotante, centrada y contenida (900x620).** Eso no lo decide el
QML: lo fuerza una `windowrule` de `hyprland.conf` que casa `class org.quickshell`
+ `title Ajustes` (es la única ventana de verdad del shell; lo demás son capas).
Sin ella Hyprland la tilaba y ocupaba media pantalla. El QML lleva el mismo
tamaño en `implicitWidth/Height` para que no haya un fogonazo grande antes de
que Hyprland la coloque. Si la quieres anclada en algún momento, `Super+V` a
mano; al volver a abrirla vuelve a salir flotante y centrada.
El ancho no debe bajar de 780: cada fila pide 120 de etiqueta + 14 + 270 de
control, más 224 de barra lateral y los márgenes. El alto sí puede ser menor
porque todas las secciones son `Flickable`, pero 620 px permite leer completa
la tarjeta de Energía sin tener que adivinar que continúa debajo.

| sección | qué lleva |
|---|---|
| Apariencia | todo lo que antes había que editar en el QML: forma del notch, comportamiento, barra, tipografía, y el acceso al selector de fondos |
| Sistema | brillo, luz nocturna, modo lectura, batería con salud/ciclos/capacidad/autonomía, cafeína, modo remoto, wifi y perfiles EAP, no molestar y pokémon del tema |
| Sonido | volumen, silencio y elección de dispositivo de salida/entrada (Pipewire nativo, sin pavucontrol) |
| Bluetooth | emparejar, conectar, desconectar y olvidar (Bluez nativo, sustituye al rofi) |
| Atajos | los binds de `hyprland.conf`, parseados en vivo y buscables (solo lectura) |
| Acerca de | distro, kernel, compositor, shell, CPU, RAM, disco, uptime, paquetes y dónde vive cada cosa del rice |

### Anatomía de la ventana
Cuatro decisiones que explican cómo está construida, y por qué NO hay que
volver al diseño anterior:

1. **La descripción de un ajuste no va debajo de su etiqueta.** Iba, y cada fila
   medía tres líneas: en la ventana original cabían siete ajustes y Apariencia era un
   scroll interminable. Ahora la fila mide 42 px y la descripción viaja a
   `ShellState.settingsHint`, que la ventana pinta en una **franja fija al pie**
   de hasta dos líneas cuando pasas el ratón. Cero reflow, nada tapando nada, y
   no se pierde una explicación larga. Cada fila la publica con `hint:`.
2. **Los ajustes van en tarjetas** (`SettingsControls.Card_`), redondeadas y con
   hairline: ley 1 del lenguaje de forma, lo redondo es del shell. Antes era una
   lista plana con separadores de 1 px que no agrupaba nada.
3. **El buscador de la barra lateral es global.** Escribe y ya: tiene el foco
   nada más abrir, ignora mayúsculas y tildes, muestra el número de resultados
   de cada sección y salta a la primera que coincida. `↑`/`↓` recorren solo esas
   secciones, `Ctrl+F` recupera el foco y `Esc` vacía la búsqueda (y si ya está
   vacía, cierra la ventana). Cada tarjeta se esconde sola si no le queda ninguna
   fila — y para eso las filas publican `matches` aparte de `visible`, porque en
   QML `visible` es *efectiva* y una tarjeta oculta haría que sus filas dijeran
   `false` para siempre.
4. **La cabecera no scrollea**: icono, título, descripción y acción de la sección
   (`actionText` / `actionRun`). También hay cierre visible; `Ctrl+W` y `Esc`
   siguen funcionando. La acción destructiva "Restablecer" exige una segunda
   pulsación antes de ejecutarse.

Para condicionar una fila se usa `shown:` (p. ej. los ajustes de isla solo en
modo isla). **Nunca `visible:`**, que es de quien filtra el buscador.

### Persistencia (`Config.qml`)
`FileView` + `JsonAdapter` sobre `~/.config/quickshell-rice.json`. Los cambios se
aplican **en vivo** (mueves el slider y el notch cambia) y se guardan solos.

**El fichero va FUERA de `~/.config/quickshell/` a propósito**: Quickshell vigila
su directorio de configuración para recargar en caliente, y guardar ahí dentro
dispararía una recarga por cada píxel de slider.

## Arquitectura
- **`ShellState.qml`** (singleton) — el hub: reloj, ventana activa, MPRIS,
  paleta de carátula, Pipewire (volumen), espectro de audio, brillo,
  batería/UPower/CPU/RAM, red,
  bluetooth, pacman, swaync, cafeína, **y la máquina de estados del notch**.
  UI cero.
- **`TopShell.qml`** — la ventana única: la forma del notch, la máscara, el
  contenido de la barra, el manejo de pantalla completa.
- **`NotchContent.qml`** — lo que se ve dentro del notch en cada modo.
- **`Config.qml`** (singleton) — ajustes persistentes; lo que antes eran
  constantes cocidas.
- **Componentes**: `MediaPanel`, `BarItem`, `NotchSlider`, `SettingsControls`,
  `StyledText`, `PillButton`, `Card`.
- **Diseño**: `Colors` (pywal + semánticos), `Appearance` (tokens), `Icons`.
- **Entrypoint**: `shell.qml` → `TopShell` + `SettingsWindow` + `MediaControls`
  + `WallpaperPicker`. (El `Overview` de pantalla completa se retiró el
  6-ago-2026: ahora es una cara del notch, `OverviewPanel.qml`.) Autostart: `quickshell.service` (unidad de
  usuario, supervisada; ya NO `exec-once`). Para reiniciar la shell usa
  `systemctl --user restart quickshell`, no `pkill`: systemd la relanzaria
  igualmente y tendrias dos arranques peleandose.

## Reparto de responsabilidades

**Regla: cada dato tiene UN solo sitio.** Si algo está en el notch, no se repite
en la barra.

**El notch** lleva lo permanente y lo de siempre: hora, fecha, batería, media,
volumen y brillo (OSD al cambiarlos + sliders en el panel), el acceso al panel
de estado del equipo, y todos los
controles (red, bluetooth, notificaciones, cafeína, fondo, bloquear, apagar).

**La barra izquierda**: launcher Arch (rueda = volumen) · workspaces en puntos
(el activo se estira) · nombre de la app en negrita. Nada de esto está en el notch.

**La barra derecha solo enseña excepciones** — lo que NO es normal. En un día
tranquilo está vacía del todo:

| elemento | cuándo aparece |
|---|---|
| systray | lo que registren las apps |
| actualizaciones | solo si hay |
| notificaciones | solo si hay (con el número) o hay DND — clic abre el centro de control, clic derecho conmuta DND |
| cafeína | solo si está activa |
| bluetooth | solo si hay algo **conectado** (encendido-sin-nada es ruido) |
| red | solo si **no** hay red (estar conectado es lo normal) |
| volumen | solo si está **silenciado** (el nivel lo lleva el OSD del notch) |
| captura de pantalla | solo si algo está capturando el **monitor** (punto rojo que late) |

## El notch

| modo | disparador | qué enseña | ancho × alto |
|---|---|---|---|
| `launcher` | `Super+R` / clic en el logo de Arch | buscador + lista de aplicaciones | 660 × **según contenido** |
| `control` | clic en el notch / `Super+D` / campana | reproductor vertical + sliders + conmutadores + notificaciones | 1080 × 526 |
| `system` | botón Tu equipo / `Super+Shift+D` | paisaje de actividad + espacio, temperatura y batería | 920 × 420 |
| `network` | chevron de "Red" en el centro de control / icono de red | wifis, PSK, perfiles WPA-Enterprise, encender/apagar | 470 × 412 |
| `bluetooth` | chevron de "Bluetooth" en el centro de control | emparejar, conectar, olvidar, encender/apagar | 470 × 412 |
| `power` | `Super+Shift+E` / tecla de encendido | bloquear · suspender · salir · reiniciar · apagar | 520 × 158 |
| `notif` | llega una notificación | icono + resumen + cuerpo + app (4 s) | 430 × 66 |
| `track` | cambia canción / play | carátula + título + artista + visualizador (3 s) | 400 × 52 |
| `activity` | volumen o brillo | OSD icono + barra + % (1,8 s) | 330 × 42 |
| `peek` | hover (con 240 ms de retardo) | lo mismo, creciendo: fecha con año | 380 × 44 |
| `media` | hay música | carátula + hora + espectro real (8 bandas, cava) | 268 × **32** |
| `idle` | — | **solo la hora**, centrada | 140 × **32** |

Gestos: **rueda vertical** = volumen · **rueda horizontal** = cambiar de
escritorio · **clic derecho** = play/pause · **clic** = centro de control.

La rueda horizontal (6-ago-2026, idea adaptada de Tide-island) **acumula**: un
panel táctil manda decenas de eventos por gesto, así que sin acumular un arrastre
corto te cruzaría los diez escritorios de golpe; 120 unidades = un paso, que es
la muesca de rueda de Qt. Va a `workspace e+1`, igual que el `Super+rueda` de
`hyprland.conf`: salta al siguiente que **existe**, no al id siguiente.

Y **solo este gesto** enseña la cara `ws` ("Escritorio 3") en el notch. Con
`Super+1..0` no sale a propósito: ahí ya sabes a dónde vas porque acabas de
teclear el número, y el indicador de la barra está al lado. Con la rueda no hay
número que teclear y estás mirando el notch, así que es el único caso en que el
gesto necesita acuse de recibo.

Los dos modos pasivos (`idle`, `media`) miden 32 = la banda reservada: nunca
invaden la ventana de abajo. El **retardo de 240 ms** en el hover evita que el
notch se despliegue solo por cruzar el ratón por ahí.

### Paneles: el notch como punto de entrada
`ShellState.panel` (`""` / `"control"` / `"launcher"` / …) manda sobre el modo. **Añadir
un panel nuevo son tres pasos**: un valor más en `panel`, su tamaño en
`notchW`/`notchH`, y su capa en `NotchContent.qml`.

**Paneles actuales**: `MediaPanel.qml`, `LauncherPanel.qml`, `ControlPanel.qml`,
`NetworkPanel.qml`, `PowerPanel.qml`, `BluetoothPanel.qml`, `OverviewPanel.qml`,
`CalendarPanel.qml`.

#### El calendario (`CalendarPanel.qml`)

Un mes, y nada más. Dos puertas: su **cuadro en el centro de control**, igual que
Red o Bluetooth, y **tres dedos hacia abajo en el trackpad**, que es la misma
postura del gesto de escritorios pero en el otro eje. El cuadro es la puerta que
se ve; el gesto, la rápida.

Se probó antes a abrirlo **pinchando el reloj** del notch —el gesto de macOS— y
se retiró: ese clic ya abría el centro de control desde siempre, y quitarle a
alguien un gesto que tiene en los dedos a cambio de una función nueva es un mal
trato. El clic derecho tampoco vale: es el play/pause del reproductor.

El gesto vive **solo en `hyprland.lua`**, porque usa una tabla de callbacks
(`action = { finish = ... }`) que la sintaxis clásica de la `.conf` no tiene.

La rejilla es **siempre de 6 filas**, aunque el mes quepa en 5: así la altura del
notch no pega un salto al cambiar de mes. Los nombres de mes y las iniciales de
los días salen de `ShellState.loc`, que sigue al idioma, así que el calendario se
traduce solo y empieza la semana por donde diga el locale. La única cadena suya
es el botón «Hoy», que solo existe cuando te has ido del mes en curso.

Se pidió con notas al lado (un comentario en YouTube). **Las notas se descartaron
a propósito**: todas las caras del notch son vistas sobre algo que el sistema ya
sabe, y unas notas harían del shell el dueño de datos del usuario, con su copia
de seguridad, su corrupción y su migración detrás. Un calendario, en cambio, es
una vista sobre el tiempo.

#### El mapa de escritorios (`OverviewPanel.qml` + `OverviewWindow.qml`)

`Super+Tab`. Diez celdas (5x2, exactamente los escritorios de `Super+1..0`), cada
una el área útil de la pantalla a escala 0.14, con el fondo de pantalla debajo y
las ventanas colocadas **donde están de verdad**: una flotante pequeña sale
pequeña y descentrada. Es un MAPA, no una lista.

**Las miniaturas se arrastran.** Soltar en otra celda es
`movetoworkspacesilent`; soltar una flotante dentro de su propia celda es
`movewindowpixel exact`, o sea que también se recolocan ventanas dentro de un
escritorio. Clic = ir a esa ventana · clic derecho = cerrarla (petición de
cierre, la app puede pedir guardar) · clic con la rueda = flotante/embaldosada ·
clic en el hueco de una celda = ir a ese escritorio. Con el teclado: flechas,
Enter, `1..0` y Esc. La franja del pie enseña el título de la que señalas (a esta
escala no cabe escribirlo encima, y taparía la ventana).

Sustituyó a un `Overview.qml` que tomaba la pantalla entera y enseñaba las
ventanas en una parrilla suelta. El problema no era estético: **una parrilla no
dice en qué escritorio está cada cosa**, que es lo único que quieres saber al
pulsar `Super+Tab`.

**Cuatro cosas que costaron y no se ven leyendo el código:**

1. `toplevel.address` viene **sin** el `0x` y los despachadores de Hyprland lo
   exigen. Sin el prefijo todos los dispatch contestan `moveWindow: no window` y
   el arrastre no hace nada, **en silencio**.
2. `toplevel.workspace` lo mantiene Quickshell al día solo, pero
   `toplevel.lastIpcObject` —de donde salen `at` y `size`— se queda **congelado**
   hasta que alguien llama a `Hyprland.refreshToplevels()`. Medido. Por eso hay
   un temporizador que lo pide **solo mientras el overview está abierto**.
3. La miniatura se ata al área de su celda (`Math.min(cellW - tw, …)`), y por eso
   la celda no necesita recortar. Recortando harían falta **dos** copias de cada
   ventana (una dentro, recortada, y otra libre para arrastrar), con el doble de
   capturas: no se puede sacar de una caja algo que la caja recorta.
4. El modelo pasa por `ScriptModel`. Un `Repeater` sobre un array nuevo destruye
   y recrea sus delegados, así que cada arrastre apagaría y volvería a encender
   las diez capturas, con parpadeo. `ScriptModel` compara por identidad.

Al arrastrar se le pone a la ventana una posición **optimista** (`posHint`) que
se retira sola en cuanto el dato real coincide: Hyprland tarda ~100 ms en
confirmar, y sin la mentira la miniatura volvería de un salto al sitio viejo para
saltar después al nuevo.

El **lanzador** (`LauncherPanel.qml`) sustituye a rofi: búsqueda difusa sobre
`DesktopEntries`, iconos por `Quickshell.iconPath()`, Enter lanza, Esc cierra.
Teclas: ↑/↓, `Ctrl+J/K`, `Ctrl+N/P`, `Tab`/`Shift+Tab`, `Inicio`/`Fin`,
`RePág`/`AvPág`.

**El alto se ajusta a lo que hay.** Si buscas y salen tres apps, o si es una
cuenta, el panel encoge hacia arriba en vez de dejar un hueco negro debajo.
`LauncherPanel` publica el número de filas en `ShellState.launcherRows` y
`launcherH` calcula el alto. Medido: 49 apps → 409 px · 3 apps → 217 · solo
calculadora → 135 · sin resultados → 119.

**Cuidado con `launcherChrome`**: esa constante (73) tiene que cuadrar
EXACTAMENTE con los márgenes de `LauncherPanel.qml` (4 + 50 + 1 + 6 + 12). La
primera versión usaba 54 y se dejaba 19 px fuera, así que la lista recibía menos
alto del que ocupaban sus filas y **la última se veía recortada**. Si tocas esos
márgenes, actualiza la constante.

**También es calculadora.** Si lo que escribes es una cuenta, aparece arriba una
fila con el resultado y **Enter lo copia al portapapeles** (nativo, vía
`Quickshell.clipboardText`, sin `wl-copy`). El notch confirma con un aviso breve
—aquí sí hace falta, porque copiar no tiene ninguna otra señal de haber ocurrido.
Soporta `+ - * / ^ % ( )`, coma o punto decimal, `pi`, `e` y las funciones
habituales (`sqrt`, `log`, `sin`…). `=` al principio fuerza el modo calculadora.

Para que no salte con cualquier cosa hace falta que haya **un número y un
operador**, y toda palabra tiene que estar en la lista blanca: así `7zip`,
`firefox` o `code 2` no disparan la calculadora. Comprobado también que
`0.1+0.2` da `0.3` y no `0.30000000000000004` — el resultado se redondea a 10
decimales antes de mostrarse.

**Está pensado para el teclado, y el ratón no puede estorbar.** Al abrirse manda
el teclado siempre, aunque el puntero esté justo encima de una fila. El único
criterio para que el ratón tome el mando es que el **puntero cambie de sitio**
(`pointerMoved()`), lo que distingue los dos casos que molestaban:

- al abrir, Wayland entrega un evento porque el puntero "entra" en la superficie
  recién creada, aunque el ratón esté quieto → el primer evento solo fija la
  referencia y no selecciona nada;
- al escribir, la lista se refiltra y las filas pasan bajo un cursor quieto,
  disparando `onEntered` → mismo punto, así que no cuenta.

Un guardado por tiempo no vale: el evento de entrada llega **después** de que la
capa se reconfigure por el cambio de `keyboardFocus`, así que se cuela por
detrás de cualquier ventana de armado razonable. La puntuación prioriza prefijo exacto del
nombre, luego prefijo de palabra, luego subcadena, y como último recurso
subsecuencia — escribir "kit" pone `kitty` el primero.

El **centro de control** (`ControlPanel.qml`) sustituye al de swaync **y al
antiguo Sidebar/dashboard**. Izquierda: media, sliders de volumen y brillo, siete
conmutadores (red, bluetooth, no molestar, cafeína, luz nocturna, remoto y
pokémon) y una puerta etiquetada como «Tu equipo». Derecha: el historial de
notificaciones.

El panel **Tu equipo** conserva 60 muestras del mismo `sysstats.sh` que ya
alimentaba el centro de control (90 segundos, sin un segundo sondeo paralelo):
superpone CPU y RAM en un solo paisaje y deja espacio, temperatura y batería
como tres lecturas tranquilas al margen. El wallpaper actual entra con muy poca
opacidad como luz ambiental; no hay cuadrícula, tarjetas ni estética de panel de
administración. El botón de vuelta regresa al centro de control sin cerrar y
reabrir la superficie.

La **pokéball** conmuta los sprites tematizados de la terminal: con ella
encendida, el pokémon que sale al abrir la primera kitty se elige entre los que
mejor pegan con la paleta de pywal; apagada vuelve a salir uno al azar, que es
como estaba antes. Es un interruptor sobre `~/.local/bin/poke-theme` (`on`/`off`
/`is-on`, mismo trato que el modo remoto: el estado real lo dice el script, aquí
no se adivina). El sesgo lo aplica `poke_theme_pick()` en `~/.zshrc`, que **solo
elige el fichero** — el dibujado del sprite no se toca desde aquí.

Al retirar el Sidebar solo había dos cosas suyas que no estuvieran ya aquí —**el
tiempo** (`wttr.in`, cada media hora) y el **uso de disco**— así que se migraron
a `ShellState` antes de quitarlo. El disco ya venía en `sysstats.sh`, solo faltaba
leer el campo 9.

Las tarjetas de Red y Bluetooth del centro de control son **una sola zona**:
pulsar en cualquier punto abre el panel dedicado. No llevan chevron ni una
diana diminuta aparte; el interruptor para encender o apagar está en la cabecera
del propio panel. Las demás tarjetas (no molestar, cafeína, luz nocturna…)
siguen actuando directamente al pulsarlas.

`BluetoothPanel.qml` es hermano de `NetworkPanel.qml`: mismo esqueleto y mismo
trato. Si el adaptador está **bloqueado por rfkill** lo dice y desactiva el
interruptor, en vez de que pulsarlo se quede en nada sin explicación
(`BluetoothAdapterState.Blocked`).

El **selector de red** (`NetworkPanel.qml`) sustituye al menú de rofi. Descubre,
ordena y conecta mediante `Quickshell.Networking`: interruptor de wifi, lista
ordenada (conectada → guardadas → por señal, con los SSID repetidos colapsados al
de mejor señal), y una contraseña PSK se pide **desplegando la propia fila**, no
en otra ventana. Las variantes 802.1X (WPA/WPA2-EAP, Suite B, LEAP y WEP
dinámico) se detectan aparte: una guardada conecta con su perfil y enseña un
lápiz para editarlo; una nueva abre
`nm-connection-editor`. Es deliberado: el QML de Quickshell todavía no expone
identidad, método EAP ni certificados, y construir un `nmcli ... password ...`
dejaría el secreto visible en la lista de procesos. El editor soporta además
PEAP, TTLS y EAP-TLS, no solo un caso cocido. `scripts/wifi-enterprise.sh`
(`~/.config/hypr/`) resuelve el UUID por **SSID exacto** sin leer ni imprimir
identidad o clave.

El escáner de wifi y el descubrimiento de bluetooth solo corren mientras su panel
está abierto, para no tener a NetworkManager y a Bluez barriendo el aire todo el
rato. Se controlan con **`Binding` declarativos**, no con `onPanelChanged`: el
manejador imperativo solo se disparaba al cambiar de panel, así que si encendías
el bluetooth *desde dentro de su propio panel* el descubrimiento no arrancaba
nunca.

Los umbrales del icono de señal son 72/48/24 y no los "clásicos" 75/50/25: en la
práctica las señales caen entre 30 y 60 y con el reparto de manual salían todas
con el mismo icono.

El **menú de encendido** (`PowerPanel.qml`) sustituye a wlogout, que tomaba la
pantalla entera. Arranca siempre sobre "Bloquear" — lo menos destructivo — para
que un Enter accidental no te apague el portátil. ←/→ o Tab mueven, Enter
confirma, Esc cierra.

**Notificaciones propias**: Quickshell es ahora el servidor D-Bus
(`NotificationServer` en `ShellState.qml`), porque el panel de swaync era una
ventana GTK suya y no se podía meter dentro del notch. Al llegar una, el notch se
estira y la enseña 4 s como live activity; luego se queda en el historial del
centro de control. `swaync.service` queda **deshabilitado**.

**Foco de teclado**: la capa pasa a `WlrKeyboardFocus.OnDemand` solo mientras el
lanzador, el menú de encendido o el selector de red están abiertos; el resto del
tiempo es `None` para no robarle el teclado a las ventanas.

**`OnDemand`, nunca `Exclusive`.** Con `Exclusive` el foco se queda pegado a la
capa y Hyprland deja de cancelar el `HyprlandFocusGrab`, así que **un clic fuera
ya no cierra el panel y te quedas atrapado dentro**. Con `OnDemand` es el propio
grab el que fuerza el foco de teclado (se puede escribir sin hacer clic) y al
pinchar fuera se cancela y el panel se cierra. Comprobado midiendo el ancho del
notch: con `Exclusive` el clic fuera dejaba el lanzador abierto; con `OnDemand`
cierra.

**Todo panel debe atender `Escape`.** Además, el `Item` del notch en
`TopShell.qml` lleva un `Keys.onEscapePressed` de red de seguridad: si un panel
no la atiende, la tecla burbujea hasta ahí y cierra igual. Ningún panel puede
dejarte encerrado.

**Trampa que costó encontrar**: al cambiar `keyboardFocus` la capa se reconfigura
y Hyprland **cancela el `HyprlandFocusGrab` al instante**, así que el panel se
cerraba solo nada más abrirse. Por eso el grab se arma con 400 ms de retardo
(`grabArmed` en `TopShell.qml`), cuando la capa ya se ha asentado.

### Estructura de dos polos
El contenido del notch está anclado siempre igual para que **nada salte** al
cambiar de estado: **izquierda** el reloj, **derecha** lo contextual (batería en
reposo y en hover, carátula + picos con música). Al pasar el ratón no se
recoloca nada: solo crece y la fecha se escribe entera.

### El visualizador (las barritas)
**Espectro real, 8 bandas, de graves a agudos.** Sale de **cava** (`scripts/cava.conf`,
salida `raw`/ascii a stdout) que `ShellState.qml` lee línea a línea y publica en
`ShellState.levels`. Corre **solo mientras suena algo** (`running: mediaLive`,
~4 % de un núcleo) y al pausar deja el array a cero para que las barras no se
queden clavadas durante el fundido.

Antes esto era un `PwNodePeakMonitor` y **no funcionaba**: da UN número (el pico
global del sink) que se iba desplazando por el array, así que todas las barras
eran la misma señal repetida y, como el pico en lineal casi siempre roza 1, se
quedaban pegadas al techo — un código de barras, no un visualizador. Encima
`onPeakChanged` solo salta cuando el valor **cambia**: en un tramo comprimido
dejaba de llegar señal y las barras se congelaban.

**Pocas y gruesas**: 8 barras de 4 px con 4 px de hueco (60 px de tira). Con 14
de 2,5 px se leía como una trama de rayas, no como un ecualizador. El suelo de
altura es el ancho de la barra, así en reposo son 8 puntos redondos. Si cambias
`ShellState.bands` hay que cambiar `bars` en `cava.conf`: son el mismo número.
El reproductor vertical de Super+D reutiliza esas ocho bandas, pero las ensancha
a 6 px y les da 58 px de recorrido para que funcionen como remate visual.

Dos mandos para el tacto: `noise_reduction` en `cava.conf` (0 nervioso ↔ 100
pastoso; ahora 70) y la gamma del parseo en `ShellState.qml` (0,6 — sin ella los
agudos son tan pequeños al lado de los graves que no se ven moverse en 18 px).
**Nada de `Behavior on height`**: cava ya filtra la señal a 60 fps con su propia
caída por gravedad, y una animación de 90 ms que nunca termina de correr solo
aplasta el recorrido. Si falta `cava` en el PATH las barras se quedan planas.

### El reloj
En reposo el notch enseña **solo la hora**, centrada, en una píldora estrecha: es
lo más minimalista posible sin dejarlo vacío. Al pasar el ratón crece y aparecen
la fecha entera con año y la batería — no se pierde nada, solo se mueve a donde
hace falta. Con música el reloj se aparta a la izquierda para dejar sitio a la
carátula y a los picos.

La fecha y la batería en reposo se pueden reactivar en Ajustes › Apariencia. Y
el ancho **se adapta solo**: `Config.idleW` es el ancho para la hora sola, y
`ShellState.idleW` le suma sitio por cada elemento que enciendas. Si fuera un
ancho fijo, reactivar la fecha recortaría el contenido.

**Dos familias tipográficas, a propósito**: `Appearance.font` (JetBrains Mono
Nerd Font) para la barra y para TODO lo que pinte iconos — los glifos solo
existen en esa familia. `Appearance.fontUI` (Adwaita Sans, base Inter) para el
texto de dentro del notch. Una fecha en monoespaciada queda desmadejada: las
letras se separan igual que los dígitos y parece salida de terminal. La hora usa
`font.features: { "tnum": 1 }` para que los dígitos no bailen al cambiar de
minuto.

Cuidado: en QML el tipo `font` **no tiene `families`** (solo `family`), aunque
QFont sí lo tenga en C++. Asignarlo revienta la carga entera.

### Movimiento
**Un solo lenguaje para todo lo que se mueve**, con los tokens en
`Appearance.qml` (`mShape`, `mIn`, `mOut`, `mStagger`, `mQuick`…). La forma es la
referencia y el contenido tiene que sentirse parte de ella, no algo pegado
encima.

La pieza clave es **`NotchLayer.qml`**: cada "cara" del notch (reposo, hover,
OSD, cada panel) es una `NotchLayer`, y todas se cruzan igual. La transición es
**asimétrica a propósito**:

- lo que sale se va en **110 ms**, la mitad de lo que tarda en entrar lo nuevo;
- lo que entra **espera esos mismos 110 ms** (`mStagger`) a que el hueco quede
  libre, y llega con la misma curva elástica que el morfeo de la forma
  (`OutBack`), creciendo desde el 96 %.

Si las dos capas duran lo mismo se solapan al 50 % y se ve un borrón; con el
relevo escalonado la forma va delante y el contenido la sigue. El contenido se
asienta a los ~320 ms y la forma a los 440, así que nunca va por detrás.

**Nunca animes un ancho derivado.** Las barras de volumen y brillo tenían
`Behavior on width` sobre un ancho que es `carril × fracción`. Al abrir el panel
el notch se ensancha, o sea que el carril crece, y la barra se pasaba 140 ms
persiguiéndolo: parecía que se rellenaba sola como una barra de carga. La regla
es animar el **valor** (`property real shown` con su `Behavior`) y calcular el
ancho a partir de él sin animación: así redimensionar es instantáneo y solo se
anima un cambio real de volumen o brillo. Aplica a `NotchSlider`, a la barra del
OSD y a `SettingsControls.Slider_`.

Antes todas las capas usaban `NumberAnimation` **sin curva**, o sea interpolación
lineal, que es lo menos fluido que hay. Y dentro de la capa de reposo la fecha,
la batería y la carátula aparecían y desaparecían **de golpe** al empezar a sonar
música; ahora se funden.

### Dos estilos: Notch e Isla
`Config.notchStyle` cambia entre los dos, en vivo desde Ajustes › Apariencia:

- **`notch`** — pegado al borde superior, con las esquinas superiores invertidas
  del MacBook. Es una ruta `Shape` con bézier.
- **`island`** — píldora flotante despegada del borde y redondeada por los cuatro
  lados, como el Dynamic Island del iPhone. Aquí no hace falta `Shape`: es un
  `Rectangle` con `radius`. La separación (`Config.islandGap`) sale **de dentro
  de la banda reservada**, así que la isla tampoco tapa ventanas.

### Detalles de la forma (modo notch)
`fl` (esquina superior invertida) = 13, `rb` (radio inferior) =
`min(30, alto - fl - 1)`, con bézier `k = 0.5523`. Dentro de elementos `Path`
**no existe `parent`** → todo se referencia por el id del `ShapePath` (`sp`).

### Pantalla completa
Con una ventana fullscreen la superficie se desliza hacia arriba y la máscara se
vacía. La capa es `WlrLayer.Top`, no `Overlay`, para que rofi / wlogout /
hyprlock salgan por encima.

### La máscara
Cubre **solo** el notch y los dos grupos de glifos, no la banda entera: el resto
del borde superior deja pasar el ratón, porque la barra no es una superficie.

## Colores
`Colors.c1..c5` vienen de pywal y **cambian con el fondo**: `color2` no tiene por
qué ser verde. Para estados con significado hay colores **fijos**: `Colors.ok`,
`Colors.warn`, `Colors.crit`. (Con un fondo azul, la batería cargando salía roja
y parecía una alarma.)

La música es la excepción contextual. `ColorQuantizer` reduce la carátula activa
a ocho tonos y `ShellState.mediaAccent` escoge uno saturado y legible sobre
negro. Ese acento viaja a `MediaPanel`, al reproductor flotante y a las dos caras
de música del notch; cambia con una animación de color al cambiar de canción. Si
MPRIS no publica carátula, aún está cargando o la imagen es casi monocroma,
vuelve a `Colors.accent`: pywal sigue siendo un fallback completo, nunca hay un
color inválido ni un proceso externo de paleta.

Ojo también con `font.capitalization: Font.Capitalize`: capitaliza TODAS las
palabras y en español deja "Martes, 4 De Agosto". Usa `ShellState.capitalize()`.

## El idioma (castellano e inglés)

El shell habla castellano e inglés. La capa son tres ficheros: `I18n.qml` (el
singleton con `I18n.tr(...)`), `translations-en.js` (el diccionario inglés, 402
entradas) y `tools/i18n-check.py` (el repaso).

**El castellano es el código.** Las cadenas siguen escritas en español dentro de
cada `.qml`, envueltas en `I18n.tr(...)`, y **la clave del diccionario es esa
misma cadena castellana, literal**:

```qml
label: I18n.tr("Brillo")
hint: I18n.tr("El mismo brillo que las teclas de función.")
```

No hay claves simbólicas (`settings.brightness.label`) a propósito: así el
código se lee solo, un `grep` de la frase que ves en pantalla te lleva a su
sitio, y **lo que falte en el diccionario sale en castellano en vez de salir
vacío**. Un fallo visible, pero inofensivo.

Los huecos son `{0}`, `{1}` y `{2}`, y las frases **no se concatenan**:

```qml
// mal: en otro idioma las piezas van en otro orden
text: "Quedan " + n + " minutos"
// bien
text: I18n.tr("Quedan {0} minutos", n)
```

`tr()` acepta hasta tres argumentos y los sustituye en el sitio, así que la
traducción puede poner los huecos en el orden que le pida su idioma.

**Por qué no `qsTr()` con ficheros `.ts`**: el flujo de Qt Linguist obliga a
compilar los `.ts` a `.qm` y a reiniciar la aplicación para cambiar de idioma.
Aquí `I18n.lang` es una propiedad, y como cada `text: I18n.tr(...)` es un
binding que depende de ella, cambiar de idioma repinta la interfaz entera en el
sitio, sin reiniciar nada.

**Y por qué un `.js` y no otro singleton QML**: se probó con un
`Translations.qml` que exponía `readonly property var en: ({…})` con las 402
entradas dentro y en caliente llegaba **sin definir** —
`TypeError: Cannot read property '...' of undefined`; antes de eso, sin un
`import` explícito, `ReferenceError: Translations is not defined`. Un fichero JS
con `.pragma library`, importado explícitamente
(`import "translations-en.js" as Dict`), funciona, aguanta el tamaño y además se
diffea mejor. No lo devuelvas a QML.

### Elegir idioma

`Config.language` vale `"es"` (por defecto) o `"en"`, y se guarda en
`~/.config/quickshell-rice.json` con el resto de los ajustes. Se elige de tres
maneras:

- al instalar, con `./install.sh --lang en` (sin la opción, el instalador
  pregunta);
- en caliente, en **Ajustes › Apariencia › Idioma del shell** — el cambio es
  inmediato y no toca el idioma del sistema ni el de las aplicaciones, solo el
  del shell;
- a mano, escribiendo `"language": "en"` en el JSON.

`ShellState.loc` sigue a `Config.language` (`es_ES` / `en_GB`), así que las
fechas y los números del shell cambian de formato con él. `Config.reset()` no
toca `language` a propósito: restablecer los valores de fábrica no debería
dejarte el escritorio en un idioma que no lees.

### Añadir un idioma

1. Añade el código y el rótulo a la lista `languages` de `I18n.qml`. **El rótulo
   va en su propio idioma** (`Français`, no `Francés`): quien abra el shell en
   un idioma que no lee tiene que poder encontrar el suyo en la lista.
2. Copia `translations-en.js` en `translations-XX.js` (mismo `.pragma library`,
   las mismas claves castellanas) y traduce los valores.
3. Impórtalo en `I18n.qml` al lado del otro
   (`import "translations-fr.js" as DictFr`) y haz que `tr()` lo mire. Hoy la
   línea es binaria (`root.english && Dict.en[s]`); con tres idiomas se resuelve
   eligiendo el diccionario por código y dejando el castellano como respaldo
   cuando no hay entrada.
4. Si el idioma escribe las fechas de otra manera, traduce también las claves de
   formato (`d 'de' MMMM`, `d 'de' MMMM 'de' yyyy`) y añade su locale a
   `ShellState.loc`.
5. Pásale `tools/i18n-check.py` y añade el código nuevo a `install.sh`
   (`--lang`), que hoy solo acepta `es` y `en`.

### Los atajos de Hyprland

`SettingsShortcuts.qml` lee las líneas `bind =` de
`~/.config/hypr/hyprland.conf` y **pasa el comentario de cada una por
`I18n.tr(comment)`**. O sea que el comentario castellano del `.conf` es la clave
del diccionario, la lista de atajos sale en inglés y **la configuración de
Hyprland no hay que tocarla**: es de diego y sigue en castellano a propósito.

Esas claves no aparecen nunca como `I18n.tr("literal")` en ningún `.qml`, así
que `tools/i18n-check.py` las recoge aparte leyendo el propio `hyprland.conf`;
si no, las daría por entradas muertas y alguien acabaría borrándolas.

### El repaso

```bash
cd ~/.config/quickshell && python3 tools/i18n-check.py
```

Comprueba las cuatro formas de romper esto: cadenas envueltas que no están en el
diccionario (saldrían en castellano), entradas del diccionario que ya no usa
nadie, huecos `{0}` que se pierden o se inventan en la traducción, y literales
visibles (`text:`, `label:`, `hint:`…) que siguen sin envolver. Sale 0 si está
todo bien y 1 si hay algo que mirar. Las excepciones a propósito —el título de
ventana «Ajustes», que es con el que casa la `windowrule`, o los rótulos de
idioma— van listadas dentro del script con su motivo.

## Salud de batería

La fila de porcentaje rápida sigue saliendo de `sysstats.sh`; los detalles de
Ajustes salen de `Quickshell.Services.UPower`, que ya entrega unidades estables:
salud (% de capacidad de fábrica), carga completa actual (Wh), consumo (W) y
tiempo hasta vaciarse o llenarse. La capacidad de diseño se deriva de salud +
capacidad actual. El único dato que UPower no expone en QML, los ciclos, se lee
de `/sys/class/power_supply/<batería>/cycle_count`; `<batería>` viene de
`UPowerDevice.nativePath`, no de suponer `BAT0` o `BAT1`. Si el firmware no
publica un campo, su fila se oculta o dice «calculando», sin inventar un cero.

## Ajustes rápidos
En `TopShell.qml`: `notchColor`, `sideMargin`, `flare`, `roundMax`, y
`scrimAlpha` (0 por defecto = barra 100 % transparente; súbelo a ~0.35 si con
fondos muy claros no lees bien los glifos).
En `ShellState.qml`: `bandH` y los tamaños de cada modo (`notchW` / `notchH`).

## La burbuja satélite

Un cuerpo pequeño que asoma **por detrás del borde derecho del notch** mientras
hay algo corriendo de fondo. Vive en `TopShell.qml` (dibujo) y `ShellState.qml`
(`bubble*`, datos y prioridad).

**Por qué un satélite y no otra cara del notch**: el notch en reposo mide
exactamente la banda reservada y no puede crecer solo — esa es la regla que hace
que no tape ninguna ventana nunca. Una cuenta atrás dura minutos, así que no cabe
ahí sin romperla. Un cuerpo aparte sí: nace detrás del borde, se queda **dentro**
de la banda (28 de 32 px) y el notch sigue midiendo lo mismo.

Es un **hueco genérico**, no un temporizador. Hoy lo llenan dos cosas y meter una
tercera es una línea más en `bubbleKind`:

| quién | qué enseña |
|---|---|
| temporizador | anillo que se vacía + `mm:ss` al pasar el ratón |
| `pacman --refresh` | arco girando (indeterminado) + "Sincronizando" |

Tres detalles que no se ven leyendo el código:

1. **Se declara ANTES que el notch**, o sea que el notch la pinta encima. No es
   un descuido: cuando el notch crece (un OSD, un panel, el mapa de escritorios)
   se traga la burbuja, y al encoger vuelve a asomar. Es la metáfora entera —
   algo que estaba detrás — y sale gratis, sin una línea que esconda nada.
2. **Su sitio se mide contra el notch EN REPOSO.** Si siguiera al borde vivo,
   abrir el mapa de escritorios (1396 px) la mandaría volando al otro extremo de
   la pantalla y de vuelta.
3. **En la máscara va por coordenadas, no por `item:`**, para poder medir CERO
   cuando no hay nada. Con `item:` la zona de ratón seguiría ahí invisible y te
   comerías los clics en un trozo de escritorio al lado del notch.

Clic pausa/reanuda · clic derecho cancela · al sonar se queda en rojo con
"¡Tiempo!" hasta que la descartas. El aviso de fin es un `notify-send` normal: como
**nosotros somos el servidor de notificaciones**, da la vuelta y sale en nuestro
propio notch, y de paso queda en el historial del centro de control.

### El temporizador se arranca desde el lanzador

Escribe una duración (`10m`, `25 min`, `1h`, `1h30`, `90s`) y la **misma fila
destacada de la calculadora** propone la cuenta atrás; Enter la arranca. Va ahí y
no en un atajo nuevo porque el lanzador ya es donde se escriben cosas que no son
nombres de aplicación — la calculadora abrió esa puerta.

**Exige unidad a propósito**: un `5` suelto es una búsqueda. Si el lanzador
propusiera una cuenta atrás con cualquier número se metería en medio de todas las
búsquedas que empiezan por cifra, que es la misma razón por la que la calculadora
tiene lista blanca y no salta con `7zip`.

## Te están capturando la pantalla

Punto rojo que late en la barra derecha (donde viven las excepciones) mientras
algo captura el monitor. Sale del suceso `screencast` de Hyprland, sin nada de
C++.

**Dos cosas medidas en este equipo que hacen que no sea trivial:**

```
grim (pantallazo)   → screencast 1,monitor  …  0,monitor
grabación de zona   → screencast 1,region
TU PROPIO overview  → screencast 1,window   (una por ventana)
```

Por eso solo cuentan `monitor` y `region`: contando todo, el aviso de "te están
grabando" se encendería **cada vez que pulsas Super+Tab**. Y por eso hay 1,5 s de
espera antes de encenderlo: un pantallazo con `grim` abre y cierra la captura en
menos de medio segundo, y un fogonazo rojo justo cuando haces una captura es
exactamente lo que no quieres.

## El lanzador es el centro de comandos

`LauncherPanel.qml` ya no busca solo aplicaciones. **El primer carácter decide
qué se busca**:

| prefijo | modo | qué hace Enter |
|---|---|---|
| *(nada)* | aplicaciones · calculadora · temporizador · favoritos | lanza la app |
| `#` | historial del portapapeles (texto **e imágenes**) | lo deja en el portapapeles |
| `>` | acciones del sistema | la ejecuta |
| `@` | ventanas abiertas | salta a ella (cambiando de escritorio si hace falta) |

**El prefijo se consume**: al escribirlo desaparece del campo y en su sitio sale
una etiqueta con el nombre del modo. Si se quedara escrito habría dos cosas
diciendo lo mismo y el campo empezaría por un carácter que no es parte de lo que
buscas. Se sale con **un borrado sobre el campo vacío**, que es donde la mano va
sola cuando quiere deshacer.

Con el campo vacío en modo aplicaciones, los tres prefijos salen escritos a la
derecha, donde antes iba el contador de resultados. El contador decía «hay 49
aplicaciones», que no es un dato que nadie necesite; en cuanto escribes una
letra vuelve, y ahí sí significa algo.

**Por qué prefijos y no cuatro atajos.** Los atajos hay que recordarlos con los
dedos y cada uno abre una ventana que se aprende por separado. Un prefijo se
descubre solo, se corrige con un borrado, y sobre todo: la costumbre sigue
siendo una sola, `Super+R` y escribir. Es además la puerta que abrió la
calculadora — escribir `2+2` ya era escribir algo que no es un nombre de
aplicación—, así que la calculadora y el temporizador siguen **sin prefijo**: no
son un modo, son lo que pasa cuando lo que escribes resulta ser una cuenta o una
duración.

**Con esto se retiran los dos últimos menús de rofi del rice.** No queda ninguno.

### `#` portapapeles

Los datos los sirve `scripts/cliphist-tool.sh` (`list` / `copy <id>` /
`delete <id>`), que sustituye al par `~/.config/rofi/cliphist-menu.sh` +
`cliphist-paste.sh`. Aquí el QML **no decodifica nada**: una entrada de imagen es
un binario, y meter binarios en una cadena de QML es pedir que algo se rompa en
silencio. El script entrega TSV con `id`, tipo, ruta de miniatura y etiqueta.

- Las miniaturas se cachean por `id` en `~/.cache/cliphist/thumbs/` (el `id` de
  cliphist no se reutiliza, así que una miniatura cacheada no puede acabar
  apuntando a otra imagen).
- Se sirven las **150** entradas más recientes, con vista previa de **200**
  caracteres. Ese ancho es el límite real de la búsqueda: solo se puede encontrar
  lo que está en la vista previa.
- **`Supr` borra la entrada sin cerrar el panel** (o clic derecho, o la papelera
  de la fila señalada). Rofi no podía: elegir cerraba el menú. Limpiar el
  historial es justo la tarea en la que quieres seguir mirándolo.
- El script **no llama a `grep`, `sed` ni `tr`**. Con un fork por línea y campo
  tardaba 0,56 s con las miniaturas ya cacheadas, y eso se ejecuta cada vez que
  abres el modo; con coincidencia de patrones de bash baja a **0,06 s**. Tampoco
  usa `cliphist list | head`: con la tubería, `head` cierra el grifo, cliphist
  muere de SIGPIPE y el script termina en 141 por `pipefail` — un fallo de
  mentira que tarde o temprano se interpreta como uno de verdad.

### `>` acciones

La lista que había en `~/.config/hypr/scripts/menu.sh`, más lo que aquel menú no
podía ofrecer porque vivía fuera del shell: **Ajustes, mapa de escritorios, no
molestar y café**. Las que tienen equivalente nativo ya no llaman a un programa
externo: «Wifi» abría `kitty -e impala` y ahora abre `NetworkPanel`; «Apagar»
abría `wlogout` y ahora abre `PowerPanel`. Lanzar una terminal para tocar el
wifi teniendo el panel al lado era el resto de una época anterior.

También vive aquí **Modo lectura**: busca `>lectura`. No estrena atajo —`Super+D`
sigue siendo el centro de control— y también se puede conmutar en Ajustes ›
Sistema. `reading-mode.sh` captura antes el shader, animaciones, blur y sombras
reales de Hyprland; al salir restaura esos mismos valores. El shader lleva papel
cálido, tinta, grano estático y dither mínimo. Fondo, pywal y brillo quedan fuera
a propósito.

Las que se quedan dentro del shell **cambian de cara sin cerrar** (cerrar y
reabrir en el mismo instante hace parpadear el notch entero); las que salen
fuera cierran primero, porque varias congelan la pantalla o piden un recorte y
lo harían con el panel dentro de la foto.

### `@` ventanas

Se lee de Hyprland y no del `ToplevelManager` de Wayland porque hace falta el
**escritorio** de cada ventana, y eso solo lo sabe el compositor. Cada fila
enseña icono, título, clase y una pastilla con el escritorio (resaltada si es el
activo): saltar aquí puede cambiarte de escritorio y conviene saberlo antes.

Dos trampas heredadas del overview, por si hay que volver: `address` viene **sin
el `0x`** y los despachadores lo exigen (sin el prefijo `focus` contesta «no
window» en silencio), y el salto **cierra primero y pide el foco 60 ms después**,
porque al cerrar el panel Hyprland devuelve el foco a la ventana anterior y sin
ese hueco no está garantizado quién llega el último.

`winTick` existe porque `Hyprland.toplevels.values` avisa cuando una ventana nace
o muere pero **no** cuando cambia de título: sin él, buscar «github» no
encontraría la pestaña que acabas de abrir en un Chrome que ya estaba.

### Quién elige el delegado

Lo eligen **los datos**, no el modo (`root.listKind` mira el `kind` de la primera
fila). No es teórico: `mode` es un enlace declarado arriba del fichero y los
resultados los recarga un `Connections` declarado más abajo, así que al cambiar
de modo Qt actualiza primero el enlace y después el manejador. En ese hueco de un
fotograma la lista se repintaba con el delegado **nuevo** y los datos **viejos**
—el delegado de ventanas recibía aplicaciones y pedía campos que no existen— y
salían cinco `TypeError` en el log por cada `@` que escribías. Preguntándoselo a
la primera fila eso no puede pasar, porque la respuesta cambia exactamente a la
vez que los datos.

## Favoritos del lanzador

Fila fijada de iconos arriba del todo, **solo con el campo vacío** (y solo en
modo aplicaciones): en cuanto
escribes manda la búsqueda y la fila desaparece para no quitarle sitio a los
resultados.

| | |
|---|---|
| fijar / soltar | la **estrella** de cada fila, **clic derecho** sobre ella, o **Ctrl+D** sobre la seleccionada |
| lanzar | clic en el icono, o **Ctrl+1..9** |
| reordenar | **arrastrar** el icono; la marca vertical enseña dónde va a caer |
| quitar | clic derecho sobre el icono fijado |

Se guardan en `favApps` de `~/.config/quickshell-rice.json`, **por `id` de la
entrada `.desktop`** y en orden. Por `id` y no por nombre porque el `id` es
constante: renombrar la app o cambiar el idioma del escritorio no debe perderte
el favorito. Un `id` que ya no existe (app desinstalada) se ignora al resolver,
así que la lista se limpia sola y sin avisar.

Que la lista tenga ORDEN y no sea un conjunto es lo que hace que `Ctrl+1..9`
signifique algo: la posición se convierte en un atajo que se aprende con los
dedos, y por eso se puede reordenar.

**Trampa del arrastre**, si alguna vez hay que tocarlo: el orden que se pinta
(`favShown` en `LauncherPanel.qml`) es propio del panel, no de `Config`.
Mientras arrastras, lo guardado no cambia. Si se escribiera el fichero a cada
píxel, la lista se repintaría entera y los delegados se recrearían justo debajo
del dedo, matando el gesto a la mitad. Solo se confirma al soltar, y `favDrag`
se limpia **antes** de tocar `Config` para que `syncFavs()` pueda repintar.

## Emparejar por Bluetooth

Quickshell sabe emparejar (`Bluetooth.pair()`) y sabe decirte que está en ello,
pero **no sabe contestar** a lo que BlueZ pregunta a mitad del emparejamiento:

```
"¿coincide el código 418293 con el que ves en el aparato?"
"teclea 418293 en el teclado y pulsa Enter"
```

Eso no son señales: BlueZ llama a métodos de un objeto D-Bus que el escritorio
tiene que **exportar**, y desde QML no se puede exportar un objeto D-Bus — la
API de Bluetooth de Quickshell no tiene ningún callback de agente. Sin nada que
conteste, los auriculares emparejan igual (no preguntan nada) pero **un teclado
o un mando falla en silencio**: sin error, sin aviso, simplemente no empareja.

`scripts/bt-agent.py` es ese objeto, supervisado por
`~/.config/systemd/user/bt-agent.service`.

```
BlueZ  --(bus del SISTEMA)-->  Agent1  --> qs ipc call notch btask …
                                  ^                        |
                                  |                  el notch pregunta
                                  |                        |
    org.quickshell.BtAgent1.Reply(b) <-- busctl --user <-- tu clic
```

Dos buses a propósito: BlueZ vive en el del sistema y llama de vuelta al objeto
que registremos ahí; el notch vive en el de sesión y no debe poder tocar nada
del sistema. El único puente es ese proceso.

**La cara del notch va por delante hasta de un panel abierto.** Es la única que
se salta esa regla, y no es capricho: no es un aviso, es una pregunta con
caducidad al otro lado de la cual hay un aparato esperando. Detrás del panel que
tuvieras abierto, el emparejamiento vencería sin que llegaras a verla.

Dos formas: **`confirm`/`authorize`** traen dos botones (Sí / No), y
**`display`** no trae ninguno — BlueZ inventa el código y lo tecleas tú en el
teclado; la barrita de progreso sube con cada tecla, y es la única señal de que
el teclado está hablando de verdad con el equipo.

Si nadie contesta en 45 s se rechaza solo. Sin eso, un aviso sin atender dejaría
la cara clavada por delante de todo. Por lo mismo el agente manda `btclear` al
morir: parar el servicio con una pregunta en pantalla la quita.

**Lo que este agente NO hace**, dicho en voz alta en vez de fallar callando:
`RequestPasskey` y `RequestPinCode` (los casos en que hay que teclear *aquí* un
número que enseña el aparato) se rechazan con un aviso visible, porque harían
falta un campo de texto con foco. No es el caso de teclados ni de mandos.

**Ojo con blueman.** Hay un `~/.config/autostart/blueman.desktop`, pero Hyprland
no procesa el autostart XDG, así que no corre. Si algún día corriera,
`blueman-applet` registraría su propio agente y se llevaría el de por defecto.

## IPC y atajos
```
qs ipc call notch bright up|down          # cambia el brillo Y enseña el OSD, sin lag
qs ipc call notch osd volume|brightness|track|charge|ws|toast|notif
qs ipc call notch timer 10m|1h30|90s|stop # temporizador -> burbuja satélite
qs ipc call notch toggle
```
`Super+Tab` mapa de escritorios · `Super+N` alterna **notch ↔ isla** (sin aviso de texto: que la forma cambie ya
es la confirmación) · `Super+A` (o `Super+,`) Ajustes · `Super+R` lanzador · `Super+D` centro de control · `Super+Shift+D` estado del equipo · `Super+Shift+E` o la tecla de
encendido → menú de encendido · `Super+W` ocultar/mostrar todo · `Super+G`
recarga (`reload.sh`).

`Super+Shift+V` abre el lanzador ya en `#` (portapapeles) y `Super+Alt+Space` en
`>` (acciones). Tienen atajo propio los dos modos que **ya lo tenían cuando eran
menús de rofi**: cambiar por dentro cómo se pintan no es motivo para quitarle a
nadie una tecla que ya tiene aprendida. Las ventanas no estrenan atajo, se llega
escribiendo `@`.

```
qs ipc call notch launcher     # abrir/cerrar el lanzador (modo aplicaciones)
qs ipc call notch open apps|clip|cmd|win   # abrirlo YA en un modo
qs ipc call notch clipboard    # atajo de `open clip`
qs ipc call notch overview     # abrir/cerrar el mapa de escritorios
qs ipc call notch control      # abrir/cerrar el centro de control
qs ipc call notch system       # abrir/cerrar el estado del equipo
qs ipc call notch power        # abrir/cerrar el menú de encendido
qs ipc call notch network      # abrir/cerrar el selector de red
qs ipc call notch bluetooth    # abrir/cerrar el panel de bluetooth
qs ipc call notch settings     # abrir/cerrar la app de Ajustes
qs ipc call notch keys         # Ajustes ya en «Atajos» (lo que hace Super+K)
qs ipc call notch style        # alternar notch <-> isla
qs ipc call notch close        # cerrar cualquier panel
qs ipc call notch current      # qué panel está abierto (vacío si ninguno)
qs ipc call notch restore NOMBRE  # reabrir ese panel
qs ipc call notch btask confirm|display|authorize NOMBRE CODIGO TECLEADOS
qs ipc call notch btclear      # quitar la cara de emparejamiento
```
`btask`/`btclear` no son para usarlas a mano: las llama
`scripts/bt-agent.py` (ver «Emparejar por Bluetooth»). Sirven para VER la cara
sin tener un aparato delante, igual que `osd` sirve para ver los OSD sin
enchufar el cargador:
```
qs ipc call notch btask confirm "Teclado K380" 418293 -1
qs ipc call notch btask display "Teclado K380" 418293 4
```
`current` + `restore` existen para la captura de pantalla: fotografiar el
notch obliga a congelar la pantalla, congelar manda el foco fuera y eso
cancela el `HyprlandFocusGrab`, así que el panel se cierra por debajo de la
foto. `~/.config/hypr/scripts/capture-region.sh` apunta cuál era antes de
congelar y lo devuelve al terminar: hacer una captura ya no te cierra lo que
estabas mirando.

## Qué cambió fuera de este directorio
- 2026-08-19: **fuera el último menú de rofi con tecla propia**. `Super+K` ya no
  llama a `~/.config/hypr/list_keybinds.sh`: abre Ajustes directamente en
  «Atajos» (`global, quickshell:keybinds`), que es la MISMA lista leída del
  mismo `hyprland.conf` — eran dos vistas del mismo parseo y solo coincidían
  mientras nadie tocara ninguna. Se estrenan `ShellState.openSettingsAt(id)`,
  `SettingsWindow.openAt(id)`, `qs ipc call notch keys` y la acción «Atajos de
  teclado» del menú de comandos. Los siete scripts de rofi que ya no llamaba
  nadie (`list_keybinds.sh`, `hypr/scripts/menu.sh`, `hypr/wallpaper-picker.sh`,
  `rofi/cliphist-menu.sh`, `rofi/cliphist-paste.sh`,
  `rofi/scripts/network-menu.sh`, `rofi/scripts/bluetooth-menu.sh`) están en
  `~/.config/menus-rofi-retirados-20260819.tar.gz`.

  Ese mismo día, un poco después: **rofi se ha ido entero**. El único
  superviviente era `hypr/scripts/webapp-install.sh` (`Super+Ctrl+W`), dos
  preguntas de texto encadenadas que el lanzador del notch no sabe hacer — y que
  no hacía falta que aprendiera, porque `~/.local/share/webapps/` no llegó a
  existir nunca: el atajo no se usó ni una vez. Retirado él, rofi se quedaba sin
  un solo uso vivo, así que se van con él `~/.config/rofi/` (112 ficheros de
  temas), la plantilla `wal/templates/colors-rofi.rasi`, la regla de capa
  `rofi-blur` de Hyprland y el paquete en `packages/pacman.txt`. Y por el mismo
  motivo `wlogout`, al que sustituyó `PowerPanel.qml`. Todo en
  `~/.config/rofi-wlogout-retirados-20260819.tar.gz` y
  `~/.config/webapp-install-retirado-20260819.tar.gz`.

  Lo que quedaba no era código muerto y ya está: era una descripción falsa del
  escritorio en un repo a punto de publicarse.
- 2026-08-09: `~/.config/hypr/shaders/reading-mode.glsl` y
  `~/.config/hypr/scripts/reading-mode.sh`. El estado temporal reversible vive
  en `$XDG_RUNTIME_DIR/quickshell-rice/reading-mode.json`, así que no se persiste
  una preferencia que ya no describa al compositor. También se añadió
  `~/.config/hypr/scripts/wifi-enterprise.sh`, puente mínimo al editor de
  NetworkManager: recibe acción + SSID, nunca identidad ni contraseña.
- `hyprland.conf`: `exec-once = waybar` comentado; `swayosd-server` retirado;
  volumen → `wpctl` (el notch lo ve al instante por Pipewire), brillo →
  `qs ipc call notch bright`; `Super+R` ya no lanza rofi, abre el lanzador del
  notch.
- 2026-08-08: **fuera los dos últimos menús de rofi**. `Super+Shift+V` ya no
  llama a `~/.config/rofi/cliphist-paste.sh` y `Super+Alt+Space` ya no llama a
  `~/.config/hypr/scripts/menu.sh`: los dos abren el lanzador del notch en su
  modo (`global, quickshell:clipboard` y `quickshell:actions`), en
  `hyprland.lua` y en el respaldo `hyprland.conf`. Los datos del portapapeles
  siguen saliendo de cliphist (`wl-paste --watch` en `exec-once`), solo cambia
  quién los pinta. Los tres scripts de rofi se dejaron en disco por si había que
  volver; el 2026-08-19 se archivaron (ver arriba).
- `set-wallpaper.sh`: ya no recarga waybar ni swayosd.
- 2026-08-05: `exec-once = qs` sustituido por `~/.config/systemd/user/`
  `quickshell.service` (Restart=on-failure). Motivo: el 2026-08-05 qs murio
  con SIGSEGV y nadie lo levanto; ademas al morir solto el nombre D-Bus de
  las notificaciones y se lo quedo swaync. `qs --no-duplicate` evita que un
  lanzamiento manual cree una segunda barra.
- 2026-08-05: `swaync` enmascarado y su recarga muerta quitada de
  `set-wallpaper.sh` (linea `swaync-client -rs`).
- 2026-08-07: la notificación de una captura se puede PULSAR para editarla.
  `notify-shot.sh` la manda con una acción "Editar" (`notify-send -A`, que
  implica `--wait`: por eso va al fondo y con `timeout 600`, porque nuestro
  servidor no caduca las notificaciones solo). Pulsar el aviso en el notch o
  su fila en el centro de control invoca la acción y abre la foto en satty
  (`screenshot-edit.sh`, guarda la anotada aparte). El aviso del notch ahora
  invoca la primera acción si la notificación trae alguna, y solo abre el
  centro de control cuando no hay ninguna — o sea que cualquier app con
  acciones se beneficia, no solo las capturas.
- 2026-08-07: capturas de región sobre pantalla CONGELADA. `Super+Shift+S` ya
  no llama a `hyprshot -m region`, sino a `screenshot-region.sh`, que se apoya
  en `capture-region.sh` (hyprpicker congela → slurp elige sobre la foto →
  `grim -g` recorta). Motivo: slurp roba el foco y el notch, el lanzador o
  cualquier menú se cerraban antes del disparo, así que era imposible
  fotografiarlos. `screenshot-annotate.sh` (satty) y `ocr.sh` usan el mismo
  camino.
- 2026-08-06: pokemon del tema. Nuevo `~/.local/bin/poke-theme` (indexa la
  paleta de cada sprite y los ordena para el tema vigente), `poke_theme_pick()`
  en `~/.zshrc` y una linea en `set-wallpaper.sh` que reordena en 2o plano al
  cambiar de fondo. Preferencia en `~/.config/poke-theme/state`.
- Copias: `~/.config/hypr/hyprland.conf.bak-notch-*`, `shell.qml.bak-notch`.

### Volver a waybar
```
cp ~/.config/hypr/hyprland.conf.bak-notch-* ~/.config/hypr/hyprland.conf
cp ~/.config/quickshell/shell.qml.bak-notch ~/.config/quickshell/shell.qml
hyprctl reload; ~/.config/quickshell/reload.sh; (waybar >/dev/null 2>&1 &)
```

## Probar sin tocar el escritorio
```
qs -p ~/.config/quickshell/TopShell.qml
```

## `~/.config/quickshell-old/`
Intentos superados, fuera del directorio de carga: `Bar.qml` (barra flotante
original), `MenuBar.qml` + `Notch.qml` + `NotchState.qml` + `NotchBar.qml` (la
versión de dos ventanas, que se veía como dos piezas distintas), `Osd.qml` y
`Notifications.qml` (los popups sueltos, ya cubiertos por el modo `notif`) y
`Sidebar.qml` (el dashboard de `Super+N`, absorbido por el centro de control;
ese atajo pasó a alternar notch/isla).
También hubo una versión con franja negra maciza de la que colgaba el notch:
descartada, el bulto sobresalía de la banda reservada y estorbaba encima de las
ventanas.

### Volver a swaync
swaync esta ENMASCARADO desde el 2026-08-05: se activaba solo por D-Bus cada vez
que Quickshell no tenia el nombre `org.freedesktop.Notifications` (arranque,
recarga o crash) y luego no lo soltaba nunca, dejando muertas las
notificaciones del notch. Para volver a el:
```
systemctl --user unmask swaync && systemctl --user enable --now swaync
```
…y quitar el bloque `NotificationServer` de `ShellState.qml` (no puede haber dos
dueños de `org.freedesktop.Notifications`).

## Cosas sabidas
- **Systray tras reiniciar la shell**: los `StatusNotifierItem` se registran
  contra el watcher del momento. Si matas Quickshell, las apps ya abiertas
  (p. ej. `rustdesk --tray`) no vuelven a la bandeja hasta reiniciarlas. En un
  login normal no pasa.
- **Blur**: la sintaxis nueva de `layerrule` SI se conoce y funciona
  (`layerrule = blur on, match:namespace ^(rofi)$`, activa en `hyprland.conf`).
  No se aplica a la barra ni al notch a proposito: son opacos, asi que el
  desenfoque seria una mancha en vez de un material. rofi es lo unico con
  transparencia real y por eso es lo unico que lo lleva.
- **Mic mute** no tiene OSD en el notch.

## En un equipo que no es este portátil

Todo esto se diseñó sobre un portátil Intel con UNA pantalla, batería, panel con
brillo y wifi. Al estrenarlo en una torre (dos monitores DisplayPort, sin
batería, sin panel interno, por cable) aparecieron los supuestos que se habían
colado. Lo que hay ahora:

**Dos pantallas.** `TopShell` ya instanciaba una superficie por monitor con
`Variants` sobre `Quickshell.screens`, y `win.primary` decide cuál es la de
verdad comparando con `ShellState.focusedMon`. La barra sale en todas; el notch
también, pero las que no tienen el foco se quedan en su cara de reposo y no
despliegan paneles, no piden teclado y no arman el `HyprlandFocusGrab`.

Lo que faltaba era el indicador de escritorio: pintaba la lista ENTERA y marcaba
el activo con `Hyprland.focusedWorkspace`, que es global. En la pantalla sin foco
eso es una píldora señalando un escritorio que está en la otra. Ahora cada barra
filtra por `ws.monitor.name` y marca el `activeWorkspace` de SU monitor
(`win.hlMon`, buscado por nombre en `Hyprland.monitors` — no con `monitorFor()`,
que es un método y no reevalúa el binding al enchufar o quitar una salida). Si
todavía no se sabe de quién es cada escritorio, se pintan todos: con una sola
pantalla el resultado es idéntico al de antes.

Ojo con lo que NO es un fallo: los escritorios no se duplican por monitor, la
numeración es única. Super+2 desde la pantalla izquierda te lleva el foco a
donde viva el 2. Es Hyprland de serie; en `hyprland.lua` hay un comentario con
cómo fijarlos por monitor si algún día se quiere.

El ancho del notch (`notchW`) se recorta a la pantalla menos 48 px por lado. Los
anchos por cara son números fijos elegidos sobre 1920 px y ahí sobra sitio, pero
en una salida más estrecha se saldrían por los dos costados.

**Sin batería.** `sysstats.sh` devuelve `bat = -1` y todo lo que pinta carga
exige `batt >= 0`, así que el polo derecho del notch, la cara de `charge` y las
filas de Ajustes desaparecen sin dejar hueco (van por `anchors`, no por layout).
La fila "Batería" de Ajustes ya no se queda presidiendo un bloque vacío con un
"sin batería". Y `ac` pasa a 1 cuando no hay batería: el respaldo `ac = 0`
significa literalmente "con batería", que en una torre enchufada es mentira.

**Sin brillo.** El detalle que muerde: `brightnessctl` SIN `-c` recorre las
clases en orden (`backlight`, luego `leds`) y se queda con la primera que tenga
algo. En una máquina sin `/sys/class/backlight` eso significa acabar encendiendo
y apagando el LED de bloq-mayús y enseñar su 0/100 como si fuera el brillo de la
pantalla. Por eso las tres llamadas (`sysstats.sh`, `stepBrightness`,
`setBrightness`) y las de `hypridle.d/normal.conf` llevan `-c backlight`. Sin
panel no hay lectura, `bright` se queda en -1 y el slider del centro de control
no se dibuja.

**Sin tapa.** No hay ninguna acción de cierre de tapa configurada, ni en
`hyprland.lua` ni en hypridle. No había nada que degradar.

**Sin wifi.** `ShellState.hasWifi` mira el DISPOSITIVO, no `wifiEnabled`:
NetworkManager reporta la radio como deshabilitada también cuando sencillamente
no existe, y el panel no sabía distinguir "apagado" de "no hay". Sin adaptador,
el interruptor de Wi-Fi desaparece (del panel y de Ajustes) y la lista vacía dice
que el equipo va por cable en vez de quedarse en un "Buscando redes…" eterno.

**Temperatura.** La búsqueda por `thermal_zone` solo conocía `x86_pkg_temp` y
`TCPU`, que son de este Intel. En un Ryzen el sensor es `k10temp` y vive en
hwmon, así que la tarjeta de temperatura quedaba muerta para siempre. Hay un
respaldo por hwmon (`k10temp`/`zenpower`/`coretemp`), resuelto una sola vez al
arrancar el script.

**Lo que sigue clavado a este panel** y no se ha tocado porque es una decisión de
diseño, no un fallo: los tamaños de fuente de `Appearance.qml` van en píxeles
fijos y `hyprland.lua` fija `scale = 1` para toda salida. En un 27" a 1440p o en
un 4K todo se lee pequeño. Arreglarlo de verdad es meter escalado por DPI en
todo el shell, y eso hay que verlo con los ojos en la pantalla de destino.
