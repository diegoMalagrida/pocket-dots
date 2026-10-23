#!/usr/bin/env python3
"""bt-agent.py — Bluetooth pairing agent for the notch.

WHY IT EXISTS
-------------
Quickshell knows how to pair (`Bluetooth.pair()`) and how to tell you it is
doing so, but it does not know how to ANSWER what BlueZ asks halfway through
the pairing:

    "does code 418293 match the one you see on the device?"
    "type 418293 on the keyboard and press Enter"

Those questions are not signals: BlueZ asks them by calling methods on a D-Bus
object the desktop has to EXPORT, and a D-Bus object cannot be exported from
QML. Quickshell's Bluetooth API has no agent callback at all, so without this
process headphones pair all the same (they ask nothing) but a keyboard or a
gamepad fails SILENTLY: no error, no warning, it simply never pairs.

This process is that object.

HOW IT FITS
-----------
    BlueZ  --(system bus)-->       Agent1   ->  `qs ipc call notch btask ...`
                                      ^                                |
                                      |                          the notch asks
                                      |                                |
    org.quickshell.BtAgent1.Reply(b) <+-- `busctl --user call` <--- user's click

Two buses on purpose: BlueZ lives on the SYSTEM one and calls back the object
we register there; the notch lives on the SESSION one and must not be able to
touch anything on the system. The only bridge is this process.

If nobody answers within AGENT_TIMEOUT seconds it is rejected automatically.
Without that, an unattended prompt would leave the notch's face stuck in front
of everything (btpair takes priority over the panels) and BlueZ waiting
indefinitely.
"""

import json
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
from gi.repository import GLibUnix  # noqa: E402  (require_version has to come first)

AGENT_PATH = "/org/quickshell/btagent"
AGENT_IFACE = "org.bluez.Agent1"
REPLY_NAME = "org.quickshell.BtAgent"
REPLY_IFACE = "org.quickshell.BtAgent1"

# KeyboardDisplay = "I can show a number and I can type". It is the highest
# capability, and it is what makes BlueZ choose numeric comparison (secure)
# instead of falling back to unauthenticated pairing when the other device CAN
# show the code.
CAPABILITY = "KeyboardDisplay"

AGENT_TIMEOUT = 45     # seconds to answer a question
DISPLAY_TIMEOUT = 90   # read-only codes live longer: they have to be typed


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def notch(*args):
    """Tells the notch. It never crashes the agent: if the shell is not running,
    pairing must keep working, even if blind."""
    try:
        subprocess.run(["qs", "ipc", "call", "notch", *[str(a) for a in args]],
                       timeout=3, capture_output=True)
    except Exception as e:
        log(tr("aviso al notch fallido:", "Could not notify the notch:"), e)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


class Pending:
    """The question currently in the air. There can only be one: BlueZ pairs
    one at a time, and two notch faces at once would make no sense."""

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
        log(tr("nadie contestó: se rechaza", "No reply: rejecting"))
        err = self.err
        self.ok = self.err = self.timer = None
        notch("btclear")
        if err:
            err(Rejected(tr("sin respuesta", "no reply")))
        return False   # do not repeat

    def answer(self, accept):
        if not self.live:
            return False
        ok, err = self.ok, self.err
        self.clear(notify=False)
        if accept:
            ok()
        else:
            err(Rejected(tr("rechazado por el usuario", "rejected by the user")))
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
objetos = []    # what is exported on D-Bus, alive as long as the process is


def english() -> bool:
    """The rice language, read when it is needed and not at start: this agent
    lives for the whole session, and the language can change under it."""
    try:
        with open(os.path.expanduser("~/.config/quickshell-rice.json"),
                  encoding="utf-8") as f:
            return json.load(f).get("language") == "en"
    except (OSError, ValueError, AttributeError):
        return False


def tr(es, en):
    return en if english() else es


def device_name(path):
    """The device's friendly name. If there is none, the MAC address; and
    failing that, the last piece of the D-Bus path. Never empty: the notch's
    face has to say WHAT you are pairing with."""
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
        log(tr("no se pudo leer el nombre de", "Could not read the name of"), path, e)
    return str(path).rsplit("/", 1)[-1]


class Agent(dbus.service.Object):
    """The object BlueZ calls. It lives on the SYSTEM bus."""

    # ── questions that need an answer ────────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="",
                         async_callbacks=("ok", "err"))
    def RequestConfirmation(self, device, passkey, ok, err):
        code = "%06u" % passkey
        log(tr("confirmar", "confirm"), device, code)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "confirm", device_name(device), code, -1)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="",
                         async_callbacks=("ok", "err"))
    def RequestAuthorization(self, device, ok, err):
        log(tr("autorizar", "authorise"), device)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "authorize", device_name(device), "", -1)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="",
                         async_callbacks=("ok", "err"))
    def AuthorizeService(self, device, uuid, ok, err):
        # An already paired device that wants to use a profile (audio, gamepad…).
        # If you already marked it as trusted, nothing is asked: asking every
        # time a pair of headphones is switched on would be pure noise.
        try:
            props = dbus.Interface(system_bus.get_object("org.bluez", device),
                                   "org.freedesktop.DBus.Properties")
            if bool(props.Get("org.bluez.Device1", "Trusted")):
                log(tr("servicio autorizado solo (aparato de confianza)",
                       "Service authorised automatically (trusted device)"), device)
                ok()
                return
        except Exception as e:
            log(tr("no se pudo leer Trusted:", "Could not read Trusted:"), e)
        log(tr("autorizar servicio", "authorise service"), device, uuid)
        pending.arm(ok, err, AGENT_TIMEOUT)
        notch("btask", "authorize", device_name(device), "", -1)

    # ── read-only codes ──────────────────────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        # The keyboard case: BlueZ makes up the code and YOU type it over there.
        # It is called several times, once per key, with `entered` going up —
        # hence the notch's little progress bar, which is the only sign that the
        # keyboard is really talking to the computer.
        code = "%06u" % passkey
        notch("btask", "display", device_name(device), code, int(entered))
        if not pending.live:
            # There is nothing to answer, but there is cleaning up to do: if the
            # pairing is left halfway, the face cannot stay stuck.
            pending.timer = GLib.timeout_add_seconds(DISPLAY_TIMEOUT,
                                                     lambda: (notch("btclear"), False)[1])

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        notch("btask", "display", device_name(device), str(pincode), -1)

    # ── what this agent CANNOT do, said out loud ─────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        # Here BlueZ expects the USER to type, on the computer, a number the
        # device shows. That would need a focused text field, which is another
        # matter. It is rejected with a visible warning instead of failing
        # quietly, which is precisely the problem this agent exists to solve.
        log(tr("RequestPasskey no soportado", "RequestPasskey is not supported"), device)
        aviso = " — wants a code typed by hand" if english() else " — pide un código a mano"
        notch("btask", "authorize", device_name(device) + aviso, "", -1)
        GLib.timeout_add_seconds(6, lambda: (notch("btclear"), False)[1])
        raise Rejected(tr("este agente no pide códigos a mano", "This agent does not request codes manually"))

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        log(tr("RequestPinCode no soportado", "RequestPinCode is not supported"), device)
        aviso = " — wants a PIN typed by hand" if english() else " — pide un PIN a mano"
        notch("btask", "authorize", device_name(device) + aviso, "", -1)
        GLib.timeout_add_seconds(6, lambda: (notch("btclear"), False)[1])
        raise Rejected(tr("este agente no pide PIN a mano", "This agent does not request PINs manually"))

    # ── lifecycle ────────────────────────────────────────────────────────

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        log(tr("BlueZ canceló", "BlueZ cancelled"))
        pending.clear()

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        log(tr("BlueZ soltó el agente", "BlueZ released the agent"))
        pending.clear()


class Replier(dbus.service.Object):
    """The way the notch answers back. It lives on the SESSION bus."""

    @dbus.service.method(REPLY_IFACE, in_signature="b", out_signature="b")
    def Reply(self, accept):
        log(tr("respuesta del usuario:", "User reply:"), bool(accept))
        return pending.answer(bool(accept))

    @dbus.service.method(REPLY_IFACE, in_signature="", out_signature="b")
    def Ping(self):
        return True


def main():
    global system_bus
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    system_bus = dbus.SystemBus()
    session_bus = dbus.SessionBus()

    # CAREFUL: the references have to be KEPT. Python collects a stray
    # dbus.service.BusName as soon as it goes out of scope, and collecting it
    # RELEASES the bus name: the agent would stay alive and registered with
    # BlueZ, but the notch would find nobody to answer ("The name is not
    # activatable").
    objetos.append(Agent(system_bus, AGENT_PATH))
    objetos.append(dbus.service.BusName(REPLY_NAME, session_bus, do_not_queue=True))
    objetos.append(Replier(session_bus, AGENT_PATH))

    manager = dbus.Interface(system_bus.get_object("org.bluez", "/org/bluez"),
                             "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, CAPABILITY)
    try:
        # Being the DEFAULT agent is what makes the questions arrive here when
        # the pairing is started by the device and not by us. If blueman-applet
        # started up, it would take that role: that is why this service exists
        # and blueman does not autostart.
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as e:
        log(tr("no se pudo ser el agente por defecto:", "Could not become the default agent:"), e)

    log(tr("agente registrado en", "Agent registered at"), AGENT_PATH, tr("con capacidad", "with capability"), CAPABILITY)

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
