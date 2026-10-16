"""Refined, professional Google Play Store asset generator for MetroMitra.
Fixes all font rendering, eliminates tofu characters, creates high-end visual aesthetics.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "play_store_assets"
OUT_DIR.mkdir(exist_ok=True)

LOGO_PATH = ROOT / "app/assets/brand/logo.jpg"
FONT_INTER_PATH = ROOT / "app/assets/fonts/Inter-Variable.ttf"
FONT_HINDI_PATH = ROOT / "app/assets/fonts/NotoSansDevanagari-Variable.ttf"

# Curated palette
NAVY_DEEP = (11, 19, 43)        # #0b132b
NAVY_SURFACE = (28, 37, 65)     # #1c2541
TEXT_WHITE = (255, 255, 255)
TEXT_MUTED = (148, 163, 184)    # #94a3b8
TEXT_DARK = (15, 23, 42)
CYAN_ACCENT = (56, 189, 248)    # #38bdf8
TEAL_PRIMARY = (13, 148, 136)   # #0d9488
BORDER_LIGHT = (226, 232, 240)  # #e2e8f0

# Metro line colors
LINE_YELLOW = (245, 158, 11)    # Yellow
LINE_BLUE = (37, 99, 235)       # Blue
LINE_RED = (225, 29, 72)        # Red
LINE_VIOLET = (147, 51, 234)    # Violet
LINE_MAGENTA = (219, 39, 119)   # Magenta
LINE_GREEN = (22, 163, 74)      # Green

def get_font(size: int, hindi: bool = False):
    try:
        path = FONT_HINDI_PATH if hindi else FONT_INTER_PATH
        return ImageFont.truetype(str(path), size)
    except Exception:
        return ImageFont.load_default()

def draw_text_smart(draw, xy, text: str, size: int, fill, hindi: bool = False):
    """Draw text with appropriate font (Hindi vs English)."""
    f = get_font(size, hindi=hindi)
    draw.text(xy, text, font=f, fill=fill)
    return draw.textlength(text, font=f)

def create_app_icon():
    print("Generating 512x512 App Icon...")
    logo = Image.open(LOGO_PATH).convert("RGB")
    icon = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    target_size = 460
    scaled = logo.resize((target_size, target_size), Image.LANCZOS)
    offset = (512 - target_size) // 2
    icon.paste(scaled, (offset, offset))
    
    out_file = OUT_DIR / "app_icon_512x512.png"
    icon.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

def create_feature_graphic():
    print("Generating 1024x500 Feature Graphic...")
    W, H = 1024, 500
    
    # Modern dark gradient
    canvas = Image.new("RGBA", (W, H), NAVY_DEEP)
    draw = ImageDraw.Draw(canvas)
    
    # Clean decorative subway lines in corners (avoiding text area)
    # Top-right corner tracks
    draw.line([(680, 0), (780, 0), (920, 140), (W, 140)], fill=(LINE_YELLOW[0], LINE_YELLOW[1], LINE_YELLOW[2], 60), width=6)
    draw.line([(760, 0), (840, 0), (960, 120), (W, 120)], fill=(LINE_BLUE[0], LINE_BLUE[1], LINE_BLUE[2], 8), width=8)
    draw.line([(880, 0), (940, 0), (W, 60)], fill=(LINE_RED[0], LINE_RED[1], LINE_RED[2], 6), width=6)
    
    # Bottom corner tracks
    draw.line([(0, 430), (320, 430), (440, H)], fill=(LINE_BLUE[0], LINE_BLUE[1], LINE_BLUE[2], 70), width=8)
    draw.line([(0, 460), (350, 460), (470, H)], fill=(LINE_MAGENTA[0], LINE_MAGENTA[1], LINE_MAGENTA[2], 60), width=6)
    draw.line([(550, H), (700, 390), (W, 390)], fill=(LINE_VIOLET[0], LINE_VIOLET[1], LINE_VIOLET[2], 50), width=7)

    # Soft radial glow behind text
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse([450, 60, 980, 440], fill=(14, 116, 144, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    canvas.paste(glow, (0, 0), glow)

    # Logo Card on left with soft drop shadow
    logo = Image.open(LOGO_PATH).convert("RGBA")
    logo_size = 280
    logo_scaled = logo.resize((logo_size, logo_size), Image.LANCZOS)
    
    card_w, card_h = 320, 320
    card_x, card_y = 65, (H - card_h) // 2
    
    # Shadow
    shadow = Image.new("RGBA", (card_w + 30, card_h + 30), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([15, 15, card_w + 15, card_h + 15], radius=36, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.paste(shadow, (card_x - 15, card_y - 15), shadow)
    
    # White rounded card
    card = Image.new("RGBA", (card_w, card_h), (255, 255, 255, 255))
    mask = Image.new("L", (card_w, card_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, card_w, card_h], radius=32, fill=255)
    card.paste(logo_scaled, ((card_w - logo_size) // 2, (card_h - logo_size) // 2), logo_scaled)
    canvas.paste(card, (card_x, card_y), mask)
    
    # Right-side text presentation
    text_x = 425
    draw.text((text_x, 85), "MetroMitra", font=get_font(60), fill=TEXT_WHITE)
    draw.text((text_x, 158), "Delhi Metro — Fast, Simple & Offline", font=get_font(26), fill=CYAN_ACCENT)
    draw.text((text_x, 198), "Navigate the entire Delhi Metro network without internet.", font=get_font(20), fill=TEXT_MUTED)
    
    # Feature Badges
    badges = [
        ("OFFLINE", "100% Offline Routes"),
        ("MAP", "Interactive Vector Map"),
        ("SEARCH", "English & Hindi Search"),
        ("PRIVACY", "Zero Ads · No Sign-Up")
    ]
    
    bx = text_x
    by = 260
    f_tag = get_font(13)
    f_lbl = get_font(19)
    
    # Row 1
    for tag, label in badges[:2]:
        pill_w = 265
        draw.rounded_rectangle([bx, by, bx + pill_w, by + 48], radius=14, fill=NAVY_SURFACE, outline=(71, 85, 105), width=1)
        draw.rounded_rectangle([bx + 10, by + 10, bx + 80, by + 38], radius=8, fill=(14, 116, 144))
        draw.text((bx + 18, by + 16), tag, font=f_tag, fill=TEXT_WHITE)
        draw.text((bx + 90, by + 14), label, font=f_lbl, fill=TEXT_WHITE)
        bx += pill_w + 16
        
    # Row 2
    bx = text_x
    by = 325
    for tag, label in badges[2:]:
        pill_w = 265
        draw.rounded_rectangle([bx, by, bx + pill_w, by + 48], radius=14, fill=NAVY_SURFACE, outline=(71, 85, 105), width=1)
        draw.rounded_rectangle([bx + 10, by + 10, bx + 80, by + 38], radius=8, fill=(14, 116, 144))
        draw.text((bx + 18, by + 16), tag, font=f_tag, fill=TEXT_WHITE)
        draw.text((bx + 90, by + 14), label, font=f_lbl, fill=TEXT_WHITE)
        bx += pill_w + 16
        
    draw.text((text_x, 412), "Independent transit utility for Delhi NCR commuters", font=get_font(16), fill=(100, 116, 139))

    out_file = OUT_DIR / "feature_graphic_1024x500.png"
    canvas.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

def draw_phone_frame(canvas, phone_box, screen_content):
    """Draw a clean modern smartphone frame around screen_content."""
    px, py, pw, ph = phone_box
    
    # Drop shadow
    shadow = Image.new("RGBA", (pw + 50, ph + 50), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_draw.rounded_rectangle([15, 15, pw + 35, ph + 35], radius=50, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas.paste(shadow, (px - 25, py - 10), shadow)
    
    # Phone Body (dark metallic frame)
    body = Image.new("RGBA", (pw, ph), (18, 24, 38, 255))
    bdraw = ImageDraw.Draw(body)
    bdraw.rounded_rectangle([0, 0, pw, ph], radius=46, fill=(18, 24, 38, 255), outline=(71, 85, 105, 255), width=4)
    
    bezel = 14
    sw, sh = pw - (bezel * 2), ph - (bezel * 2)
    scaled_screen = screen_content.resize((sw, sh), Image.LANCZOS)
    
    screen_mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle([0, 0, sw, sh], radius=36, fill=255)
    body.paste(scaled_screen, (bezel, bezel), screen_mask)
    
    # Camera Island / Notch
    island_w, island_h = 120, 26
    ix = (pw - island_w) // 2
    bdraw.rounded_rectangle([ix, bezel + 8, ix + island_w, bezel + 8 + island_h], radius=13, fill=(10, 15, 26, 255))
    bdraw.ellipse([ix + island_w - 22, bezel + 15, ix + island_w - 12, bezel + 25], fill=(30, 41, 59, 255))
    
    frame_mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(frame_mask).rounded_rectangle([0, 0, pw, ph], radius=46, fill=255)
    canvas.paste(body, (px, py), frame_mask)

def create_screenshot_1_routes():
    W, H = 1080, 1920
    canvas = Image.new("RGBA", (W, H), NAVY_DEEP)
    draw = ImageDraw.Draw(canvas)
    
    # Radial glow
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([150, 50, 930, 750], fill=(14, 116, 144, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    canvas.paste(glow, (0, 0), glow)
    
    # Marketing header
    f_badge = get_font(24)
    f_hero = get_font(52)
    f_sub = get_font(28)
    
    badge_text = "OFFLINE ROUTE PLANNER"
    bw = draw.textlength(badge_text, font=f_badge) + 36
    bx = (W - bw) // 2
    draw.rounded_rectangle([bx, 75, bx + bw, 75 + 44], radius=22, fill=NAVY_SURFACE, outline=CYAN_ACCENT, width=2)
    draw.text((bx + 18, 83), badge_text, font=f_badge, fill=CYAN_ACCENT)
    
    title = "Fastest Routes Without Confusion"
    tw = draw.textlength(title, font=f_hero)
    draw.text(((W - tw) // 2, 140), title, font=f_hero, fill=TEXT_WHITE)
    
    sub = "Clear interchange guidance, travel time & stops"
    sw = draw.textlength(sub, font=f_sub)
    draw.text(((W - sw) // 2, 212), sub, font=f_sub, fill=TEXT_MUTED)
    
    # Phone Screen Content
    SW, SH = 700, 1440
    screen = Image.new("RGBA", (SW, SH), (248, 250, 252, 255))
    sdraw = ImageDraw.Draw(screen)
    
    # Status bar
    sdraw.text((40, 22), "09:41", font=get_font(20), fill=TEXT_DARK)
    sdraw.text((SW - 120, 22), "5G  100%", font=get_font(20), fill=TEXT_DARK)
    
    # Brand bar
    sdraw.text((40, 70), "MetroMitra", font=get_font(32), fill=(14, 116, 144))
    
    # Route Selection Card
    card_y = 125
    sdraw.rounded_rectangle([32, card_y, SW - 32, card_y + 190], radius=24, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    
    # From dot
    sdraw.ellipse([56, card_y + 36, 76, card_y + 56], fill=LINE_GREEN)
    sdraw.text((95, card_y + 24), "FROM STATION", font=get_font(16), fill=TEXT_MUTED)
    sdraw.text((95, card_y + 46), "Rajiv Chowk (Connaught Place)", font=get_font(22), fill=TEXT_DARK)
    
    # Connecting dashed line
    for dy in range(card_y + 64, card_y + 116, 8):
        sdraw.line([(66, dy), (66, dy + 4)], fill=(203, 213, 225), width=3)
        
    # To dot
    sdraw.ellipse([56, card_y + 124, 76, card_y + 144], fill=LINE_RED)
    sdraw.text((95, card_y + 112), "TO STATION", font=get_font(16), fill=TEXT_MUTED)
    sdraw.text((95, card_y + 134), "Hauz Khas", font=get_font(22), fill=TEXT_DARK)
    
    # Quick Route Summary Card
    res_y = 340
    sdraw.rounded_rectangle([32, res_y, SW - 32, res_y + 110], radius=20, fill=(240, 253, 250), outline=(153, 246, 228), width=2)
    sdraw.rounded_rectangle([52, res_y + 18, 185, res_y + 44], radius=8, fill=(13, 148, 136))
    sdraw.text((62, res_y + 22), "FASTEST ROUTE", font=get_font(14), fill=TEXT_WHITE)
    
    sdraw.text((52, res_y + 54), "22 min", font=get_font(34), fill=TEXT_DARK)
    sdraw.text((185, res_y + 64), "• 9 Stations • Direct (0 Changes)", font=get_font(19), fill=TEXT_MUTED)
    
    # Journey Timeline
    tl_y = 475
    sdraw.text((36, tl_y), "Recommended Itinerary", font=get_font(24), fill=TEXT_DARK)
    
    # Step 1: Yellow Line
    st1_y = tl_y + 45
    sdraw.rounded_rectangle([32, st1_y, SW - 32, st1_y + 140], radius=20, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.rounded_rectangle([32, st1_y, 46, st1_y + 140], radius=6, fill=LINE_YELLOW)
    sdraw.text((64, st1_y + 20), "Board Yellow Line (Towards HUDA City Centre)", font=get_font(20), fill=TEXT_DARK)
    sdraw.text((64, st1_y + 50), "Platform 2  •  Departing in 3 min", font=get_font(18), fill=(14, 116, 144))
    sdraw.text((64, st1_y + 88), "Ride 9 stops: Patel Chowk, Central Sec, Udyog Bhawan...", font=get_font(17), fill=TEXT_MUTED)
    
    # Step 2: Hauz Khas Alight
    st2_y = st1_y + 165
    sdraw.rounded_rectangle([32, st2_y, SW - 32, st2_y + 130], radius=20, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.rounded_rectangle([32, st2_y, 46, st2_y + 130], radius=6, fill=LINE_MAGENTA)
    sdraw.text((64, st2_y + 20), "Arrive at Hauz Khas", font=get_font(20), fill=TEXT_DARK)
    sdraw.text((64, st2_y + 50), "Interchange with Magenta Line available", font=get_font(17), fill=TEXT_MUTED)
    sdraw.text((64, st2_y + 82), "Exit Gate 1 & 2 for IIT Delhi & Aurobindo Marg", font=get_font(17), fill=LINE_GREEN)
    
    # Action Button
    btn_y = SH - 150
    sdraw.rounded_rectangle([36, btn_y, SW - 36, btn_y + 70], radius=22, fill=(14, 116, 144))
    sdraw.text((SW // 2 - 85, btn_y + 20), "START JOURNEY", font=get_font(22), fill=TEXT_WHITE)
    
    # Frame & Paste
    pw, ph = 760, 1550
    px = (W - pw) // 2
    py = 295
    draw_phone_frame(canvas, (px, py, pw, ph), screen)
    
    out_file = OUT_DIR / "screenshot_1_routes_1080x1920.png"
    canvas.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

def create_screenshot_2_map():
    W, H = 1080, 1920
    canvas = Image.new("RGBA", (W, H), NAVY_DEEP)
    draw = ImageDraw.Draw(canvas)
    
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([150, 50, 930, 750], fill=(37, 99, 235, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    canvas.paste(glow, (0, 0), glow)
    
    f_badge = get_font(24)
    f_hero = get_font(52)
    f_sub = get_font(28)
    
    badge_text = "INTERACTIVE VECTOR MAP"
    bw = draw.textlength(badge_text, font=f_badge) + 36
    bx = (W - bw) // 2
    draw.rounded_rectangle([bx, 75, bx + bw, 75 + 44], radius=22, fill=NAVY_SURFACE, outline=(96, 165, 250), width=2)
    draw.text((bx + 18, 83), badge_text, font=f_badge, fill=(96, 165, 250))
    
    title = "Smooth Zoom & Live Network Map"
    tw = draw.textlength(title, font=f_hero)
    draw.text(((W - tw) // 2, 140), title, font=f_hero, fill=TEXT_WHITE)
    
    sub = "Offline vector rendering of all lines and stations"
    sw = draw.textlength(sub, font=f_sub)
    draw.text(((W - sw) // 2, 212), sub, font=f_sub, fill=TEXT_MUTED)
    
    SW, SH = 700, 1440
    screen = Image.new("RGBA", (SW, SH), (241, 245, 249, 255))
    sdraw = ImageDraw.Draw(screen)
    
    # Subtle map grid
    for x in range(0, SW, 80):
        sdraw.line([(x, 0), (x, SH)], fill=(226, 232, 240, 180), width=1)
    for y in range(0, SH, 80):
        sdraw.line([(0, y), (SW, y)], fill=(226, 232, 240, 180), width=1)
        
    # Metro Line tracks
    # Blue Line (horizontal)
    sdraw.line([(30, 520), (320, 520), (480, 680), (670, 680)], fill=LINE_BLUE, width=12)
    # Yellow Line (vertical)
    sdraw.line([(320, 120), (320, 520), (320, 1020), (480, 1320)], fill=LINE_YELLOW, width=12)
    # Red Line (diagonal top)
    sdraw.line([(80, 240), (420, 240), (640, 440)], fill=LINE_RED, width=12)
    # Violet Line
    sdraw.line([(320, 680), (540, 680), (540, 1260)], fill=LINE_VIOLET, width=10)
    # Magenta Line
    sdraw.line([(80, 1020), (320, 1020), (640, 1020)], fill=LINE_MAGENTA, width=10)
    
    stations = [
        ("Kashmere Gate", 320, 240, True, "Red & Yellow"),
        ("Chandni Chowk", 320, 340, False, ""),
        ("New Delhi", 320, 430, False, "Railway Connect"),
        ("Rajiv Chowk", 320, 520, True, "Yellow & Blue"),
        ("Mandi House", 480, 520, True, "Blue & Violet"),
        ("Central Secretariat", 320, 680, True, "Yellow & Violet"),
        ("Hauz Khas", 320, 1020, True, "Yellow & Magenta"),
        ("Botanical Garden", 540, 1020, True, "Blue & Magenta"),
    ]
    for name, sx, sy, is_inter, sub_info in stations:
        if is_inter:
            sdraw.ellipse([sx - 18, sy - 18, sx + 18, sy + 18], fill=(255, 255, 255), outline=(15, 23, 42), width=4)
            sdraw.ellipse([sx - 8, sy - 8, sx + 8, sy + 8], fill=LINE_RED)
            sdraw.text((sx + 26, sy - 14), name, font=get_font(21), fill=TEXT_DARK)
        else:
            sdraw.ellipse([sx - 9, sy - 9, sx + 9, sy + 9], fill=(255, 255, 255), outline=(15, 23, 42), width=3)
            sdraw.text((sx + 20, sy - 12), name, font=get_font(18), fill=TEXT_MUTED)

    # Search bar on top
    sdraw.rounded_rectangle([32, 55, SW - 32, 115], radius=20, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.text((60, 72), "Search any station on map...", font=get_font(20), fill=TEXT_MUTED)
    
    # Zoom controls
    mc_x = SW - 85
    sdraw.rounded_rectangle([mc_x, 150, mc_x + 55, 270], radius=16, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.text((mc_x + 18, 160), "+", font=get_font(28), fill=TEXT_DARK)
    sdraw.line([(mc_x + 8, 210), (mc_x + 47, 210)], fill=BORDER_LIGHT, width=2)
    sdraw.text((mc_x + 20, 220), "-", font=get_font(28), fill=TEXT_DARK)
    
    # Bottom Station Inspector Card
    sh_y = SH - 270
    sdraw.rounded_rectangle([24, sh_y, SW - 24, SH - 24], radius=28, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.text((50, sh_y + 24), "Rajiv Chowk", font=get_font(28), fill=TEXT_DARK)
    sdraw.text((50, sh_y + 62), "Major Interchange  •  Connaught Place", font=get_font(18), fill=TEXT_MUTED)
    
    # Line tags
    sdraw.rounded_rectangle([50, sh_y + 100, 180, sh_y + 140], radius=10, fill=LINE_YELLOW)
    sdraw.text((64, sh_y + 110), "Yellow Line", font=get_font(16), fill=TEXT_DARK)
    sdraw.rounded_rectangle([195, sh_y + 100, 310, sh_y + 140], radius=10, fill=LINE_BLUE)
    sdraw.text((210, sh_y + 110), "Blue Line", font=get_font(16), fill=TEXT_WHITE)
    
    # Actions
    sdraw.rounded_rectangle([50, sh_y + 160, 340, sh_y + 220], radius=16, fill=(14, 116, 144))
    sdraw.text((95, sh_y + 178), "ROUTE FROM HERE", font=get_font(18), fill=TEXT_WHITE)
    sdraw.rounded_rectangle([360, sh_y + 160, SW - 50, sh_y + 220], radius=16, fill=(241, 245, 249), outline=BORDER_LIGHT, width=2)
    sdraw.text((410, sh_y + 178), "STATION DETAILS", font=get_font(18), fill=TEXT_DARK)

    pw, ph = 760, 1550
    px = (W - pw) // 2
    py = 295
    draw_phone_frame(canvas, (px, py, pw, ph), screen)
    
    out_file = OUT_DIR / "screenshot_2_map_1080x1920.png"
    canvas.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

def create_screenshot_3_stations():
    W, H = 1080, 1920
    canvas = Image.new("RGBA", (W, H), NAVY_DEEP)
    draw = ImageDraw.Draw(canvas)
    
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([150, 50, 930, 750], fill=(225, 29, 72, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    canvas.paste(glow, (0, 0), glow)
    
    f_badge = get_font(24)
    f_hero = get_font(52)
    f_sub = get_font(28)
    
    badge_text = "STATION GUIDE & FACILITIES"
    bw = draw.textlength(badge_text, font=f_badge) + 36
    bx = (W - bw) // 2
    draw.rounded_rectangle([bx, 75, bx + bw, 75 + 44], radius=22, fill=NAVY_SURFACE, outline=(251, 113, 133), width=2)
    draw.text((bx + 18, 83), badge_text, font=f_badge, fill=(251, 113, 133))
    
    title = "Gates, Platforms & Accessibility"
    tw = draw.textlength(title, font=f_hero)
    draw.text(((W - tw) // 2, 140), title, font=f_hero, fill=TEXT_WHITE)
    
    sub = "Find the correct exit gate for your destination"
    sw = draw.textlength(sub, font=f_sub)
    draw.text(((W - sw) // 2, 212), sub, font=f_sub, fill=TEXT_MUTED)
    
    SW, SH = 700, 1440
    screen = Image.new("RGBA", (SW, SH), (248, 250, 252, 255))
    sdraw = ImageDraw.Draw(screen)
    
    sdraw.text((40, 22), "09:41", font=get_font(20), fill=TEXT_DARK)
    sdraw.text((SW - 120, 22), "5G  100%", font=get_font(20), fill=TEXT_DARK)
    
    sdraw.text((40, 70), "Station Guide", font=get_font(30), fill=TEXT_DARK)
    
    # Station title card
    st_y = 125
    sdraw.rounded_rectangle([32, st_y, SW - 32, st_y + 175], radius=24, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
    sdraw.text((56, st_y + 22), "Kashmere Gate", font=get_font(34), fill=TEXT_DARK)
    sdraw.text((56, st_y + 64), "3-Line Mega Interchange Hub", font=get_font(20), fill=TEXT_MUTED)
    
    # Connecting line pills
    sdraw.rounded_rectangle([56, st_y + 110, 175, st_y + 150], radius=10, fill=LINE_RED)
    sdraw.text((72, st_y + 120), "Red Line", font=get_font(16), fill=TEXT_WHITE)
    sdraw.rounded_rectangle([190, st_y + 110, 320, st_y + 150], radius=10, fill=LINE_YELLOW)
    sdraw.text((205, st_y + 120), "Yellow Line", font=get_font(16), fill=TEXT_DARK)
    sdraw.rounded_rectangle([335, st_y + 110, 465, st_y + 150], radius=10, fill=LINE_VIOLET)
    sdraw.text((350, st_y + 120), "Violet Line", font=get_font(16), fill=TEXT_WHITE)
    
    # Gates Section
    g_y = 330
    sdraw.text((36, g_y), "Exit Gates & Nearby Locations", font=get_font(24), fill=TEXT_DARK)
    
    gates = [
        ("Gate 1", "ISBT Kashmere Gate Bus Terminal", "Lifts available  •  Step-free access"),
        ("Gate 2", "Old Delhi Railway Station road", "Auto, Taxi & E-Rickshaw stand"),
        ("Gate 3", "Lala Hardev Sahai Marg", "Stairs access only"),
        ("Gate 4", "GPO & Heritage Court", "Ramp access  •  Wide walkway"),
    ]
    cur_y = g_y + 40
    for gate, landmark, notes in gates:
        sdraw.rounded_rectangle([32, cur_y, SW - 32, cur_y + 105], radius=18, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
        sdraw.rounded_rectangle([48, cur_y + 18, 140, cur_y + 54], radius=10, fill=(240, 253, 250))
        sdraw.text((58, cur_y + 24), gate, font=get_font(18), fill=(13, 148, 136))
        sdraw.text((155, cur_y + 20), landmark, font=get_font(20), fill=TEXT_DARK)
        sdraw.text((155, cur_y + 56), notes, font=get_font(16), fill=TEXT_MUTED)
        cur_y += 120
        
    # Facilities Section
    f_y = cur_y + 15
    sdraw.text((36, f_y), "Verified Facilities", font=get_font(24), fill=TEXT_DARK)
    facs = [
        ("[ACC]", "Step-free wheelchair accessibility"),
        ("[LIFT]", "Lifts and escalators on all platforms"),
        ("[REST]", "Public restrooms inside paid area"),
        ("[PARK]", "Parking available at designated gates"),
    ]
    fy_cur = f_y + 40
    for tag, desc in facs:
        sdraw.rounded_rectangle([32, fy_cur, SW - 32, fy_cur + 55], radius=14, fill=(255, 255, 255), outline=BORDER_LIGHT, width=1)
        sdraw.rounded_rectangle([44, fy_cur + 10, 110, fy_cur + 45], radius=8, fill=(241, 245, 249))
        sdraw.text((54, fy_cur + 16), tag, font=get_font(14), fill=(14, 116, 144))
        sdraw.text((125, fy_cur + 16), desc, font=get_font(18), fill=TEXT_DARK)
        fy_cur += 68

    pw, ph = 760, 1550
    px = (W - pw) // 2
    py = 295
    draw_phone_frame(canvas, (px, py, pw, ph), screen)
    
    out_file = OUT_DIR / "screenshot_3_stations_1080x1920.png"
    canvas.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

def create_screenshot_4_bilingual():
    W, H = 1080, 1920
    canvas = Image.new("RGBA", (W, H), NAVY_DEEP)
    draw = ImageDraw.Draw(canvas)
    
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([150, 50, 930, 750], fill=(22, 163, 74, 45))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    canvas.paste(glow, (0, 0), glow)
    
    f_badge = get_font(24)
    f_hero = get_font(52)
    f_sub = get_font(28)
    
    badge_text = "BILINGUAL SEARCH & ASSISTANT"
    bw = draw.textlength(badge_text, font=f_badge) + 36
    bx = (W - bw) // 2
    draw.rounded_rectangle([bx, 75, bx + bw, 75 + 44], radius=22, fill=NAVY_SURFACE, outline=(74, 222, 128), width=2)
    draw.text((bx + 18, 83), badge_text, font=f_badge, fill=(74, 222, 128))
    
    title = "Search Any Station In Any Script"
    tw = draw.textlength(title, font=f_hero)
    draw.text(((W - tw) // 2, 140), title, font=f_hero, fill=TEXT_WHITE)
    
    sub = "Type in English or Hindi with instant matching"
    sw = draw.textlength(sub, font=f_sub)
    draw.text(((W - sw) // 2, 212), sub, font=f_sub, fill=TEXT_MUTED)
    
    SW, SH = 700, 1440
    screen = Image.new("RGBA", (SW, SH), (248, 250, 252, 255))
    sdraw = ImageDraw.Draw(screen)
    
    sdraw.text((40, 22), "09:41", font=get_font(20), fill=TEXT_DARK)
    sdraw.text((SW - 120, 22), "5G  100%", font=get_font(20), fill=TEXT_DARK)
    
    # Search input bar with query
    sdraw.rounded_rectangle([32, 70, SW - 32, 140], radius=20, fill=(255, 255, 255), outline=(14, 116, 144), width=3)
    sdraw.text((55, 90), "Hauz Khas", font=get_font(26), fill=TEXT_DARK)
    sdraw.text((SW - 80, 92), "X", font=get_font(22), fill=TEXT_MUTED)
    
    # Results list
    res = [
        ("Hauz Khas", "Yellow Line • Magenta Line", "Interchange"),
        ("Green Park", "Yellow Line", "Next Station"),
        ("Malviya Nagar", "Yellow Line", "Previous Station"),
        ("Panchsheel Park", "Magenta Line", "Direct Connect"),
    ]
    ry = 170
    sdraw.text((36, ry), "Instant Station Results", font=get_font(20), fill=TEXT_MUTED)
    ry += 35
    for en, lines, badge in res:
        sdraw.rounded_rectangle([32, ry, SW - 32, ry + 105], radius=18, fill=(255, 255, 255), outline=BORDER_LIGHT, width=2)
        sdraw.text((54, ry + 18), en, font=get_font(24), fill=TEXT_DARK)
        sdraw.text((54, ry + 56), lines, font=get_font(18), fill=(14, 116, 144))
        
        bw = sdraw.textlength(badge, font=get_font(14)) + 24
        sdraw.rounded_rectangle([SW - 54 - bw, ry + 22, SW - 54, ry + 54], radius=8, fill=(241, 245, 249))
        sdraw.text((SW - 42 - bw, ry + 28), badge, font=get_font(14), fill=TEXT_MUTED)
        ry += 120
        
    # Offline transit assistant card
    ast_y = ry + 25
    sdraw.rounded_rectangle([32, ast_y, SW - 32, ast_y + 265], radius=24, fill=(240, 253, 250), outline=(153, 246, 228), width=2)
    sdraw.text((56, ast_y + 24), "OFFLINE TRANSIT ASSISTANT", font=get_font(18), fill=(13, 148, 136))
    
    # Question bubble
    sdraw.rounded_rectangle([56, ast_y + 60, SW - 56, ast_y + 115], radius=16, fill=(255, 255, 255), outline=(204, 251, 241), width=1)
    sdraw.text((74, ast_y + 75), "\"What is the last train from Rajiv Chowk?\"", font=get_font(18), fill=TEXT_DARK)
    
    # Verified Answer
    sdraw.text((56, ast_y + 135), "Verified Answer (From local schedule):", font=get_font(18), fill=TEXT_DARK)
    ans1 = "• Towards Samaypur Badli: Last departure at 23:25"
    ans2 = "• Towards Millennium City Centre: Last departure at 23:30"
    sdraw.text((56, ast_y + 168), ans1, font=get_font(17), fill=TEXT_MUTED)
    sdraw.text((56, ast_y + 198), ans2, font=get_font(17), fill=TEXT_MUTED)
    sdraw.text((56, ast_y + 234), "Zero data fabrication. Always verified from dataset.", font=get_font(14), fill=(13, 148, 136))

    pw, ph = 760, 1550
    px = (W - pw) // 2
    py = 295
    draw_phone_frame(canvas, (px, py, pw, ph), screen)
    
    out_file = OUT_DIR / "screenshot_4_bilingual_1080x1920.png"
    canvas.save(out_file, "PNG", optimize=True)
    print(f"Saved: {out_file}")

if __name__ == "__main__":
    create_app_icon()
    create_feature_graphic()
    create_screenshot_1_routes()
    create_screenshot_2_map()
    create_screenshot_3_stations()
    create_screenshot_4_bilingual()
    print("\nAll refined Play Store assets generated successfully!")
