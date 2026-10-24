"""
Applet: Server Monitor
Summary: Home server readouts
Description: CPU, memory, temperature, load, network and disk activity, containers, uptime and alerts from a Glances server, on three pages.
Author: Jacob Thompson
"""

load("http.star", "http")
load("re.star", "re")
load("render.star", "render")
load("schema.star", "schema")

DEFAULT_TITLE = "MONGO2"
DEFAULT_FEED = "http://tidbyt-feed:8080"

# Kiosk palette.
AMBER = "#ffb547"
CYAN = "#5ce1e6"
GREEN = "#3ddc84"
RED = "#ff4d4d"
DIM = "#666"
TRACK = "#1e1e1e"

FONT = "tom-thumb"
LABEL_WIDTH = 21
BAR_WIDTH = 26

# Frames per page at 100 ms each: 5 seconds a page.
PAGE_FRAMES = 50

OK_CONTAINER_STATES = ["running", "healthy"]

# Whole physical disks only, so partitions and RAID devices aren't counted twice.
WHOLE_DISK = r"^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$"

# Interfaces that never carry the server's real traffic.
SKIP_IFACE = r"^(lo|docker|br-|veth|tailscale|virbr)"

ALERT_NAMES = {
    "MEMSWAP": "SWAP",
    "MEM": "RAM",
    "CPU_TOTAL": "CPU",
    "CPU_IOWAIT": "IO WAIT",
    "CPU_USER": "CPU",
    "CPU_SYSTEM": "CPU",
    "LOAD": "LOAD",
    "FS": "DISK",
    "SENSOR_TEMP": "TEMP",
}

def main(config):
    base = config.str("glances_url", "").strip().rstrip("/")
    title = config.str("title", DEFAULT_TITLE).strip().upper()[:12] or DEFAULT_TITLE
    feed = config.str("feed_url", DEFAULT_FEED).strip().rstrip("/") or DEFAULT_FEED

    if not base:
        return message(title, "Set the Glances URL in this app's settings.")

    api = base + "/api/4"
    cpu = get(api + "/cpu/total")
    if cpu == None:
        return message(title, "Glances did not answer.")

    cpu = cpu.get("total", 0)
    mem = (get(api + "/mem/percent") or {}).get("percent", 0)
    temp = cpu_temp(get(api + "/sensors") or [])
    load5 = (get(api + "/load") or {}).get("min5", 0)
    uptime = short_uptime(get(api + "/uptime") or "")
    down, up = network_rates(get(api + "/network") or [])
    read, write = disk_rates(get(api + "/diskio") or [])
    alert = active_alert(get(api + "/alert") or [])

    names = (get(api + "/containers/name") or {}).get("name", [])
    states = (get(api + "/containers/status") or {}).get("status", [])
    bad = [names[i] for i in range(min(len(names), len(states))) if states[i] not in OK_CONTAINER_STATES]

    worst = max(cpu, mem)
    if bad or worst >= 90 or (temp != None and temp >= 80) or (alert and alert["state"] == "CRITICAL"):
        lamp = RED
    elif worst >= 75 or (temp != None and temp >= 70) or alert:
        lamp = AMBER
    else:
        lamp = GREEN

    page1 = page(title, lamp, [
        bar_row("CPU", cpu),
        bar_row("RAM", mem),
        text_row("TEMP", "%dC" % temp if temp != None else "--", temp_color(temp)),
        text_row("LOAD", two_decimals(load5), CYAN),
    ])

    page2 = page(title, lamp, [
        text_row("IN", rate(down), CYAN),
        text_row("OUT", rate(up), CYAN),
        text_row("READ", rate(read), CYAN),
        text_row("WRIT", rate(write), CYAN),
    ])

    if bad:
        dock_text, dock_color = "%d DOWN" % len(bad), RED
    else:
        dock_text, dock_color = "%d OK" % len(names), GREEN

    if alert:
        alert_color = RED if alert["state"] == "CRITICAL" else AMBER
        alert_text = alert["name"]
    else:
        alert_color, alert_text = GREEN, "NONE"

    # The alert row scrolls whatever needs explaining: down containers first, then the alert.
    notes = [alert_text]
    if bad:
        notes.append("down: " + ", ".join(bad))
    if alert and alert["msg"]:
        notes.append(alert["msg"])
    if len(notes) > 1:
        alert_row = render.Row(children = [
            label_box("ALRT"),
            render.Marquee(width = 62 - LABEL_WIDTH, child = render.Text(" | ".join(notes), font = FONT, color = alert_color)),
        ])
    else:
        alert_row = text_row("ALRT", alert_text, alert_color)

    ai_text, ai_color = ollama_status(feed)

    page3 = page(title, lamp, [
        text_row("UP", uptime, CYAN),
        text_row("DOCK", dock_text, dock_color),
        alert_row,
        text_row("AI", ai_text, ai_color),
    ])

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Animation(
            children = [page1] * PAGE_FRAMES + [page2] * PAGE_FRAMES + [page3] * PAGE_FRAMES,
        ),
    )

def get(url):
    resp = http.get(url, ttl_seconds = 30)
    if resp.status_code != 200:
        print("Glances %s returned %d" % (url, resp.status_code))
        return None
    return resp.json()

def ollama_status(feed):
    # Read through tidbyt-feed, which polls Ollama in the background, so a
    # sleeping Ollama box can't stall this app.
    resp = http.get(feed + "/ollama", ttl_seconds = 30)
    if resp.status_code != 200:
        return "NO FEED", DIM
    status = resp.json()
    if not status.get("checked_at"):
        return "--", DIM
    if not status.get("online"):
        return "OFF", DIM
    loaded = status.get("loaded") or []
    if not loaded:
        return "IDLE", CYAN
    name = loaded[0].get("name", "")
    gb = (loaded[0].get("size_vram", 0) or 0) / (1024 * 1024 * 1024)
    return "%s %sG" % (name.split(":")[0][:6].upper(), one_decimal(gb)), GREEN

def cpu_temp(sensors):
    # AMD reports the CPU as Tctl, Intel as Package id 0.
    for preferred in ["Tctl", "Package id 0", "Tccd1"]:
        for s in sensors:
            if s.get("label") == preferred and s.get("value") != None:
                return int(s["value"])
    return None

def network_rates(interfaces):
    # The busiest real interface is the server's main link.
    best = None
    for n in interfaces:
        if re.match(SKIP_IFACE, n.get("interface_name", "")):
            continue
        if best == None or n.get("bytes_all_rate_per_sec", 0) > best.get("bytes_all_rate_per_sec", 0):
            best = n
    if best == None:
        return 0, 0
    return best.get("bytes_recv_rate_per_sec", 0) or 0, best.get("bytes_sent_rate_per_sec", 0) or 0

def disk_rates(disks):
    read = 0
    write = 0
    for d in disks:
        if re.match(WHOLE_DISK, d.get("disk_name", "")):
            read += d.get("read_bytes_rate_per_sec", 0) or 0
            write += d.get("write_bytes_rate_per_sec", 0) or 0
    return read, write

def active_alert(alerts):
    # Glances marks an alert that is still happening with end = -1.
    for a in alerts:
        if a.get("end", 0) == -1:
            kind = a.get("type", "")
            return {
                "state": a.get("state", "WARNING"),
                "name": ALERT_NAMES.get(kind, kind.replace("_", " "))[:10],
                "msg": a.get("global_msg", "") or "",
            }
    return None

def rate(bytes_per_sec):
    if bytes_per_sec >= 1024 * 1024:
        return one_decimal(bytes_per_sec / (1024 * 1024)) + " MB/s"
    if bytes_per_sec >= 1024:
        return "%d KB/s" % int(bytes_per_sec / 1024 + 0.5)
    return "%d B/s" % int(bytes_per_sec)

def short_uptime(text):
    # Glances gives "5 days, 22:06:20" or "22:06:20".
    if not text:
        return "--"
    days = 0
    clock = text
    if "day" in text:
        days = int(text.split(" ")[0])
        clock = text.split(", ")[-1]
    parts = clock.split(":")
    hours = int(parts[0])
    minutes = int(parts[1]) if len(parts) > 1 else 0
    if days:
        return "%dd %dh" % (days, hours)
    return "%dh %dm" % (hours, minutes)

def two_decimals(x):
    # Starlark's % operator has no precision, so format by hand.
    n = int(x * 100 + 0.5)
    frac = str(n % 100)
    if len(frac) < 2:
        frac = "0" + frac
    return "%d.%s" % (n // 100, frac)

def one_decimal(x):
    n = int(x * 10 + 0.5)
    return "%d.%d" % (n // 10, n % 10)

def level_color(pct):
    if pct >= 90:
        return RED
    if pct >= 75:
        return AMBER
    return GREEN

def temp_color(temp):
    if temp == None:
        return DIM
    if temp >= 80:
        return RED
    if temp >= 70:
        return AMBER
    return CYAN

def label_box(label):
    return render.Box(
        width = LABEL_WIDTH,
        height = 6,
        child = render.Row(expanded = True, children = [render.Text(label, font = FONT, color = DIM)]),
    )

def bar_row(label, pct):
    pct = max(0, min(100, pct))
    filled = int(BAR_WIDTH * pct / 100 + 0.5)
    return render.Row(
        cross_align = "center",
        children = [
            label_box(label),
            render.Stack(children = [
                render.Box(width = BAR_WIDTH, height = 4, color = TRACK),
                render.Box(width = max(filled, 1), height = 4, color = level_color(pct)),
            ]),
            render.Box(width = 62 - LABEL_WIDTH - BAR_WIDTH, height = 6, child = render.Row(
                expanded = True,
                main_align = "end",
                children = [render.Text("%d%%" % int(pct + 0.5), font = FONT, color = CYAN)],
            )),
        ],
    )

def text_row(label, value, color):
    return render.Row(
        cross_align = "center",
        children = [label_box(label), render.Text(value, font = FONT, color = color)],
    )

def page(title, lamp, rows):
    header = render.Row(
        main_align = "space_between",
        cross_align = "center",
        expanded = True,
        children = [
            render.Text(title, font = FONT, color = AMBER),
            render.Circle(diameter = 3, color = lamp),
        ],
    )
    return render.Padding(
        pad = (1, 1, 1, 0),
        child = render.Column(
            children = [
                header,
                render.Box(height = 1, color = "#222"),
                render.Column(children = rows),
            ],
        ),
    )

def message(title, text):
    return render.Root(
        child = page(title, DIM, [
            render.WrappedText(content = text, width = 62, font = FONT, color = DIM),
        ]),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "glances_url",
                name = "Glances URL",
                desc = "Address of the Glances web server, for example http://192.168.1.10:61208",
                icon = "server",
            ),
            schema.Text(
                id = "title",
                name = "Title",
                desc = "Header text, up to 12 characters.",
                icon = "tag",
                default = DEFAULT_TITLE,
            ),
            schema.Text(
                id = "feed_url",
                name = "Feed URL",
                desc = "Address of the tidbyt-feed helper, used for the Ollama row. The default works when it shares Tronbyt's Docker network.",
                icon = "brain",
                default = DEFAULT_FEED,
            ),
        ],
    )
