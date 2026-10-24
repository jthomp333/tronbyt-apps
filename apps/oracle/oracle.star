"""
Applet: Oracle
Summary: A thought from your Ollama
Description: Asks a local Ollama model for one calm, slightly cryptic thought and scrolls it on the display. The same idea as the Oracle strip on the homepage kiosk.
Author: Jacob Thompson
"""

load("cache.star", "cache")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

DEFAULT_MODEL = "qwen3:14b"
DEFAULT_PROMPT = "You are the oracle of a small home server. In one calm, slightly cryptic sentence of at most 18 words, with no preamble or quotation marks, give the thought for the day."
TIMEZONE = "America/Chicago"

# Kiosk colors: amber label, cyan line.
AMBER = "#ffb547"
CYAN = "#5ce1e6"
DIM = "#555"

# Keep the last good line for a week so an Ollama outage still shows something.
LAST_LINE_TTL = 7 * 24 * 3600

def main(config):
    ollama_url = config.str("ollama_url", "").strip().rstrip("/")
    model = config.str("model", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    prompt = config.str("prompt", DEFAULT_PROMPT).strip() or DEFAULT_PROMPT
    frequency = config.str("frequency", "daily")

    if not ollama_url:
        return show("Set the Ollama URL in this app's settings.", DIM)

    now = time.now().in_location(TIMEZONE)
    if frequency == "hourly":
        period = now.format("2006-01-02T15")
        ttl = 3600
    else:
        period = now.format("2006-01-02")
        ttl = 24 * 3600

    key = "line-%s-%s" % (hash(ollama_url + model + prompt), period)
    last_key = "last-%s" % hash(ollama_url + model + prompt)

    line = cache.get(key)
    if line == None:
        line = ask_ollama(ollama_url, model, prompt)
        if line:
            cache.set(key, line, ttl_seconds = ttl)
            cache.set(last_key, line, ttl_seconds = LAST_LINE_TTL)
        else:
            # Ollama is down or slow: fall back to the last line we got.
            line = cache.get(last_key)

    if not line:
        return show("The oracle is silent. Ollama did not answer.", DIM)

    return show(line, CYAN)

def ask_ollama(base_url, model, prompt):
    resp = http.post(
        base_url + "/api/generate",
        json_body = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            # Stops qwen3 from spending its token budget on hidden reasoning.
            "think": False,
            "options": {"num_predict": 48, "temperature": 0.9},
        },
    )
    if resp.status_code != 200:
        print("Ollama returned %d" % resp.status_code)
        return None

    text = resp.json().get("response", "")
    return clean(text)

def clean(text):
    text = " ".join(text.strip().split())
    text = text.strip("\"'“”")
    return text

def show(line, color):
    header = render.Row(
        main_align = "space_between",
        cross_align = "center",
        expanded = True,
        children = [
            render.Text("ORACLE", font = "tom-thumb", color = AMBER),
            render.Circle(diameter = 3, color = AMBER),
        ],
    )

    body = render.Marquee(
        height = 24,
        scroll_direction = "vertical",
        offset_start = 24,
        offset_end = 24,
        child = render.WrappedText(
            content = line,
            width = 62,
            font = "tom-thumb",
            color = color,
            linespacing = 1,
        ),
    )

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Padding(
            pad = (1, 1, 1, 0),
            child = render.Column(
                children = [
                    header,
                    render.Box(height = 1, color = "#222"),
                    body,
                ],
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "ollama_url",
                name = "Ollama URL",
                desc = "Address of your Ollama server, for example http://192.168.1.20:11434",
                icon = "server",
            ),
            schema.Text(
                id = "model",
                name = "Model",
                desc = "Ollama model to ask.",
                icon = "brain",
                default = DEFAULT_MODEL,
            ),
            schema.Dropdown(
                id = "frequency",
                name = "New thought",
                desc = "How often the oracle speaks again.",
                icon = "clock",
                default = "daily",
                options = [
                    schema.Option(display = "Once a day", value = "daily"),
                    schema.Option(display = "Every hour", value = "hourly"),
                ],
            ),
            schema.Text(
                id = "prompt",
                name = "Prompt",
                desc = "What the oracle is asked. Keep answers short so they fit.",
                icon = "message",
                default = DEFAULT_PROMPT,
            ),
        ],
    )
