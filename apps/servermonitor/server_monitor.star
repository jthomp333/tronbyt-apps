"""
Applet: Server Monitor
Summary: Home server readouts
Description: CPU, memory, temperature, disks, containers and uptime from a Glances server, on three pages.
Author: Jacob Thompson
"""

load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

DEFAULT_TITLE = "MONGO2"

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

# Friendlier names for Glances mount points.
DISK_LABELS = {
    "/host/root": "ROOT",
    "/host/fast": "FAST",
    "/host/media": "MEDIA",
    "/host/backup": "BKUP",
}

OK_CONTAINER_STATES = ["running", "healthy"]

def main(config):
    base = config.str("glances_url", "").strip().rstrip("/")
    title = config.str("title", DEFAULT_TITLE).strip().upper()[:12] or DEFAULT_TITLE

    if not base:
        return message(title, "Set the Glances URL in this app's settings.")

    api = base + "/api/4"
    cpu = get(api + "/cpu/total")
    if cpu == None:
        return message(title, "Can't reach Glances.")

    cpu = cpu.get("total", 0)
    mem = (get(api + "/mem/percent") or {}).get("percent", 0)
    temp = cpu_temp(get(api + "/sensors") or [])
    load5 = (get(api + "/load") or {}).get("min5", 0)
    uptime = short_uptime(get(api + "/uptime") or "")
    disks = disk_rows(get(api + "/fs") or [])

    names = (get(api + "/containers/name") or {}).get("name", [])
    states = (get(api + "/containers/status") or {}).get("status", [])
    bad = [names[i] for i in range(min(len(names), len(states))) if states[i] not in OK_CONTAINER_STATES]

    worst = max([cpu, mem] + [d[1] for d in disks])
    if bad or worst >= 90 or (temp != None and temp >= 80):
        lamp = RED
    elif worst >= 75 or (temp != None and temp >= 70):
        lamp = AMBER
    else:
        lamp = GREEN

    page1 = page(title, lamp, [
        bar_row("CPU", cpu),
        bar_row("RAM", mem),
        text_row("TEMP", "%dC" % temp if temp != None else "--", temp_color(temp)),
        text_row("LOAD", two_decimals(load5), CYAN),
    ])

    page2 = page(title, lamp, [bar_row(label, pct) for label, pct in disks[:4]])

    if bad:
        status_text = "%d DOWN" % len(bad)
        status_color = RED
        detail = render.Marquee(
            width = 62,
            child = render.Text(", ".join(bad), font = FONT, color = RED),
        )
    else:
        status_text = "ALL OK"
        status_color = GREEN
        detail = render.Text("", font = FONT)

    page3 = page(title, lamp, [
        text_row("UP", uptime, CYAN),
        text_row("DOCK", "%d RUN" % len(names), CYAN),
        text_row("STAT", status_text, status_color),
        detail,
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

def cpu_temp(sensors):
    # AMD reports the CPU as Tctl, Intel as Package id 0.
    for preferred in ["Tctl", "Package id 0", "Tccd1"]:
        for s in sensors:
            if s.get("label") == preferred and s.get("value") != None:
                return int(s["value"])
    return None

def disk_rows(fs):
    rows = []
    seen = {}
    for d in fs:
        mount = d.get("mnt_point", "")
        if not mount.startswith("/host/") or mount in seen:
            continue
        seen[mount] = True
        label = DISK_LABELS.get(mount, mount.replace("/host/", "").upper()[:5])
        rows.append((label, d.get("percent", 0)))
    return rows

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

def bar_row(label, pct):
    pct = max(0, min(100, pct))
    filled = int(BAR_WIDTH * pct / 100 + 0.5)
    return render.Row(
        cross_align = "center",
        children = [
            render.Box(width = LABEL_WIDTH, height = 6, child = render.Row(expanded = True, children = [render.Text(label, font = FONT, color = DIM)])),
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
        children = [
            render.Box(width = LABEL_WIDTH, height = 6, child = render.Row(expanded = True, children = [render.Text(label, font = FONT, color = DIM)])),
            render.Text(value, font = FONT, color = color),
        ],
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
        ],
    )
