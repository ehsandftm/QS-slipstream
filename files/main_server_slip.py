import asyncio, socket, os, sys, json, hashlib, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from utility.packets import build_udp_payload_v4, build_ipv4_header
from reverse_frag import encode_fragments

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "config_server_slip.json")) as f:
    config = json.loads(f.read())

info_encryption_pass = hashlib.sha256(config["info_encryption_pass"].encode()).digest()
listen_host = config.get("listen_host", "127.0.0.1")
listen_port = int(config.get("listen_port", 5210))
target_addr = (config["target_host"], int(config["target_port"]))
fragment_chunk_size = int(config.get("fragment_chunk_size", 1100))
TYPE_DATA, TYPE_INFO = 0x00, 0x01
raw_sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
raw_sock.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)

def _xor(data, key):
    return bytes(data[i] ^ key[i] for i in range(len(data)))

def _spoof_send(src_ip, src_port, dst_ip, dst_port, payload):
    sp, dp = socket.inet_aton(src_ip), socket.inet_aton(dst_ip)
    udp = build_udp_payload_v4(payload, src_port, dst_port, sp, dp)
    ip_hdr = build_ipv4_header(len(udp), sp, dp, 17, ip_id=random.randint(1, 65535))
    raw_sock.sendto(ip_hdr + udp, (dst_ip, 0))

class Session:
    def __init__(self):
        self.client_ip = self.client_port = self.spoof_src_ip = self.spoof_src_port = None
        self._msg_id = 0
        self.svc_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    def ready(self): return self.client_ip is not None
    def parse_info(self, payload):
        if len(payload) < 12: return False
        d = _xor(payload, info_encryption_pass)
        self.client_ip = socket.inet_ntop(socket.AF_INET, d[0:4])
        self.client_port = int.from_bytes(d[4:6], "big")
        self.spoof_src_ip = socket.inet_ntop(socket.AF_INET, d[6:10])
        self.spoof_src_port = int.from_bytes(d[10:12], "big")
        return True
    def _next_id(self):
        mid = self._msg_id; self._msg_id = (self._msg_id + 1) & 0xFFFF; return mid
    def send_to_client(self, data):
        for frag in encode_fragments(data, self._next_id(), fragment_chunk_size):
            try: _spoof_send(self.spoof_src_ip, self.spoof_src_port, self.client_ip, self.client_port, frag)
            except Exception as e: print("spoof error:", e)

async def svc_recv_loop(session):
    loop = asyncio.get_running_loop()
    session.svc_sock.setblocking(False)
    while True:
        try: data = await loop.sock_recv(session.svc_sock, 65535)
        except asyncio.CancelledError: return
        except Exception as e: print("svc recv error:", e); return
        if data and session.ready(): session.send_to_client(data)

async def handle_client(reader, writer):
    peer = writer.get_extra_info("peername")
    print("connected:", peer)
    session = Session()
    svc_task = asyncio.create_task(svc_recv_loop(session))
    loop = asyncio.get_running_loop()
    try:
        while True:
            hdr = await reader.readexactly(2)
            length = int.from_bytes(hdr, "big")
            if length == 0: continue
            frame = await reader.readexactly(length)
            ptype, payload = frame[0], frame[1:]
            if ptype == TYPE_INFO:
                was_ready = session.ready()
                if session.parse_info(payload) and not was_ready:
                    print(f"client: {session.client_ip}:{session.client_port}")
            elif ptype == TYPE_DATA:
                if not session.ready(): continue
                try: await loop.sock_sendto(session.svc_sock, payload, target_addr)
                except Exception as e: print("svc send error:", e)
    except asyncio.IncompleteReadError: pass
    except Exception as e: print("handler error:", repr(e))
    finally:
        svc_task.cancel(); session.svc_sock.close(); writer.close()
        print("disconnected:", peer)

async def main():
    server = await asyncio.start_server(handle_client, listen_host, listen_port)
    print(f"listening {listen_host}:{listen_port} -> {target_addr[0]}:{target_addr[1]}")
    async with server: await server.serve_forever()

asyncio.run(main())
