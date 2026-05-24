import time
import math
import smbus2
import socket
import serial
from gpiozero import Button

LAPTOP_IP = "192.168.0.16"

# ── I2C / MPU-6050 ──────────────────────────────────────────────
bus = smbus2.SMBus(1)
ADDR = 0x68
bus.write_byte_data(ADDR, 0x6B, 0)

# ── GPIO buttons (gpiozero — no root needed) ─────────────────────
# pull_up=True mirrors the original PUD_UP config
btn_zero = Button(17, pull_up=True, bounce_time=0.3)
btn2     = Button(27, pull_up=True, bounce_time=0.05)
btn3     = Button(22, pull_up=True, bounce_time=0.05)

# ── DFPlayer Mini (UART) ─────────────────────────────────────────
ser = serial.Serial('/dev/ttyS0', 9600, timeout=1)

def send_cmd(cmd, param1=0, param2=0):
    buf = bytes([0x7E, 0xFF, 0x06, cmd, 0x00, param1, param2, 0xEF])
    ser.write(buf)
    time.sleep(0.1)

send_cmd(0x06, 0, 10)   # set volume (0-30)
print("DFPlayer ready.")

# ── IMU helpers ──────────────────────────────────────────────────
def read_word_signed(reg):
    high = bus.read_byte_data(ADDR, reg)
    low  = bus.read_byte_data(ADDR, reg + 1)
    val  = (high << 8) | low
    return val - 65536 if val >= 32768 else val

# ── State ────────────────────────────────────────────────────────
angle_x = 0.0
angle_y = 0.0
offset_x = 0.0
offset_y = 0.0
prev_time = time.time()
music_playing = False

# ── Zero button callback ─────────────────────────────────────────
def on_zero_pressed():
    global offset_x, offset_y
    offset_x = angle_x
    offset_y = angle_y
    print("\n[Zeroed]", end='\r')

btn_zero.when_pressed = on_zero_pressed

# ── UDP socket ───────────────────────────────────────────────────
PORT = 5000
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print(f"Streaming to {LAPTOP_IP}:{PORT}")

try:
    while True:
        # ── Read IMU ─────────────────────────────────────────────
        ax = read_word_signed(0x3B) / 16384.0
        ay = read_word_signed(0x3D) / 16384.0
        az = read_word_signed(0x3F) / 16384.0
        gx = read_word_signed(0x43) / 131.0
        gy = read_word_signed(0x45) / 131.0

        now = time.time()
        dt  = now - prev_time
        prev_time = now

        acc_angle_x = math.degrees(math.atan2(ay, az))
        acc_angle_y = math.degrees(math.atan2(-ax, az))
        angle_x = 0.96 * (angle_x + gx * dt) + 0.04 * acc_angle_x
        angle_y = 0.96 * (angle_y + gy * dt) + 0.04 * acc_angle_y

        display_x = angle_x - offset_x
        display_y = angle_y - offset_y

        # ── Read buttons ─────────────────────────────────────────
        btn2_pressed = btn2.is_pressed
        btn3_pressed = btn3.is_pressed

        b2 = 1 if btn2_pressed else 0
        b3 = 1 if btn3_pressed else 0

        # ── Music control: play track 1 while BTN2 held ──────────
        if btn2_pressed and not music_playing:
            send_cmd(0x03, 0, 33)   # play track 33
            music_playing = True
        elif not btn2_pressed and music_playing:
            send_cmd(0x16)          # stop playback
            music_playing = False

        # ── UDP send ─────────────────────────────────────────────
        msg = f"{display_x:.2f},{display_y:.2f},{b2},{b3}"
        sock.sendto(msg.encode("utf-8"), (LAPTOP_IP, PORT))

        print(
            f"Roll: {display_x:+7.2f}°  Pitch: {display_y:+7.2f}°  "
            f"BTN2: {b2}  BTN3: {b3}  Music: {'▶' if music_playing else '■'}",
            end='\r'
        )

        time.sleep(0.02)

except KeyboardInterrupt:
    print("\nStopped.")
finally:
    send_cmd(0x16)   # stop music on exit
    ser.close()
    sock.close()
    btn_zero.close()
    btn2.close()
    btn3.close()