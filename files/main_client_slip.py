import asyncio
import random
import socket
import json
import os
import sys
import hashlib
import re

from reverse_frag import Reassembler

with open(os.path.join(os.path.dirname(sys.argv[0]), "config_client_slip.json")) as f:
    config = json.loads(f.read())

info_encryption_pass = hashlib.sha256(config["info_encryption_pass"].encode()).digest()
slipstream_addr = (config.get("slipstream_host", "127.0.0.1"), int(config.get("slipstream_port", 5201)))
fake_send_ip = config["fake_send_ip"]
fake_send_port = int(config["fake_send_port"])
h_bind = (config["h_in_address"].rsplit(":", 1)[0], int(config["h_in_address"].rsplit(":", 1)[1]))

TYPE_DATA = 0x00
TYPE_INFO = 0x01

slipstream_reader = None
slipstream_writer = None
slipstream_send_queue = asyncio.Queue(maxsize=4096)

last_h_addr: tuple | None = None
last_wan_recv_time: float | None = None
reverse_reassembler = Reassembler(15.0)


def _create_udp4(blocking: bool, bind_addr) -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setblocking(blocking)
    if bind_addr:
        s.bind(bind_addr)
    return s


def _xor(data: bytes, key: bytes) -> bytes:
    return bytes(data[i] ^ key[i] for i in range(len(data)))


h_socket = _create_udp4(False, h_bind)
wan_socket = _create_udp4(False, ("0.0.0.0", 0))
wan_port = int(wan_socket.getsockname()[1])


async def _get_writer():
    global slipstream_reader, slipstream_writer
    if slipstream_writer is None or slipstream_writer.is_closing():
        slipstream_reader, slipstream_writer = await asyncio.open_connection(*slipstream_addr)
        print("slipstream connected:", slipstream_addr)
    return slipstream_writer


async def slipstream_writer_task():
    global slipstream_reader, slipstream_writer
    while True:
        data = await slipstream_send_queue.get()
        frame = len(data).to_bytes(2, "big") + data
        while True:
            try:
                w = await _get_writer()
                w.write(frame)
                await w.drain()
                break
            except Exception as e:
                print("slipstream write error:", repr(e))
                try:
                    if slipstream_writer:
                        slipstream_writer.close()
                        await slipstream_writer.wait_closed()
                except Exception:
                    pass
                slipstream_reader = slipstream_writer = None
                await asyncio.sleep(0.2)


async def _enqueue(data: bytes):
    try:
        slipstream_send_queue.put_nowait(data)
    except asyncio.QueueFull:
        print("queue full: drop")


async def h_recv():
    global h_socket, last_h_addr
    loop = asyncio.get_running_loop()
    while True:
        cur = h_socket
        try:
            raw, addr = await loop.sock_recvfrom(cur, 65535)
        except Exception as e:
            print("h recv error:", e)
            cur.close()
            while h_socket is cur:
                try:
                    h_socket = _create_udp4(False, h_bind)
                    break
                except Exception as e2:
                    print("h socket recreate error:", e2)
                    await asyncio.sleep(1)
            continue
        if not raw:
            continue
        if last_h_addr != addr:
            last_h_addr = addr
            print("local app:", addr)
        await _enqueue(bytes([TYPE_DATA]) + raw)


async def wan_recv():
    global h_socket, last_wan_recv_time
    loop = asyncio.get_running_loop()
    while True:
        try:
            data, _ = await loop.sock_recvfrom(wan_socket, 65575)
        except Exception as e:
            print("wan recv error:", e)
            await asyncio.sleep(0.5)
            continue
        if not data or last_h_addr is None:
            continue
        data = reverse_reassembler.add_packet(data)
        if data is None:
            continue
        last_wan_recv_time = loop.time()
        cur = h_socket
        try:
            await loop.sock_sendto(cur, data, last_h_addr)
        except Exception as e:
            print("h send error:", e)
            cur.close()
            while h_socket is cur:
                try:
                    h_socket = _create_udp4(False, h_bind)
                    break
                except Exception as e2:
                    print("h socket recreate error:", e2)
                    await asyncio.sleep(1)


async def nat_keep_alive():
    loop = asyncio.get_running_loop()
    while True:
        await asyncio.sleep(2)
        try:
            await loop.sock_sendto(wan_socket, os.urandom(random.randint(257, 499)),
                                   (fake_send_ip, fake_send_port))
        except Exception as e:
            print("nat keepalive error:", e)


async def send_info_loop(my_public_ip: str):
    raw = (
        socket.inet_pton(socket.AF_INET, my_public_ip)
        + wan_port.to_bytes(2, "big")
        + socket.inet_pton(socket.AF_INET, fake_send_ip)
        + fake_send_port.to_bytes(2, "big")
    )
    payload = bytes([TYPE_INFO]) + _xor(raw, info_encryption_pass)
    while True:
        await _enqueue(payload)
        await asyncio.sleep(5)


async def fetch_ip(url: str) -> str:
    import aiohttp
    async with aiohttp.ClientSession() as s:
        async with s.get(url) as r:
            r.raise_for_status()
            text = await r.text()
    m = re.search(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", text)
    if m:
        return m.group(0)
    raise ValueError(f"no IP found in {url}")


async def main():
    loop = asyncio.get_running_loop()
    ip = config["my_public_ip"]
    if ip == "ezping":
        ip = await fetch_ip("https://ezping.ir/geoip")
    elif ip == "ipnumberia":
        ip = await fetch_ip("https://ipnumberia.com/")
    elif ip == "ipmyp":
        ip = await fetch_ip("https://ipmyp.ir/")
    print("public IP:", ip)

    for _ in range(3):
        await loop.sock_sendto(wan_socket, os.urandom(random.randint(257, 499)),
                               (fake_send_ip, fake_send_port))
        await asyncio.sleep(0.001)

    tasks = [
        asyncio.create_task(slipstream_writer_task()),
        asyncio.create_task(h_recv()),
        asyncio.create_task(wan_recv()),
        asyncio.create_task(nat_keep_alive()),
        asyncio.create_task(send_info_loop(ip)),
    ]
    print("started.")
    await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)


asyncio.run(main())
