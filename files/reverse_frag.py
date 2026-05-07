import time

MAGIC = b"QSRF"
HEADER_LEN = 10


def encode_fragments(payload: bytes, message_id: int, chunk_size: int = 1100):
    if chunk_size < 64:
        raise ValueError("chunk_size too small")

    if len(payload) <= chunk_size and not payload.startswith(MAGIC):
        return [payload]

    total = (len(payload) + chunk_size - 1) // chunk_size
    if total > 255:
        raise ValueError(f"payload too large for fragmentation: {len(payload)} bytes")

    out = []
    orig_len = len(payload).to_bytes(2, "big")
    msg_id_b = message_id.to_bytes(2, "big")

    for idx in range(total):
        part = payload[idx * chunk_size:(idx + 1) * chunk_size]
        header = MAGIC + msg_id_b + bytes([idx, total]) + orig_len
        out.append(header + part)

    return out


def parse_fragment(packet: bytes):
    if len(packet) < HEADER_LEN or not packet.startswith(MAGIC):
        return None

    msg_id = int.from_bytes(packet[4:6], "big")
    idx = packet[6]
    total = packet[7]
    orig_len = int.from_bytes(packet[8:10], "big")
    part = packet[10:]

    if total == 0 or idx >= total:
        return None

    return msg_id, idx, total, orig_len, part


class Reassembler:
    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout
        self.messages = {}

    def _cleanup(self, now: float):
        dead = [k for k, v in self.messages.items() if now - v["time"] > self.timeout]
        for k in dead:
            del self.messages[k]

    def add_packet(self, packet: bytes):
        frag = parse_fragment(packet)
        if frag is None:
            return packet

        now = time.monotonic()
        self._cleanup(now)

        msg_id, idx, total, orig_len, part = frag
        entry = self.messages.get(msg_id)

        if entry is None or entry["total"] != total or entry["orig_len"] != orig_len:
            entry = {
                "time": now,
                "total": total,
                "orig_len": orig_len,
                "parts": [None] * total,
                "count": 0,
            }
            self.messages[msg_id] = entry

        if entry["parts"][idx] is None:
            entry["parts"][idx] = part
            entry["count"] += 1
            entry["time"] = now

        if entry["count"] != entry["total"]:
            return None

        payload = b"".join(entry["parts"])[:entry["orig_len"]]
        del self.messages[msg_id]
        return payload
