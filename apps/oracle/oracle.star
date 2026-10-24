"""
Applet: Oracle
Summary: A thought from your Ollama
Description: Shows one calm, slightly cryptic thought from a local Ollama model, fetched through the tidbyt-feed helper so a slow or sleeping Ollama never blocks the display.
Author: Jacob Thompson
"""

load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

DEFAULT_FEED = "http://tidbyt-feed:8080"
DEFAULT_MODEL = "qwen3:14b"
DEFAULT_PROMPT = "You are the oracle of a small home server. In one calm, slightly cryptic sentence of at most 18 words, with no preamble or quotation marks, give the thought for the day."
DEFAULT_TITLE = "ORACLE"
MAX_TITLE = 14  # what fits beside the lamp in the tom-thumb font

# Kiosk colors: amber label, cyan line.
AMBER = "#ffb547"
CYAN = "#5ce1e6"
DIM = "#555"

def main(config):
    feed = config.str("feed_url", DEFAULT_FEED).strip().rstrip("/") or DEFAULT_FEED
    model = config.str("model", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    prompt = config.str("prompt", DEFAULT_PROMPT).strip() or DEFAULT_PROMPT
    frequency = config.str("frequency", "daily")
    title = config.str("title", DEFAULT_TITLE).strip().upper()[:MAX_TITLE] or DEFAULT_TITLE

    # The helper answers at once: the current line, or the last one while a new
    # one is being written in the background.
    resp = http.get(
        feed + "/oracle",
        params = {"prompt": prompt, "model": model, "freq": frequency},
        ttl_seconds = 60,
    )
    if resp.status_code != 200:
        return show("The oracle is silent. The feed answered %d." % resp.status_code, DIM, title)

    line = resp.json().get("line")
    if line:
        return show(line, CYAN, title)
    if resp.json().get("thinking"):
        return show("The oracle is thinking...", DIM, title)
    return show("The oracle is silent. Ollama did not answer.", DIM, title)

def show(line, color, title):
    header = render.Row(
        main_align = "space_between",
        cross_align = "center",
        expanded = True,
        children = [
            render.Text(title, font = "tom-thumb", color = AMBER),
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
                id = "title",
                name = "Title",
                desc = "Header text, up to 14 characters.",
                icon = "house",
                default = DEFAULT_TITLE,
            ),
            schema.Text(
                id = "feed_url",
                name = "Feed URL",
                desc = "Address of the tidbyt-feed helper. The default works when it shares Tronbyt's Docker network.",
                icon = "server",
                default = DEFAULT_FEED,
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
