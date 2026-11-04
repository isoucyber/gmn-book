"""Gera os icones do GMN BOOK (livro aberto estilizado, azul-petroleo + verde-agua)."""
from PIL import Image, ImageDraw
import sys, os

PETROL = (11, 79, 92)
DEEP = (7, 52, 61)
AQUA = (46, 196, 182)
WHITE = (255, 255, 255)

def book(draw, s, ox=0, oy=0, scale=1.0):
    # Livro aberto: duas paginas em perspectiva + marcador verde-agua.
    def P(x, y):
        return (ox + x * s * scale, oy + y * s * scale)
    left = [P(0.18, 0.30), P(0.48, 0.36), P(0.48, 0.78), P(0.18, 0.72)]
    right = [P(0.52, 0.36), P(0.82, 0.30), P(0.82, 0.72), P(0.52, 0.78)]
    draw.polygon(left, fill=WHITE)
    draw.polygon(right, fill=(225, 244, 242))
    for i in range(3):
        y = 0.45 + i * 0.08
        draw.line([P(0.24, y - 0.02), P(0.43, y + 0.02)], fill=PETROL, width=max(2, int(s * scale * 0.018)))
    # marcador
    draw.polygon([P(0.63, 0.33), P(0.71, 0.315), P(0.71, 0.55), P(0.67, 0.51), P(0.63, 0.56)], fill=AQUA)

def full_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(size * 0.22)
    # fundo em degrade diagonal
    grad = Image.new('RGBA', (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        c = tuple(int(PETROL[i] * (1 - t) + DEEP[i] * t) for i in range(3)) + (255,)
        gd.line([(0, y), (size, y)], fill=c)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    img.paste(grad, (0, 0), mask)
    book(d, size)
    return img

def foreground(size):
    # Area segura do icone adaptativo Android: conteudo dentro dos 66% centrais.
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inner = size * 0.62
    off = (size - inner) / 2
    book(d, inner, off, off)
    return img

out = sys.argv[1] if len(sys.argv) > 1 else 'assets/brand'
os.makedirs(out, exist_ok=True)
full_icon(1024).save(os.path.join(out, 'icon.png'))
foreground(1024).save(os.path.join(out, 'icon_foreground.png'))
full_icon(256).save(os.path.join(out, 'icon_256.png'))
full_icon(512).save(os.path.join(out, 'app_icon.ico'), sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
print('ok')
