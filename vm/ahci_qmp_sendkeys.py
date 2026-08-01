#!/usr/bin/env python3
"""Send the Rhapsody boot command through QEMU's JSON QMP protocol."""

import json
import socket
import sys
import time


class QMPError(RuntimeError):
    pass


KEY_MAP = {c: [c] for c in "abcdefghijklmnopqrstuvwxyz0123456789"}
KEY_MAP.update({
    "-": ["minus"],
    "_": ["shift", "minus"],
    "=": ["equal"],
    " ": ["spc"],
    "\n": ["ret"],
    "\r": ["ret"],
})


class QMPClient:
    def __init__(self, host, port, deadline):
        self.deadline = deadline
        self.socket = None
        self.stream = None
        last_error = None
        while time.monotonic() < self.deadline:
            try:
                remaining = self._remaining()
                self.socket = socket.create_connection(
                    (host, port), min(1, remaining))
                break
            except OSError as error:
                last_error = error
                remaining = self.deadline - time.monotonic()
                if remaining > 0:
                    time.sleep(min(0.1, remaining))
        if self.socket is None:
            raise QMPError("QMP deadline expired while connecting: %s" % last_error)
        try:
            self.stream = self.socket.makefile("rwb", buffering=0)
            greeting = self._read_message()
        except QMPError:
            self.close()
            raise
        except (OSError, ValueError) as error:
            self.close()
            raise QMPError("QMP connection failed: %s" % error)
        if "QMP" not in greeting:
            self.close()
            raise QMPError("invalid QMP greeting")
        self.next_id = 1
        try:
            self.execute("qmp_capabilities")
        except Exception:
            self.close()
            raise

    def _remaining(self):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise QMPError("QMP deadline expired")
        return remaining

    def _read_message(self):
        try:
            self.socket.settimeout(self._remaining())
            line = self.stream.readline()
        except socket.timeout:
            raise QMPError("QMP deadline expired while reading")
        except (OSError, socket.timeout) as error:
            raise QMPError("QMP read failed: %s" % error)
        if not line:
            raise QMPError("QMP connection closed before reply")
        try:
            message = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            raise QMPError("invalid QMP JSON: %s" % error)
        if not isinstance(message, dict):
            raise QMPError("invalid QMP message type")
        return message

    def execute(self, command, **arguments):
        request_id = self.next_id
        self.next_id += 1
        request = {"execute": command, "id": request_id}
        if arguments:
            request["arguments"] = arguments
        try:
            self.socket.settimeout(self._remaining())
            self.socket.sendall(json.dumps(request).encode("ascii") + b"\n")
        except socket.timeout:
            raise QMPError("QMP deadline expired while writing")
        except (OSError, socket.timeout) as error:
            raise QMPError("QMP write failed: %s" % error)
        while True:
            reply = self._read_message()
            if "event" in reply or reply.get("id") != request_id:
                continue
            if "error" in reply:
                error = reply["error"]
                if isinstance(error, dict):
                    error = error.get("desc", error)
                raise QMPError("QMP %s failed: %s" % (command, error))
            if "return" not in reply:
                raise QMPError("QMP %s reply has no result" % command)
            return reply["return"]

    def close(self):
        stream = getattr(self, "stream", None)
        sock = getattr(self, "socket", None)
        if stream is not None:
            try:
                stream.close()
            except OSError:
                pass
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass


def send_keys(host, port, delay, text, timeout=30):
    deadline = time.monotonic() + timeout
    for char in text:
        if char not in KEY_MAP:
            raise QMPError("no QMP key mapping for %r" % char)
    client = QMPClient(host, port, deadline)
    try:
        remaining = client._remaining()
        if delay >= remaining:
            time.sleep(remaining)
            raise QMPError("QMP deadline expired during key delay")
        time.sleep(delay)
        for char in text:
            for code in KEY_MAP[char]:
                client.execute("send-key", keys=[{"type": "qcode", "data": code}])
                remaining = client._remaining()
                if remaining <= 0.05:
                    time.sleep(remaining)
                    raise QMPError("QMP deadline expired between keys")
                time.sleep(0.05)
    finally:
        client.close()


def main(argv):
    if len(argv) != 5:
        raise QMPError("usage: ahci_qmp_sendkeys.py HOST PORT DELAY TEXT")
    send_keys(argv[1], int(argv[2]), float(argv[3]), argv[4])


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (QMPError, ValueError) as error:
        print("ahci-qmp-sendkeys: %s" % error, file=sys.stderr)
        raise SystemExit(1)
