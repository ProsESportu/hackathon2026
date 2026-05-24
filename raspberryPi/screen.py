import board
import digitalio
from PIL import Image, ImageDraw, ImageFont
import adafruit_rgb_display.ili9341 as ili9341
import time
import random
import math
import socket
import threading

HOST        = "0.0.0.0"
PORT        = 5001
BUFFER_SIZE = 4096

# ── Display setup ────────────────────────────────────────────
spi       = board.SPI()
tft_cs    = digitalio.DigitalInOut(board.CE0)
tft_dc    = digitalio.DigitalInOut(board.D24)
tft_reset = digitalio.DigitalInOut(board.D25)
display = ili9341.ILI9341(
    spi,
    cs=tft_cs,
    dc=tft_dc,
    rst=tft_reset,
    width=240,
    height=320,
    rotation=180,
    baudrate=24000000,
)

IW, IH = 320, 240

# ── Progress bar config (native 240x320 portrait coords) ─────
BAR_W  = 300
BAR_H  = 40
BAR_X  = (320 - BAR_W) // 2
BAR_Y  = (240 - BAR_H) // 2 - 20

BAR2_W = 300
BAR2_H = 20
BAR2_X = (320 - BAR2_W) // 2
BAR2_Y = BAR_Y + BAR_H + 10

# ── Shared state ─────────────────────────────────────────────
case_event      = threading.Event()
case_lock       = threading.Lock()
pending_ip      = None

progress_lock   = threading.Lock()
progress_value  = 0
progress_value2 = 0.0

# ── Rarity tiers ─────────────────────────────────────────────
RARITIES = [
    {"name": "Consumer",   "color": (176, 195, 217), "bg": (40,  50,  70),  "weight": 80},
    {"name": "Industrial", "color": (94,  152, 217), "bg": (30,  50,  90),  "weight": 60},
    {"name": "Mil-Spec",   "color": (75,  105, 255), "bg": (20,  30, 100),  "weight": 40},
    {"name": "Restricted", "color": (136,  71, 255), "bg": (45,  15,  90),  "weight": 20},
    {"name": "Classified", "color": (211,  44, 230), "bg": (70,  10,  70),  "weight": 8},
    {"name": "Covert",     "color": (235,  75,  75), "bg": (90,  10,  10),  "weight": 3},
    {"name": "Gold",       "color": (228, 174,  57), "bg": (80,  55,   5),  "weight": 1},
]

SKIN_NAMES = {
  "Consumer": [
    "Drewniane stateczniki",
    "Mały silnik parowy",
  ],

  "Industrial": [
    "Stalowy korpus",
    "Lniany spadochron",
    "+5 Materiałów do Fabryk W Stalowej Woli"
  ],

  "Mil-Spec": [
    "Aluminiowe stateczniki",
    "Aerodynamiczny kołpak",
    "+10 Materiałów do Fabryk W Stalowej Woli"
  ],

  "Restricted": [
    "Silnik odrzutowy",
    "Korpus z włókna węglowego",

  ],

  "Classified": [
    "Tytanowe stateczniki",
    "Wytrzymały spadochron",
    "+10 Materiałów do Kuźni w Stalowej Woli"
  ],

  "Covert": [
    "Silnik jonowy",
    "Korpus ze stopu aluminium",
    "+10 Materiałów do Huty w Stalowej Woli"
  ],

  "Gold": [
    "Silnik na czarną materię",
    "Rdzeń antygrawitacyjny",
    "Eksponat do Muzeum COP w Stalowej Woli"
  ]
}

NOTIFY_PORT = 5002

# ── Progress bar helpers ──────────────────────────────────────
def lerp_color(t):
    stops = [
        (0.00, (0,   0,   255)),
        (0.25, (0,   180, 255)),
        (0.50, (0,   255,  80)),
        (0.75, (255, 220,   0)),
        (1.00, (255,   0,   0)),
    ]
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t0 <= t <= t1:
            f = (t - t0) / (t1 - t0)
            return (
                int(c0[0] + f * (c1[0] - c0[0])),
                int(c0[1] + f * (c1[1] - c0[1])),
                int(c0[2] + f * (c1[2] - c0[2])),
            )
    return stops[-1][1]

def draw_progress(value, value2=0.0):
    img  = Image.new("RGB", (240, 320), (15, 15, 25))
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 11)
    except Exception:
        font = ImageFont.load_default()

    def paste_rotated_label(text, bar_y, bar_x, bar_h, bar_w):
        bbox = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        txt_img = Image.new("RGBA", (tw + 4, th + 4), (0, 0, 0, 0))
        txt_draw = ImageDraw.Draw(txt_img)
        txt_draw.text((2, 2), text, fill=(180, 180, 200, 255), font=font)
        txt_img = txt_img.rotate(90, expand=True)
        paste_x = bar_y - txt_img.width - 4
        paste_y = bar_x + (bar_w - txt_img.height) // 2
        img.paste(txt_img, (paste_x, paste_y), txt_img)

    # ── Bar 1: Angle ──────────────────────────────────────────
    paste_rotated_label("ANGLE\n", BAR_Y, BAR_X, BAR_H, BAR_W)
    draw.rectangle(
        [BAR_Y, BAR_X, BAR_Y + BAR_H, BAR_X + BAR_W],
        fill=(40, 40, 55),
    )
    fill_w = int(BAR_W * value / 100)
    for y in range(fill_w):
        t   = y / BAR_W
        col = lerp_color(t)
        draw.line(
            [(BAR_Y, BAR_X + y), (BAR_Y + BAR_H, BAR_X + y)],
            fill=col,
        )
    draw.rectangle(
        [BAR_Y, BAR_X, BAR_Y + BAR_H, BAR_X + BAR_W],
        outline=(70, 70, 90),
        width=1,
    )

    # ── Bar 2: Distance ───────────────────────────────────────
    paste_rotated_label("\n\nDISTANCE\n", BAR2_Y, BAR2_X, BAR2_H, BAR2_W)
    draw.rectangle(
        [BAR2_Y, BAR2_X, BAR2_Y + BAR2_H, BAR2_X + BAR2_W],
        fill=(40, 40, 55),
    )
    fill_w2 = int(BAR2_W * (1.0 - value2 / 3.0))
    for y in range(fill_w2):
        t   = y / BAR2_W
        col = lerp_color(t)
        draw.line(
            [(BAR2_Y, BAR2_X + y), (BAR2_Y + BAR2_H, BAR2_X + y)],
            fill=col,
        )
    draw.rectangle(
        [BAR2_Y, BAR2_X, BAR2_Y + BAR2_H, BAR2_X + BAR2_W],
        outline=(70, 70, 90),
        width=1,
    )

    display.image(img)


# ── Case open helpers ─────────────────────────────────────────
def send_result_udp(dest_ip, rarity_name, skin_name):
    message = f"{skin_name}".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(message, (dest_ip, NOTIFY_PORT))
    print(f"Sent result to {dest_ip}:{NOTIFY_PORT} → {message.decode()}")

def weighted_choice(items):
    total = sum(r["weight"] for r in items)
    r = random.uniform(0, total)
    upto = 0
    for item in items:
        upto += item["weight"]
        if r <= upto:
            return item
    return items[-1]

def build_strip(num_items=40):
    strip = []
    for _ in range(num_items - 1):
        strip.append(weighted_choice(RARITIES))
    prize_pool = [r for r in RARITIES if r["weight"] <= 40]
    prize = weighted_choice(prize_pool)
    insert_pos = random.randint(32, 36)
    strip.insert(insert_pos, prize)
    return strip, insert_pos, prize

ITEM_W  = 70
ITEM_H  = 90
STRIP_Y = (IH - ITEM_H) // 2

def draw_item_card(draw, x, y, rarity, selected=False):
    bx, by, bw, bh = x, y, ITEM_W - 2, ITEM_H - 2
    col = rarity["color"]
    bg  = rarity["bg"]
    draw.rectangle([bx, by, bx + bw, by + bh], fill=bg)
    for i in range(3):
        draw.rectangle([bx + i, by + i, bx + bw - i, by + bh - i], outline=col)
    cx, cy = bx + bw // 2, by + bh // 2 - 8
    size = 18 if not selected else 22
    diamond = [(cx, cy - size), (cx + size, cy), (cx, cy + size), (cx - size, cy)]
    draw.polygon(diamond, fill=col)
    s2 = size // 2
    inner = [(cx, cy - s2), (cx + s2, cy), (cx, cy + s2), (cx - s2, cy)]
    draw.polygon(inner, fill=bg)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 8)
    except Exception:
        font = ImageFont.load_default()
    label = rarity["name"]
    bbox  = draw.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    draw.text((bx + (bw - tw) // 2, by + bh - 14), label, fill=col, font=font)

def push(img):
    display.image(img.rotate(90, expand=True))

def draw_frame(strip, scroll_px, flash=0.0, result_rarity=None, won_skin=None):
    bg_color = (10, 12, 18)
    img  = Image.new("RGB", (IW, IH), bg_color)
    draw = ImageDraw.Draw(img)
    for sy in range(0, IH, 4):
        draw.line([(0, sy), (IW, sy)], fill=(20, 22, 30))
    try:
        font_hdr = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
        font_sub = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 9)
    except Exception:
        font_hdr = ImageFont.load_default()
        font_sub = font_hdr
    draw.text((IW // 2 - 45, 8), "CASE OPENING", fill=(200, 200, 220), font=font_hdr)
    draw.line([(10, 27), (IW - 10, 27)], fill=(50, 55, 80))
    strip_top    = STRIP_Y
    strip_bottom = STRIP_Y + ITEM_H
    visible_start = int(scroll_px // ITEM_W)
    pixel_offset  = int(scroll_px % ITEM_W)
    draw.rectangle([0, 0, IW, strip_top - 1], fill=(8, 9, 16))
    draw.rectangle([0, strip_bottom + 1, IW, IH], fill=(8, 9, 16))
    draw.rectangle([0, strip_top, IW, strip_bottom], fill=(25, 28, 40))
    for slot in range(-1, IW // ITEM_W + 2):
        strip_idx = visible_start + slot
        if 0 <= strip_idx < len(strip):
            card_x = slot * ITEM_W - pixel_offset
            if -ITEM_W < card_x < IW:
                rarity = strip[strip_idx]
                selected = (card_x + ITEM_W // 2 > IW // 2 - 10 and
                            card_x + ITEM_W // 2 < IW // 2 + 10)
                draw_item_card(draw, card_x, strip_top, rarity, selected)
    marker_x = IW // 2
    arrow_pts_top = [(marker_x - 7, strip_top - 2), (marker_x + 7, strip_top - 2), (marker_x, strip_top + 7)]
    arrow_pts_bot = [(marker_x - 7, strip_bottom + 2), (marker_x + 7, strip_bottom + 2), (marker_x, strip_bottom - 7)]
    draw.polygon(arrow_pts_top, fill=(255, 210, 40))
    draw.polygon(arrow_pts_bot, fill=(255, 210, 40))
    draw.line([(marker_x, strip_top - 2), (marker_x, strip_bottom + 2)], fill=(255, 210, 40), width=1)
    for vx in range(30):
        shade = (8, 9, 16)
        draw.line([(vx, strip_top), (vx, strip_bottom)], fill=shade)
        draw.line([(IW - 1 - vx, strip_top), (IW - 1 - vx, strip_bottom)], fill=shade)
    if flash > 0.0:
        fv = int(255 * flash)
        flash_img = Image.new("RGB", (IW, IH), (fv, fv, fv))
        img = Image.blend(img, flash_img, flash * 0.7)
        draw = ImageDraw.Draw(img)
    if result_rarity and won_skin:
        col = result_rarity["color"]
        draw.rectangle([0, IH - 72, IW, IH], fill=(12, 14, 22))
        draw.line([(0, IH - 72), (IW, IH - 72)], fill=col, width=2)
        for gi in range(4):
            draw.line([(0, IH - 72 + gi), (IW, IH - 72 + gi)],
                      fill=(col[0] // (gi + 1), col[1] // (gi + 1), col[2] // (gi + 1)))
        draw.text((10, IH - 65), result_rarity["name"].upper(), fill=col, font=font_hdr)
        draw.text((10, IH - 47), won_skin, fill=(200, 200, 220), font=font_sub)
        draw.rectangle([10, IH - 18, IW - 10, IH - 10], fill=(30, 33, 50))
        draw.rectangle([10, IH - 18, 10 + int((IW - 20) * 0.87), IH - 10], fill=col)
    push(img)

def ease_out_expo(t):
    if t >= 1.0:
        return 1.0
    return 1 - 2 ** (-10 * t)

def run_case_open(sender_ip):
    strip, win_idx, prize = build_strip(42)
    center_offset = random.randint(-15, 15)
    target_scroll = float(win_idx * ITEM_W + ITEM_W // 2 - IW // 2 + center_offset)
    TOTAL_DURATION = 5.2
    FLASH_DURATION = 0.35
    start_time   = time.time()
    flashing     = False
    flash_start  = None
    result_shown = False
    won_skin = random.choice(SKIN_NAMES[prize["name"]])
    while True:
        now     = time.time()
        elapsed = now - start_time
        if elapsed < TOTAL_DURATION:
            t = elapsed / TOTAL_DURATION
            eased = ease_out_expo(t)
            scroll_px = eased * target_scroll
            if eased > 0.95 and not flashing:
                flashing    = True
                flash_start = now
            flash_val = 0.0
            if flashing:
                fd = now - flash_start
                if fd < FLASH_DURATION:
                    flash_val = math.sin(fd / FLASH_DURATION * math.pi)
            draw_frame(strip, scroll_px, flash=flash_val)
            time.sleep(0.016)
        elif not result_shown:
            draw_frame(strip, target_scroll, flash=0.0, result_rarity=prize, won_skin=won_skin)
            result_shown = True
            send_result_udp(sender_ip, prize["name"], won_skin)
            time.sleep(4.0)
            for _ in range(6):
                intensity = random.uniform(0.05, 0.25)
                draw_frame(strip, target_scroll, flash=intensity, result_rarity=prize, won_skin=won_skin)
                time.sleep(0.08)
                draw_frame(strip, target_scroll, flash=0.0, result_rarity=prize, won_skin=won_skin)
                time.sleep(0.08)
            time.sleep(2.0)
            break

# ── UDP listener: port 5001 (case open trigger) ───────────────
def udp_listener():
    global pending_ip
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((HOST, PORT))
        print(f"UDP case listener on {HOST}:{PORT} ...")
        while True:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            sender_ip = addr[0]
            print(f"[{sender_ip}:{addr[1]}] {data.decode(errors='replace')}")
            if data.decode(errors="replace").strip() == "1":
                with case_lock:
                    pending_ip = sender_ip
                case_event.set()

# ── UDP listener: port 5004 (progress bar values) ────────────
def udp_progress_listener():
    global progress_value, progress_value2
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((HOST, 5004))
        print(f"UDP progress listener on {HOST}:5004 ...")
        while True:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            try:
                parts = data.decode(errors="replace").strip().split(",")
                num1 = int(float(parts[0]))
                num1 = max(0, min(100, num1))
                num2 = float(parts[1]) if len(parts) > 1 else 0.0
                num2 = max(0.0, min(3.0, num2))
                with progress_lock:
                    progress_value  = num1
                    progress_value2 = num2
                print(f"Progress update: {num1}, {num2}")
            except Exception as e:
                print(f"Progress parse error: {e}")

# ── Main loop ─────────────────────────────────────────────────
def main():
    t1 = threading.Thread(target=udp_listener, daemon=True)
    t2 = threading.Thread(target=udp_progress_listener, daemon=True)
    t1.start()
    t2.start()

    while True:
        if case_event.is_set():
            case_event.clear()
            with case_lock:
                sender_ip = pending_ip
            run_case_open(sender_ip)
            push(Image.new("RGB", (IW, IH), (0, 0, 0)))
            continue

        with progress_lock:
            value  = progress_value
            value2 = progress_value2
        draw_progress(value, value2)
        time.sleep(0.05)

if __name__ == "__main__":
    main()