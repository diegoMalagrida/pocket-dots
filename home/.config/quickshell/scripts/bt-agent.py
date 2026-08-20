#!/usr/bin/env python3
"""bt-agent.py — agente de emparejamiento Bluetooth para el notch.

POR QUÉ EXISTE
--------------
Quickshell sabe emparejar (`Bluetooth.pair()`) y sabe decirte que está en ello,
pero no sabe CONTESTAR a lo que BlueZ pregunta a mitad del emparejamiento:

    "¿coincide el código 418293 con el que ves en el aparato?"
    "teclea 418293 en el teclado y pulsa Enter"

Esas preguntas no son señales: BlueZ las hace llamando a métodos de un objeto
D-Bus que el escritorio tiene que EXPORTAR, y desde QML no se puede exportar un
objeto D-Bus. La API de Bluetooth de Quickshell no tiene ningún callback de
agente, así que sin este proceso los auriculares emparejan igual (no preguntan
nada) pero un teclado o un mando falla EN SILENCIO: sin error, sin aviso,
simplemente no se empareja nunca.

Este proceso es ese objeto.

CÓMO ENCAJA
-----------
    BlueZ  --(bus del sistema)-->  Agent1   ->  `qs ipc call notch btask ...`
                                      ^                                |
                                      |                          el notch pregunta
                                      |                                |
    org.quickshell.BtAgent1.Reply(b) <+-- `busctl --user call` <--- clic del usuario

Dos buses a propósito: BlueZ vive en el del SISTEMA y llama de vuelta al objeto
que registremos ahí; el notch vive en el de SESIÓN y no debe poder tocar nada
del sistema. El único puente es este proceso.

Si nadie contesta en AGENT_TIMEOUT segundos se rechaza solo. Sin eso, un aviso
sin atender dejaría la cara del notch clavada por delante de todo (btpair tiene
prioridad sobre los paneles) y BlueZ esperando indefinidamente.
"""

import os
import signal
import subprocess
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
import gi
from gi.repository import GLib

gi.require_version("GLibUnix", "2.0")
from gi.repository import GLibUnix  # noqa: E402  (require_version tiene que ir antes)

AGENT_PATH = "/org/quickshell/btagent"
AGENT_IFACE = "org.bluez.Agent1"
REPLY_NAME = "org.quickshell.BtAgent"
REPLY_IFACE = "org.quickshell.BtAgent1"

# KeyboardDisplay = "puedo enseñar un número y puedo teclear". Es la capacidad
# más alta, y es la que hace que BlueZ elija la comparación numérica (segura)
# en vez de caer al emparejamiento sin autenticar cuando el otro aparato sí sabe
# enseñar el código.
CAPABILITY = "KeyboardDisplay"

AGENT_TIMEOUT = 45     # segundos para contestar a una pregunta
DISPLAY_TIMEOUT = 90   # los códigos que solo se leen viven más: hay que teclearlos


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def notch(*args):
    """Avisa al notch. Nunca revienta el agente: si el shell no está corriendo,
    el emparejamiento debe seguir funcionando aunque sea a ciegas."""
    try:
        subprocess.run(["qs", "ipc", "call", "notch", *[str(a) for a in args]],
                       timeout=3, capture_output=True)
    except Exception as e:
        log("aviso al notch fallido:", e)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


class Pending:
    """La pregunta que está en el aire. Solo puede haber una: BlueZ empareja de
    uno en uno, y dos caras del notch a la vez no tendrían sentido."""

    def __init__(self):
        self.ok = None
        self.err = None
        self.timer = None

    @property
    def live(self):
        return self.ok is not None

    def arm(self, ok, err, timeout):
        self.clear(notify=False)
        self.ok, self.err = ok, err
        self.timer = GLib.timeout_add_seconds(timeout, self._expired)

    def _expired(self):
        log("nadie contestó: se rechaza")
        err = self.err
        self.ok = self.err = self.timer = None
        notch("btclear")
        if err:
            err(Rejected("sin respuesta"))
        return False   # no repetir

    def answer(self, accept):
        if not self.live:
            return False
        ok, err = self.ok, self.err
        self.clear(notify=False)
        if accept:
            ok()
        else:
            err(Rejected("rechazado por el usuario"))
        return True

    def clear(self, notify=True):
        if self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
        self.ok = self.err = None
        if notify:
            notch("btclear")


pending = Pending()
system_bus = None
objetos = []    # lo exportado en D-Bus, vivo mientras viva el proceso


def device_name(path):
    """El nombre bonito del aparato. Si no lo hay, la dirección MAC; y si
    tampoco, el último trozo de la ruta D-Bus. Nunca vacío: la cara del notch
    tiene que decir CON QUÉ estás emparejando."""
    try:
        props = dbus.Interface(system_bus.get_object("org.bluez", path),
                               "org.freedesktop.DBus.Properties")
        for key in ("Alias", "Name", "Address"):
            try:
                v = str(props.Get("org.bluez.Device1", key))
                if v:
                    return v
            except dbus.DBusException:
                continue
    except Exception as e:
        log("no se pudo leer el nombre de", path, e)
    return str(path).rsplit("/", 1)[-1]


class Agent(dbus.service.Object):
    """El objeto que BlueZ llama. Va en el bus del SISTEMA."""

    # ── preguntas que necesitan respuesta ────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="",
                         async_callbacks=("ok", "err"))
    def RequestConfirmation(self, device, passkey, ok, err):
        code = "%06u" % passkey
        log("confirmar", device, code)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "confirm", device_name(device), code, -1)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="",
                         async_callbacks=("ok", "err"))
    def RequestAuthorization(self, device, ok, err):
        log("autorizar", device)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "authorize", device_name(device), "", -1)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="",
                         async_callbacks=("ok", "err"))
    def AuthorizeService(self, device, uuid, ok, err):
        # Un aparato ya emparejado que quiere usar un perfil (audio, mando…).
        # Si ya lo marcaste como de confianza no se pregunta: preguntar cada vez
        # que se encienden unos auriculares sería ruido puro.
        try:
            props = dbus.Interface(system_bus.get_object("org.bluez", device),
                                   "org.freedesktop.DBus.Properties")
            if bool(props.Get("org.bluez.Device1", "Trusted")):
                log("servicio autorizado solo (aparato de confianza)", device)
                ok()
                return
        except Exception as e:
            log("no se pudo leer Trusted:", e)
        log("autorizar servicio", device, uuid)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "authorize", device_name(device), "", -1)

    # ── códigos que solo se leen ─────────────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        # El caso del teclado: BlueZ inventa el código y lo tecleas TÚ allí.
        # Se llama varias veces, una por tecla, con `entered` subiendo — de ahí
        # la barrita de progreso del notch, que es la única señal de que el
        # teclado está hablando de verdad con el equipo.
        code = "%06u" % passkey
        notch("btask", "display", device_name(device), code, int(entered))
        if not pending.live:
            # No hay nada que contestar, pero sí que limpiar: si el
            # emparejamiento se queda a medias, la cara no puede quedarse fija.
            pending.timer = GLib.timeout_add_seconds(DISPLAY_TIMEOUT,
                                                     lambda: (notch("btclear"), False)[1])

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        notch("btask", "display", device_name(device), str(pincode), -1)

    # ── lo que este agente NO puede hacer, dicho en voz alta ─────────────

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        # Aquí BlueZ espera que el USUARIO teclee, en el ordenador, un número
        # que enseña el aparato. Haría falta un campo de texto con foco, que es
        # otra cosa. Se rechaza con un aviso visible en vez de fallar callando,
        # que es justo el problema que este agente viene a resolver.
        log("RequestPasskey no soportado", device)
        notch("btask", "authorize", device_name(device) + " — pide un código a mano", "", -1)
        GLib.timeout_add_seconds(6, lambda: (notch("btclear"), False)[1])
        raise Rejected("este agente no pide códigos a mano")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        log("RequestPinCode no soportado", device)
        notch("btask", "authorize", device_name(device) + " — pide un PIN a mano", "", -1)
        GLib.timeout_add_seconds(6, lambda: (notch("btclear"), False)[1])
        raise Rejected("este agente no pide PIN a mano")

    # ── ciclo de vida ────────────────────────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        log("BlueZ canceló")
        pending.clear()

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        log("BlueZ soltó el agente")
        pending.clear()


class Replier(dbus.service.Object):
    """Por donde contesta el notch. Va en el bus de SESIÓN."""

    @dbus.service.method(REPLY_IFACE, in_signature="b", out_signature="b")
    def Reply(self, accept):
        log("respuesta del usuario:", bool(accept))
        return pending.answer(bool(accept))

    @dbus.service.method(REPLY_IFACE, in_signature="", out_signature="b")
    def Ping(self):
        return True


def main():
    global system_bus
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    system_bus = dbus.SystemBus()
    session_bus = dbus.SessionBus()

    # OJO: hay que GUARDAR las referencias. Un dbus.service.BusName suelto lo
    # recolecta Python en cuanto sale de ámbito, y al recolectarlo SUELTA el
    # nombre del bus: el agente seguiría vivo y registrado en BlueZ, pero el
    # notch no encontraría a quién contestar ("The name is not activatable").
    objetos.append(Agent(system_bus, AGENT_PATH))
    objetos.append(dbus.service.BusName(REPLY_NAME, session_bus, do_not_queue=True))
    objetos.append(Replier(session_bus, AGENT_PATH))

    manager = dbus.Interface(system_bus.get_object("org.bluez", "/org/bluez"),
                             "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, CAPABILITY)
    try:
        # Ser el agente POR DEFECTO es lo que hace que las preguntas lleguen
        # aquí cuando el emparejamiento lo inicia el aparato y no nosotros.
        # Si blueman-applet se pusiera en marcha, se lo llevaría él: por eso
        # este servicio existe y blueman no se autoarranca.
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as e:
        log("no se pudo ser el agente por defecto:", e)

    log("agente registrado en", AGENT_PATH, "con capacidad", CAPABILITY)

    loop = GLib.MainLoop()

    def salir(*_):
        try:
            manager.UnregisterAgent(AGENT_PATH)
        except Exception:
            pass
        notch("btclear")
        loop.quit()

    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, salir)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, salir)
    loop.run()


if __name__ == "__main__":
    sys.exit(main())
