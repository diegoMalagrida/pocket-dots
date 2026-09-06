-- ###########################################################################
--  CONFIG DE HYPRLAND EN LUA  (Hyprland 0.56+)
--
--  Traducida desde hyprland.conf el 2026-08-05. La .conf original se queda
--  al lado como respaldo: si borras o renombras ESTE fichero, Hyprland vuelve
--  a leerla sola ("Lua config not found, using legacy config at ...").
--  Las dos no conviven: si existe hyprland.lua, manda hyprland.lua.
--
--  EL MOTIVO DEL CAMBIO: los muelles. Una bezier no sabe donde esta, solo
--  cuanto le queda, asi que si le cambias el destino a medio vuelo tiene que
--  cortar y empezar de cero -- eso es la sensacion de goma al encadenar dos
--  Super+flecha seguidas. Un muelle tiene estado (posicion y velocidad) y
--  continua desde donde iba. En Hyprland eso SOLO existe desde la config Lua.
--  Ver ~/.config/motion-language.md, seccion "Los muelles".
--
--  Si algo falla al cargar, Hyprland entra en modo emergencia y deja vivo
--  SUPER+Q para abrir un terminal. No te quedas fuera.
-- ###########################################################################


------------------
---- MONITORES ----
------------------

-- La regla COMODIN (output = "") vale para cualquier salida, asi que enchufar
-- un segundo monitor no necesita tocar nada: 'preferred' coge el modo nativo y
-- 'auto' lo coloca a la derecha del anterior, en el orden en que aparecen. Esto
-- es a proposito y NO se sustituye por nombres a fuego: 'eDP-1' en el portatil
-- y 'DP-4'/'DP-6' en la torre son la misma config, y una lista de nombres
-- concretos solo funcionaria en la maquina donde se escribio.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Si en algun equipo hace falta afinar (dos pantallas de distinto tamano que
-- quieres alineadas por abajo, una 4K que a escala 1 se ve minuscula, o el
-- orden izquierda/derecha al reves), la forma es anadir reglas CON NOMBRE
-- DEBAJO de la comodin: la ultima que encaja es la que manda, asi que la de
-- arriba sigue cubriendo cualquier salida que no menciones.
--
--   hl.monitor({ output = "DP-4", mode = "preferred", position = "0x0",    scale = 1 })
--   hl.monitor({ output = "DP-6", mode = "preferred", position = "2560x0", scale = 1 })
--
-- Los nombres salen de `hyprctl monitors`. La posicion es la esquina superior
-- izquierda en pixeles YA ESCALADOS, o sea que si la de la izquierda mide
-- 2560 de ancho a escala 1, la siguiente empieza en 2560.


---------------------
---- MIS PROGRAMAS ----
---------------------

local terminal    = "kitty"
local fileManager = "nautilus"


-------------------
---- AUTOSTART ----
-------------------

-- UWSM exporta el entorno de sesion a D-Bus y systemd.
-- Quickshell (barra + notch) lo supervisa quickshell.service: si peta,
-- systemd lo levanta. Hypridle y el agente PolicyKit quedan supervisados por
-- sus servicios de usuario. Waybar esta sustituida por MenuBar.qml + Notch.qml.
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/awww-start.sh")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")   -- portapapeles (texto)
    hl.exec_cmd("wl-paste --type image --watch cliphist store")  -- portapapeles (imagenes)
    -- Shake to find (como macOS): agitar el raton agranda el cursor. El
    -- script carga el plugin dynamic-cursors pineado a esta version de
    -- Hyprland y lo deja SOLO con el shake (mode none); si Hyprland se
    -- actualizo y el .so no casa, se recompila solo y avisa.
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/dynamic-cursors.sh")
end)


-------------------------------
---- VARIABLES DE ENTORNO ----
-------------------------------

hl.env("XCURSOR_THEME",   "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE",    "19")
hl.env("HYPRCURSOR_THEME","Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "19")


-----------------------------
---- COLORES DE PYWAL ----
-----------------------------

-- pywal escribe ~/.cache/wal/colors-hyprland.lua desde la plantilla
-- ~/.config/wal/templates/colors-hyprland.lua (gemela de la .conf de siempre,
-- que se sigue generando por si vuelves a la config legacy).
-- pcall: si el fichero no existe todavia -- primer arranque, cache limpiada --
-- la config NO revienta, se queda con estos colores de reserva.
local wal = {
    active_border   = { "rgb(394aad)", "rgb(a15bc8)" },
    active_angle    = 45,
    inactive_border = "rgb(648a91)",
    shadow_color    = "rgba(000000ee)",
    background      = "rgb(000000)",
}
do
    local ok, loaded = pcall(dofile, os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua")
    if ok and type(loaded) == "table" then
        for k, v in pairs(loaded) do wal[k] = v end
    end
end


-----------------------
---- ASPECTO ----
-----------------------

hl.config({
    general = {
        -- Ley 8 -- un solo hueco en la capa de contenido. Entre dos ventanas
        -- quedan 6 px (3 + 3) y hasta el borde de la pantalla, otros 6: EL
        -- MISMO hueco. Antes eran 6 y 5. Un pixel de desajuste no se ve, pero
        -- se siente.
        gaps_in  = 3,
        gaps_out = 6,

        -- Ley 2 -- sin borde, a proposito: el foco se marca con luz, no con
        -- contorno. Si algun dia quieres bordes: sube esto a 2 y ya vienen
        -- tematizados desde pywal (arriba).
        border_size = 0,

        col = {
            active_border   = { colors = wal.active_border, angle = wal.active_angle },
            inactive_border = wal.inactive_border,
        },

        resize_on_border = true,
        allow_tearing    = true,
        layout           = "dwindle",
    },

    decoration = {
        -- Ley 1 -- la geometria dice de quien es la capa. Las ventanas van
        -- RECTAS (esto es tuyo y esta anclado a la rejilla); lo redondo es del
        -- shell y flota por encima. No redondear esto "por coherencia": la
        -- coherencia la da el movimiento, no la forma.
        rounding       = 0,
        rounding_power = 0,  -- irrelevante con rounding = 0, pero se respeta el valor que tenias

        -- Ley 2 -- el foco se marca con luz. La enfocada esta PLENAMENTE
        -- presente; las demas se hunden. dim_inactive oscurece en vez de
        -- transparentar, que es la forma limpia de que algo retroceda:
        -- transparentar deja el fondo colandose entre letras.
        active_opacity   = 1.0,
        inactive_opacity = 0.90,
        dim_inactive     = true,
        dim_strength     = 0.35,
        dim_special      = 0.5,

        -- La sombra dice "esto flota". Las ventanas en mosaico estan pegadas a
        -- la rejilla y no la llevan (window_rule mas abajo); las flotantes y
        -- los dialogos si. Es informacion sobre el plano, no adorno.
        shadow = {
            enabled      = true,
            range        = 28,
            render_power = 4,
            color        = wal.shadow_color,
        },

        -- A size 3 / passes 1 el desenfoque no se veia. OJO: esto NO lo paga
        -- solo kitty (0.95 de opacidad). Con inactive_opacity = 0.90, TODA
        -- ventana sin foco tiene alpha < 1 y Hyprland le aplica la cadena de
        -- blur completa; en un mosaico de 2+ ventanas siempre hay media
        -- pantalla desenfocandose. El caso caro: slide de escritorios + motion
        -- blur + este blur, todo a la vez.
        -- SI NOTAS TIRONES: vuelve a size = 3 / passes = 1.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 2,
            noise             = 0.01,
            vibrancy          = 0.1696,
            vibrancy_darkness = 0.2,
            popups            = true,
        },

        -- Ley 5 -- lo que ATRAVIESA la pantalla deja rastro. Hyprland 0.56
        -- desenfoca la ventana en la direccion en la que se mueve, y solo
        -- mientras dura la animacion. Es la misma idea que las curvas de abajo,
        -- pero aplicada al pixel en vez de al tiempo.
        --
        -- No pelea con el redondeo porque aqui rounding = 0 (ley 1). En un rice
        -- con esquinas redondas si: los dos shaders se excluyen dentro de
        -- Hyprland (USE_ROUNDING && !USE_MOTION_BLUR), asi que las esquinas
        -- saldrian rectas justo mientras la ventana viaja.
        --
        -- Tampoco se paga al arrastrar con el raton: animate_mouse_windowdragging
        -- ya esta en false, y sin animacion no hay rastro que calcular. El coste
        -- vive solo en las transiciones, que es donde se ve.
        --
        -- 'samples' son las copias que se promedian a lo largo del trayecto: mas
        -- muestras, estela mas suave y mas cara. NO alarga la estela; eso lo
        -- decide cuanto se ha movido la ventana.
        --
        -- ESTOS SON LOS VALORES DE ARRANQUE. Manda el interruptor de
        -- Ajustes > Apariencia > Efectos; ver el final del fichero.
        motion_blur = {
            enabled = true,
            samples = 7,
        },
    },

    animations = { enabled = true },
})


-- ==========================================================================
--  MOVIMIENTO. La spec completa esta en ~/.config/motion-language.md
--  La velocidad va en DECISEGUNDOS: 1.3 = 130 ms. Son literalmente los mismos
--  cuatro numeros que los tokens de ~/.config/quickshell/Appearance.qml, para
--  que una ventana y el notch se muevan con el mismo pulso.
--
--     RESPUESTA  1.3 / 1.3    foco, zoom, color de borde
--     CONTENIDO  2.1 / 1.1    fundidos
--     PANEL      3.2 / 1.7    capas
--     FORMA      4.4 / 2.2    abrir y cerrar una ventana, y MOVERLA
--     RECORRIDO  5.0          lo que ATRAVIESA la pantalla entera
--
--  Si algo se mueve aqui y no esta en esa escala, es un bug.
-- ==========================================================================

-- Tres curvas, y ninguna mas. La cuarta del sistema ('entra', la que rebota)
-- vive SOLO en Quickshell y en las escalas: por ley 5 lo que se DESPLAZA no
-- rebota, porque pasarse de largo ensena el borde de la pantalla.
hl.curve("respuesta", { type = "bezier", points = { {0.2,  0},    {0,    1} } })
hl.curve("sale",      { type = "bezier", points = { {0.3,  0},    {1,    1} } })
hl.curve("forma",     { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("entra",     { type = "bezier", points = { {0.16, 1.3},  {0.3,  1} } })

-- 'apple': la curva de las transiciones de iOS/macOS. Arranca con un poco de
-- aceleracion en vez de salir disparada -- eso es lo que hace que parezca que
-- algo con masa se pone en marcha -- y despues frena durante casi todo el
-- recorrido.
hl.curve("apple",     { type = "bezier", points = { {0.32, 0.72}, {0,    1} } })

-- ---------------------------------------------------------------------------
--  EL MUELLE. Lo que una bezier no puede hacer.
--
--  Mover una ventana con Super+flechas es lo unico del escritorio que encadenas
--  a ratos: das dos o tres seguidas para colocarla. Con una bezier cada
--  pulsacion CORTA la anterior y arranca de cero desde donde estuviera, y eso
--  se lee como goma. El muelle conserva la velocidad que llevaba y encadena.
--
--  Los tres numeros, en fisica y no en gusto:
--    w0 = sqrt(stiffness/mass) = sqrt(130) = 11.4 rad/s  -> frecuencia propia
--    zeta = dampening / (2*sqrt(stiffness*mass)) = 23 / 22.8 = 1.01
--
--  zeta = 1.01 es criticamente amortiguado: llega lo mas rapido que se puede
--  SIN pasarse. Eso no es timidez, es la ley 5 -- si se pasara, la ventana se
--  meteria un pelin encima del vecino con el que acaba de intercambiarse, y
--  eso no es caracter, es un fallo de colocacion.
--
--  SI LO QUIERES MAS SECO: sube stiffness y sube dampening con el, manteniendo
--  dampening ~= 2*sqrt(stiffness). Pares que valen:
--      180 / 26.8  -> ~440 ms, justo en FORMA
--      250 / 31.6  -> ~370 ms, mas nervioso
--  Si bajas dampening por debajo de 2*sqrt(stiffness) empieza a rebotar, y ahi
--  te sales de la ley 5 a proposito. Pruebalo si quieres, pero sabiendo que lo
--  haces.
-- ---------------------------------------------------------------------------
hl.curve("mover", { type = "spring", stiffness = 130, dampening = 23, mass = 1 })

hl.animation({ leaf = "global", enabled = true, speed = 3.2, bezier = "forma" })

-- Ley 6 -- el movimiento tiene origen. Una ventana en mosaico se INFLA en su
-- hueco; no vuela desde un borde. El sitio ya lo habia decidido el tiling, y
-- entrar volando lo desmiente.
hl.animation({ leaf = "windows",   enabled = true, speed = 4.4, bezier = "entra", style = "popin 78%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.4, bezier = "entra", style = "popin 78%" })

-- Abrir recorre 22 puntos de escala (78->100) y cerrar solo 10 (100->90).
-- Deliberadamente asimetrico, no descuidado: abrir es un acontecimiento y
-- merece gesto; cerrar es un descarte y solo tiene que quitarse de en medio.
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "sale", style = "popin 90%" })

-- AQUI VIVE EL CAMBIO. Antes: speed 3.2 con bezier 'forma'.
-- Dos cosas a la vez: (1) el muelle, por lo de encadenar pulsaciones; y (2)
-- estaba en el escalon PANEL (3.2) cuando la tabla dice que mover una ventana
-- entera es FORMA. La ley 4 ("la frecuencia baja el peso un escalon") parecia
-- justificarlo, pero el matiz de esa misma ley es que "no puede pesar"
-- significa ARRANCAR YA, no durar poco -- y de arrancar ya se encarga el
-- muelle, que sale con toda la fuerza del resorte comprimido.
-- Con spring, 'speed' es la duracion techo; quien manda es la fisica.
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.4, spring = "mover" })

hl.animation({ leaf = "fade",       enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 1.1, bezier = "sale" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.1, bezier = "forma" })

-- El foco. Con follow_mouse = 1 cambia constantemente, asi que la atenuacion
-- tiene que ser RESPUESTA: si tardara, el escritorio entero temblaria cada vez
-- que cruzas el raton por encima de una ventana.
hl.animation({ leaf = "fadeDim", enabled = true, speed = 1.3, bezier = "respuesta" })

-- Capas (la barra y los paneles del notch, el lanzador, los avisos): se FUNDEN.
-- Nada a pantalla completa entra deslizandose, ensenaria el borde por el que
-- entra.
hl.animation({ leaf = "layers",        enabled = true, speed = 3.2, bezier = "forma", style = "fade" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3.2, bezier = "forma", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.7, bezier = "sale", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3.2, bezier = "forma" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.7, bezier = "sale" })

-- EL CAMBIO DE ESCRITORIO, ESTILO MACOS. Va entero: 'slide', no 'slidefade'.
-- Los dos escritorios estan pegados como dos habitaciones contiguas y la
-- pantalla viaja el 100 % de un lado al otro, a la vez, sin fundido ninguno.
-- El fundido es justo lo que delata que son dos imagenes superpuestas; sin el,
-- son un sitio del que te vas y otro al que llegas. (Ley 10: el problema nunca
-- fue la duracion ni la curva, era que 'slidefade 20%' RECORTABA el viaje.)
-- Sin rebote: es un desplazamiento, y pasarse dejaria una franja de fondo
-- asomando por el lado contrario justo al final.
hl.animation({ leaf = "workspaces",          enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "workspacesIn",        enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "workspacesOut",       enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "specialWorkspace",    enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })

-- Invisible (border_size = 0), pero el nodo existe: que no se quede en la
-- velocidad de fabrica y desentone el dia que enciendas los bordes.
hl.animation({ leaf = "border", enabled = true, speed = 1.3, bezier = "respuesta" })

-- borderangle / shadowangle / glowangle en 'loop' fuerzan repintado continuo a
-- 60 Hz aunque no se vean. En una Iris Xe eso es adorno que se paga en
-- fotogramas. Se quedan apagados (ley 7: nada se mueve porque si).
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "default" })
hl.animation({ leaf = "shadowangle", enabled = false, speed = 1, bezier = "default" })
hl.animation({ leaf = "glowangle",   enabled = false, speed = 1, bezier = "default" })

hl.animation({ leaf = "zoomFactor", enabled = true, speed = 1.3, bezier = "respuesta" })


--------------------------
---- ESCRITORIOS ----
--------------------------

-- Siempre tres escritorios. Hyprland destruye un escritorio en cuanto se queda
-- vacio, asi que la fila del indicador cambiaba de tamano sola: cerrabas la
-- ultima ventana del 3 y el punto desaparecia. 'persistent' hace que existan
-- aunque esten vacios.
--
-- Se hace AQUI y no pintando puntos de mas en el shell a proposito: asi los
-- tres escritorios existen de verdad, o sea que el punto es clicable y te
-- lleva a el. Un punto pintado que no corresponde a nada seria un adorno
-- mintiendo.
--
-- Son un MINIMO, no un tope: si creas el 4 aparece su punto solo, y desaparece
-- al vaciarlo. Los tres primeros se quedan siempre.
-- CON DOS PANTALLAS esto se reparte y conviene saberlo: los escritorios NO se
-- duplican por monitor, la numeracion es unica para toda la sesion. Hyprland le
-- da a cada salida uno al arrancar (la primera el 1, la segunda el 2) y coloca
-- los persistentes que sobran donde puede, asi que Super+2 desde la pantalla
-- izquierda no cambia lo que ves ahi: te lleva el FOCO a la pantalla donde vive
-- el 2. Es el comportamiento de serie de Hyprland y no un fallo.
--
-- La barra ya no miente sobre esto: cada pantalla pinta SOLO sus escritorios y
-- marca el activo de la suya (ver TopShell.qml, el filtro por ws.monitor).
--
-- Si en la torre se prefiere repartirlos a mano —digamos 1 y 2 en la principal
-- y 3 en la secundaria— se le anade el monitor a la regla, con los nombres que
-- diga `hyprctl monitors`:
--
--   hl.workspace_rule({ workspace = "1", persistent = true, monitor = "DP-4" })
--   hl.workspace_rule({ workspace = "2", persistent = true, monitor = "DP-4" })
--   hl.workspace_rule({ workspace = "3", persistent = true, monitor = "DP-6" })
--
-- No se hace aqui porque los nombres son de una maquina concreta y este fichero
-- lo comparten el portatil y la torre.
for i = 1, 3 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end


---- DISPOSICIONES ----

hl.config({
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
})

-- Cursor: hyprcursor APAGADO a proposito (2026-09-06). Al instalar el tema
-- SVG de Bibata (~/.local/share/icons/Bibata-Modern-Ice, para el nitido del
-- shake-to-find) Hyprland empezo a usarlo tambien para el cursor NORMAL y
-- Diego lo noto distinto al XCursor bitmap de siempre. Con esto el cursor
-- normal es el de toda la vida; el agrandado del shake escala ese bitmap con
-- filtrado suave (hyprcursor:nearest 0, abajo). El plugin usa el mismo
-- interruptor y tema que el compositor, asi que SVG-en-el-zoom +
-- bitmap-normal no pueden convivir: volver esto a true cambia el cursor.
hl.config({
    cursor = { enable_hyprcursor = false },
})

-- Shake to find (plugin dynamic-cursors): la FUENTE DE VERDAD de su config
-- es ESTE bloque, no el script. Tiene que vivir aqui porque cada reload
-- resetea las opciones del plugin a sus defaults (y el default es mode=tilt,
-- el cursor torciendose al moverse) -- y la cadena del wallpaper hace
-- reloads. El pcall es para el ARRANQUE: el .lua se parsea antes de que
-- dynamic-cursors.sh cargue el plugin y estas claves aun no existen; el
-- script hace un reload tras cargarlo y entonces esto aplica de verdad.
-- OJO sintaxis: dynamic_cursors con guion bajo (se traduce a
-- plugin:dynamic-cursors:*); con guion da "unknown config key".
-- Perfil "smooth" (base: dotfiles de alonso-herreros): threshold 3 detecta
-- al primer vaiven; influence 2 hace crecer el zoom CON la intensidad del
-- agitado; timeout 0 lo deshincha al soltar, como macOS. Verificado por IPC:
-- progresion 1 -> 3.6 continua, sin escalones.
pcall(function()
    hl.config({
        plugin = {
            dynamic_cursors = {
                mode = "none",
                shake = { threshold = 3.0, base = 2.0, speed = 2.0, influence = 2.0, limit = 4.0, timeout = 0 },
                -- nearest 0: nunca escalado pixelado. resolution 128: el tema
                -- SVG se rasteriza a 128 px -> nitido en todo el rango de zoom
                -- (19 px x 4 = 76). El plugin va parcheado para cargar el tema
                -- SVG aunque cursor:enable_hyprcursor este a false (el cursor
                -- NORMAL sigue siendo el XCursor bitmap de siempre).
                hyprcursor = { nearest = 0, resolution = 128 },
            },
        },
    })
end)


----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = wal.background,

        -- De caelestia: se animan los CAMBIOS DE ESTADO, no la interaccion en
        -- vivo. Arrastrar o redimensionar con el raton ya va 1:1 con tu mano,
        -- asi que animarlo no aporta nada y en una iGPU es repintado continuo
        -- atado al puntero (el camino mas caro que hay). No se pierde ni una
        -- pizca de sensacion y se libera GPU justo cuando mas falta hace.
        animate_manual_resizes       = false,
        animate_mouse_windowdragging = false,
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout    = "es",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad     = { natural_scroll = true },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Tres dedos hacia abajo: baja el calendario del mes desde el notch.
-- Misma postura de mano que el gesto de arriba, otro eje. `finish` y no
-- `update`: esto no es un arrastre continuo como el de escritorios, es una
-- orden que se ejecuta una vez, cuando levantas los dedos.
--
-- No se abre pinchando el reloj, que era lo primero que se probó: ese clic ya
-- abría el centro de control desde siempre y quitarle un gesto aprendido a
-- cambio de una función nueva es un mal trato. El calendario también tiene su
-- cuadro en el centro de control, que es la puerta que se ve.
hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = {
        finish = function() hl.dsp.global("quickshell:calendar") end,
    },
})


---------------------
---- ATAJOS ----
---------------------

local mainMod = "SUPER"

-- Capturas
-- Region: congela la pantalla antes de elegir el recorte, asi que tambien
-- fotografia lo que se cierra al perder el foco (el notch de Super+D, un menu,
-- un desplegable). Ver ~/.config/hypr/scripts/capture-region.sh.
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-region.sh"))
-- Captura COMPLETA instantanea (grim no roba foco -> si captura menus como rofi).
-- Super+Shift+P es la tecla FIABLE; Print funciona si tu teclado emite ese keysym.
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-full.sh"))
hl.bind("Print",                   hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-full.sh"))

hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"))
-- Historial del portapapeles. Ya no llama al rofi de cliphist: abre el lanzador
-- del notch directamente en su modo "#". Los datos siguen saliendo de cliphist
-- (wl-paste --watch los guarda ahi arriba, en exec-once), solo cambia quien los
-- pinta y quien los busca.
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.global("quickshell:clipboard"))

-- Basicos
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("uwsm app -- " .. terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("uwsm app -- " .. fileManager))


-- IA local: panel que conoce este sistema. Workspace especial para que la
-- sesion y el modelo sigan vivos entre pulsaciones.
--
-- ~/ia-local es un modulo autocontenido: TODO lo suyo vive ahi dentro, incluido
-- este panel. El bind se registra SOLO si el modulo existe, asi que borrar el
-- directorio no deja un Super+I muerto que parece funcionar y no hace nada.
-- El inventario de lo que el modulo toca fuera esta en ~/ia-local/HUELLA.md.
local ia_panel = os.getenv("HOME") .. "/ia-local/bin/ia-panel"
local ia_f = io.open(ia_panel, "r")
if ia_f then
    ia_f:close()
    hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(ia_panel))
end
-- Primera pulsacion: flotante al 60 % y centrada. Segunda: vuelve al mosaico.
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-float-centered.sh"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("~/.config/quickshell/reload.sh"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("kitty --class pokemon-popup -e ~/.config/hypr/scripts/pokemon-popup.sh"))

-- Quickshell (barra + notch). 'global' llega al shell por IPC.
hl.bind(mainMod .. " + R",         hl.dsp.global("quickshell:launcher"))   -- lanzador desde el notch
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.global("quickshell:media"))      -- reproductor flotante
hl.bind(mainMod .. " + N",         hl.dsp.global("quickshell:notchstyle")) -- alterna notch <-> isla
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.global("quickshell:wallpaper"))  -- picker wallpaper
hl.bind(mainMod .. " + TAB",       hl.dsp.global("quickshell:overview"))   -- overview de ventanas
hl.bind(mainMod .. " + D",         hl.dsp.global("quickshell:notch"))      -- centro de control
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.global("quickshell:system"))     -- estado del equipo
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.global("quickshell:power"))      -- menu de encendido
hl.bind(mainMod .. " + comma",     hl.dsp.global("quickshell:settings"))   -- Ajustes (como Cmd+, en macOS)
hl.bind(mainMod .. " + A",         hl.dsp.global("quickshell:settings"))   -- alias de Super+,
-- Super+K abria ~/.config/hypr/list_keybinds.sh: un rofi que parseaba ESTE
-- mismo fichero (bueno, su espejo .conf) para ensenar la lista de atajos. Pero
-- Ajustes > Atajos ya hacia exactamente ese parseo, asi que eran dos listas que
-- solo coincidian mientras nadie tocara ninguna. La tecla es la de siempre; lo
-- que abre ahora es la lista que ya vivia en el notch.
hl.bind(mainMod .. " + K",         hl.dsp.global("quickshell:keybinds"))   -- mapa de atajos (Ajustes > Atajos)

hl.bind(mainMod .. " + W",         hl.dsp.global("quickshell:bar"))        -- ocultar/mostrar la barra

-- Mover el FOCO con Super + Shift + flechas
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.focus({ direction = "d" }))

-- Mover/intercambiar la VENTANA con Super + flechas. Esto es lo que dispara
-- 'windowsMove', o sea el muelle de arriba.
hl.bind(mainMod .. " + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.window.move({ direction = "d" }))

-- Escritorios con Super + [0-9], y mandar la ventana alli con Super+Shift.
for i = 1, 10 do
    local key = i % 10  -- el 10 va en la tecla 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Rueda del raton para cambiar de escritorio
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mover/redimensionar arrastrando con Super + boton
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volumen/brillo: el OSD lo pinta el notch (Quickshell). El volumen lo detecta
-- solo via Pipewire; el brillo lo cambia el propio notch por IPC para que no
-- haya lag ni desfase de valor.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call notch bright up"),                      { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call notch bright down"),                    { locked = true, repeating = true })

-- Requiere playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Boton fisico de encendido
hl.bind("XF86PowerOff", hl.dsp.global("quickshell:power"))

-- Quick wins
hl.bind(mainMod .. " + CTRL + S",  hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-annotate.sh")) -- anotar captura (satty)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/colorpicker.sh"))         -- cuentagotas (hyprpicker)
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/hyprsunset-toggle.sh"))   -- luz nocturna

-- Signature: menu / ocr
-- El menu de comandos tampoco es ya un rofi: es el modo ">" del lanzador. Misma
-- tecla, misma lista (mas lo que aquel menu no podia ofrecer porque vivia fuera
-- del shell: ajustes, mapa de escritorios, no molestar, cafeina).
--
-- Aqui habia un tercer bind, Super+Ctrl+W, que instalaba una web como "app".
-- Retirado el 19-08-2026: era lo ULTIMO que quedaba lanzando rofi, y ni
-- ~/.local/share/webapps ni un solo .desktop de web-app llegaron a existir en
-- todo este tiempo. El script esta en ~/.config/webapp-install-retirado-*.tar.gz.
hl.bind(mainMod .. " + ALT + Space", hl.dsp.global("quickshell:actions"))                       -- menu de comandos
hl.bind(mainMod .. " + CTRL + T",    hl.dsp.exec_cmd("~/.config/hypr/scripts/ocr.sh"))          -- OCR de pantalla

-- Grabar pantalla (wf-recorder)
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenrecord.sh"))


--------------------------------
---- VENTANAS Y CAPAS ----
--------------------------------

-- --- App de Ajustes de Quickshell (SettingsWindow.qml) ---
-- Es la unica ventana de verdad (xdg-toplevel) del shell: class org.quickshell,
-- titulo "Ajustes"; el resto del shell son capas (layer-shell) y no pasan por
-- aqui. Sin estas reglas se abria TILED y ocupaba media pantalla (952x1038).
-- El tamano va tambien en el QML (implicitWidth/Height) para que no haya un
-- fogonazo grande antes de que Hyprland la redimensione. No bajar de 780 de
-- ancho: la ventana tiene minimo propio ahi.
hl.window_rule({
    name  = "ajustes-quickshell",
    match = {
        class = "^(org\\.quickshell)$",
        title = "^(Ajustes)$",
    },
    float  = true,
    size   = { 900, 620 },
    center = true,
})

-- La sombra dice "esto es lo que estas mirando": SOLO la ventana enfocada la
-- proyecta. Junto con dim_inactive, el foco deja de ser un matiz y pasa a ser
-- lo primero que ve el ojo al entrar en la pantalla, sin una sola linea de
-- borde. (Antes esto era "solo las flotantes", que en un tiling es casi nunca:
-- la regla era correcta sobre el papel y en la practica no se veia jamas.)
hl.window_rule({
    name      = "sombra-solo-en-foco",
    match     = { focus = 0 },
    no_shadow = true,
})

-- --- Ley 9: una animacion, un dueno ---
-- El compositor anima las superficies que APARECEN; la app anima lo de dentro.
--
-- La barra/notch de Quickshell es una capa PERMANENTE que se redimensiona sola
-- y que ya se anima ella misma (tokens de Appearance.qml). Si ademas la animara
-- Hyprland, se encadenarian dos animaciones sobre el mismo gesto y se veria un
-- borron. Aqui se le cede el mando a Quickshell.
hl.layer_rule({
    name    = "sin-anim-barra",
    match   = { namespace = "^(quickshell:bar)$" },
    no_anim = true,
})

-- Ley 6 aplicada a las superficies del shell: cada una entra por donde le
-- corresponde, en vez de un fundido generico para todas. El criterio sale de la
-- ley 9: hay que mirar QUE anima ya la app por dentro y darle al compositor
-- solo lo que quede libre. Si los dos animan lo mismo, los dos fundidos se
-- multiplican y el resultado no es el doble de bonito, es que llega tarde.
--
-- media: vive pegado al borde de abajo, asi que SUBE desde ahi. 'slide' mueve
-- posicion y nada mas -- no funde -- y la tarjeta por dentro ya se encarga de
-- la escala y la opacidad. Canales distintos, no se pisan.
hl.layer_rule({
    name      = "media-sube",
    match     = { namespace = "^(quickshell:media)$" },
    animation = "slide bottom",
})

-- wallpaper: ocupa la pantalla entera, asi que deslizarla ensenaria el borde
-- por el que entra. Y ademas su 'stage' ya se funde solo (animMed, OutCubic).
-- El compositor no tiene nada que aportar aqui: que se aparte.
hl.layer_rule({
    name    = "sin-anim-wallpaper",
    match   = { namespace = "^(quickshell:wallpaper)$" },
    no_anim = true,
})

-- overview: al reves que las otras dos. Las miniaturas entran solas en cascada,
-- pero el velo negro (color del PanelWindow, 55%) NO lo anima nadie por dentro.
-- Con no_anim apareceria la cascada sobre un negro ya puesto de golpe. El
-- fundido del compositor es justo lo que le falta.
hl.layer_rule({
    name      = "overview-funde",
    match     = { namespace = "^(quickshell:overview)$" },
    animation = "fade",
})

-- Aqui habia una regla "rofi-blur" (blur + ignore_alpha 0.5 sobre la capa de
-- rofi, que era lo unico con transparencia real). Se va con rofi el 19-08-2026:
-- una regla que apunta a una capa que ya nadie crea no hace nada salvo hacerte
-- creer que rofi sigue en el escritorio.


-- ==========================================================================
--  LO QUE MANDA EL SHELL
--
--  Ajustes > Apariencia > Efectos escribe efectos.lua y ademas lo aplica en
--  caliente, para que el interruptor se note en el momento. Este dofile es lo
--  que hace que ademas SOBREVIVA: a un `hyprctl reload`, que vuelve a leer
--  esta config y se llevaria por delante cualquier cambio en caliente, y a
--  reiniciar la sesion.
--
--  Va EL ULTIMO para ganarle a lo de arriba, y protegido con pcall: si el
--  fichero no existe -- un clon recien instalado, o un arranque sin Quickshell
--  -- no pasa nada y quedan los valores de arriba. Mismo trato que hyprlock.conf
--  le da a language.conf: los valores por defecto primero, la capa que puede
--  faltar despues.
-- ==========================================================================
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/efectos.lua")
