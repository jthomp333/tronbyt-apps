"""
Applet: Simple Clock
Summary: Time and date
Description: Shows the time with a blinking colon and today's date.
Author: Jacob Thompson
"""

load("encoding/json.star", "json")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

DEFAULT_LOCATION = json.encode({
    "lat": "40.7128",
    "lng": "-74.0060",
    "description": "New York, NY, USA",
    "locality": "New York",
    "timezone": "America/New_York",
})

DEFAULT_COLOR = "#00BFFF"

def main(config):
    location = json.decode(config.get("location", DEFAULT_LOCATION))
    timezone = location.get("timezone", "America/New_York")
    now = time.now().in_location(timezone)

    use_24h = config.bool("use_24h", False)
    color = config.str("color", DEFAULT_COLOR)

    hour_format = "15" if use_24h else "3"
    hours = now.format(hour_format)
    minutes = now.format("04")
    date = now.format("Mon Jan 2").upper()

    # Two frames: colon on, colon off. With a 500 ms delay it blinks once a second.
    frames = [
        clock_frame(hours, ":", minutes, now, use_24h, color, date),
        clock_frame(hours, " ", minutes, now, use_24h, color, date),
    ]

    return render.Root(
        delay = 500,
        child = render.Animation(children = frames * 15),
    )

def clock_frame(hours, separator, minutes, now, use_24h, color, date):
    time_row = [
        render.Text(hours + separator + minutes, font = "6x13", color = color),
    ]
    if not use_24h:
        time_row.append(
            render.Padding(
                pad = (1, 6, 0, 0),
                child = render.Text(now.format("PM"), font = "tom-thumb", color = "#888"),
            ),
        )

    return render.Box(
        child = render.Column(
            expanded = True,
            main_align = "space_evenly",
            cross_align = "center",
            children = [
                render.Row(children = time_row),
                render.Text(date, font = "tom-thumb", color = "#FFF"),
            ],
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Location",
                desc = "Location used to pick the time zone.",
                icon = "locationDot",
            ),
            schema.Toggle(
                id = "use_24h",
                name = "24-hour time",
                desc = "Show the time in 24-hour format.",
                icon = "clock",
                default = False,
            ),
            schema.Color(
                id = "color",
                name = "Time color",
                desc = "Color of the time digits.",
                icon = "brush",
                default = DEFAULT_COLOR,
            ),
        ],
    )
