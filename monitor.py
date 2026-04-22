#!/usr/bin/env python3
"""Serves monitor.html and a /stats endpoint with live system + MLX metrics."""
import json, re, socket, subprocess, time, pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

# Endpoints mirror ~/.pi/agent/models.json — keep these in sync with the justfile.
ENDPOINTS = [
    {"name": "gemma", "port": 11435, "label": "Gemma"},
    {"name": "qwen",  "port": 9099,  "label": "Qwen"},
]
MONITOR_PORT = 8766
HTML_FILE = pathlib.Path(__file__).with_name("monitor.html")


def sh(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


_host_cache = None


def get_host_info():
    global _host_cache
    if _host_cache is not None:
        return _host_cache
    total = int(sh(["sysctl", "-n", "hw.ncpu"]).strip() or 0)
    p = int(sh(["sysctl", "-n", "hw.perflevel0.physicalcpu"]).strip() or 0)
    e = int(sh(["sysctl", "-n", "hw.perflevel1.physicalcpu"]).strip() or 0)
    sp = sh(["system_profiler", "SPDisplaysDataType"], timeout=5)
    chip_m = re.search(r"Chipset Model:\s*(.+)", sp)
    cores_m = re.search(r"Total Number of Cores:\s*(\d+)", sp)
    _host_cache = {
        "chip": chip_m.group(1).strip() if chip_m else "Apple Silicon",
        "cpu_cores": total,
        "cpu_p_cores": p,
        "cpu_e_cores": e,
        "gpu_cores": int(cores_m.group(1)) if cores_m else None,
    }
    return _host_cache


def get_pid_on_port(port):
    out = sh(["lsof", "-ti", f":{port}"]).strip().split("\n")[0]
    return int(out) if out else None


def get_model_for_pid(pid):
    if not pid:
        return None
    cmd = sh(["ps", "-o", "command=", "-p", str(pid)])
    m = re.search(r"--model\s+(\S+)", cmd)
    return m.group(1) if m else None


def _parse_size_to_bytes(s):
    # vmmap prints sizes like "15.7G", "487M", "12K", "0B"
    s = s.strip()
    if not s:
        return 0
    unit = s[-1].upper()
    try:
        n = float(s[:-1]) if unit in "KMGTB" else float(s)
    except ValueError:
        return 0
    return int(n * {"B": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}.get(unit, 1))


def get_process_stats(pid):
    if not pid:
        return {"pid": None, "cpu": None, "rss_gb": None, "footprint_gb": None, "footprint_peak_gb": None}
    # CPU% and raw RSS from ps (fast)
    parts = sh(["ps", "-o", "%cpu=,rss=", "-p", str(pid)]).strip().split()
    cpu = float(parts[0]) if len(parts) >= 2 else None
    rss_gb = float(parts[1]) / (1024 * 1024) if len(parts) >= 2 else None

    # True physical footprint from vmmap (includes mmap'd pages) — matches Activity Monitor
    vm = sh(["vmmap", "--summary", str(pid)], timeout=3)
    fp = fp_peak = None
    for line in vm.split("\n"):
        if "Physical footprint:" in line and "peak" not in line:
            m = re.search(r"Physical footprint:\s*([\d.]+[KMGT]?)", line)
            if m:
                fp = _parse_size_to_bytes(m.group(1)) / (1024**3)
        elif "Physical footprint (peak):" in line:
            m = re.search(r"Physical footprint \(peak\):\s*([\d.]+[KMGT]?)", line)
            if m:
                fp_peak = _parse_size_to_bytes(m.group(1)) / (1024**3)

    return {
        "pid": pid,
        "cpu": cpu,
        "rss_gb": rss_gb,
        "footprint_gb": fp,
        "footprint_peak_gb": fp_peak,
    }


def get_cpu_total():
    ncpu = int(sh(["sysctl", "-n", "hw.ncpu"]).strip() or 1)
    total = sum(float(x) for x in sh(["ps", "-A", "-o", "%cpu="]).split() if x)
    return min(100.0, total / ncpu)


def get_memory():
    r = sh(["vm_stat"])
    total = int(sh(["sysctl", "-n", "hw.memsize"]).strip() or 0)
    m = re.search(r"page size of (\d+) bytes", r)
    page = int(m.group(1)) if m else 16384

    def num(key):
        for line in r.split("\n"):
            if line.startswith(key):
                return int(line.split(":")[1].strip().rstrip("."))
        return 0

    # macOS "free" = truly unallocated pages. Everything else (active, inactive, wired,
    # compressor, speculative, file-backed) is "used" and matches Activity Monitor.
    free_pages = num("Pages free") + num("Pages speculative")
    free = free_pages * page
    used = max(0, total - free)
    return {
        "total_gb": total / (1024**3),
        "used_gb": used / (1024**3),
        "free_gb": free / (1024**3),
    }


def get_gpu():
    r = sh(["ioreg", "-rc", "AGXAccelerator"])

    def extract(key):
        m = re.search(rf'"{key}"=(\d+)', r)
        return int(m.group(1)) if m else None

    mem = extract("In use system memory") or 0
    return {
        "device_util": extract("Device Utilization %"),
        "renderer_util": extract("Renderer Utilization %"),
        "tiler_util": extract("Tiler Utilization %"),
        "mem_used_gb": mem / (1024**3),
    }


def is_port_up(port):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=0.3).close()
        return True
    except Exception:
        return False


def get_endpoint_stats(ep):
    pid = get_pid_on_port(ep["port"])
    proc = get_process_stats(pid)
    return {
        "name": ep["name"],
        "label": ep["label"],
        "port": ep["port"],
        "up": is_port_up(ep["port"]),
        "model": get_model_for_pid(pid),
        **proc,
    }


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            if not HTML_FILE.exists():
                self.send_error(500, "monitor.html missing next to monitor.py")
                return
            body = HTML_FILE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)
        elif path == "/stats":
            endpoints = [get_endpoint_stats(ep) for ep in ENDPOINTS]
            # Active = the first endpoint whose server is up (drives charts + "MLX process" card).
            active = next((e for e in endpoints if e["up"]), endpoints[0])
            stats = {
                "ts": time.time(),
                "endpoints": endpoints,
                "active": active["name"],
                "mlx_port": active["port"],
                "server_up": active["up"],
                "cpu_total": get_cpu_total(),
                "mlx": active,
                "gpu": get_gpu(),
                "mem": get_memory(),
                "host": get_host_info(),
            }
            body = json.dumps(stats).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)
        else:
            # Serve static files from the same directory
            base_dir = HTML_FILE.parent
            requested_path = (base_dir / path.lstrip("/")).resolve()

            # Security: Ensure the requested file is within the base directory
            if requested_path.exists() and requested_path.is_file() and base_dir in requested_path.parents or requested_path == base_dir:
                content_type = "application/octet-stream"
                if requested_path.suffix == ".html":
                    content_type = "text/html; charset=utf-8"
                elif requested_path.suffix == ".svg":
                    content_type = "image/svg+xml"
                elif requested_path.suffix == ".css":
                    content_type = "text/css"
                elif requested_path.suffix == ".js":
                    content_type = "application/javascript"
                elif requested_path.suffix == ".json":
                    content_type = "application/json"

                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.end_headers()
                self.wfile.write(requested_path.read_bytes())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"404 Not Found")


if __name__ == "__main__":
    url = f"http://127.0.0.1:{MONITOR_PORT}/"
    print(f"Monitor -> {url}")
    HTTPServer(("127.0.0.1", MONITOR_PORT), H).serve_forever()
