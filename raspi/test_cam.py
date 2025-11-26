import cv2
import sys
import time

print("Mencoba membuka /dev/video0 dengan backend V4L2...")

# FIX: Tambahkan cv2.CAP_V4L2 untuk memaksa backend Linux
cap = cv2.VideoCapture(0, cv2.CAP_V4L2)

# Beri waktu kamera untuk "pemanasan" (warmup)
time.sleep(1)

if not cap.isOpened():
    print("❌ Error: Masih tidak bisa membuka kamera.")
    print("Saran: Coba jalankan 'ls -l /dev/video0' dan pastikan user Anda punya akses rw.")
    sys.exit()

# Set resolusi (Webcam JETE biasanya support 640x480 atau 1280x720)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

# Cek resolusi aktual yang didapat
w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
print(f"✅ Kamera terbuka! Resolusi aktif: {int(w)}x{int(h)}")

# Ambil 1 frame untuk memastikan stream data masuk
ret, frame = cap.read()
if ret:
    print("✅ Frame berhasil ditangkap (Data stream OK).")
    print("Tekan 'q' untuk keluar.")
else:
    print("⚠️  Kamera terbuka tapi frame kosong (Blank).")

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Jika Anda menjalankan ini via SSH tanpa X11 forwarding, baris ini akan error.
    # Namun script tetap akan print log di atas.
    try:
        cv2.imshow('Test Webcam', frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
    except Exception:
        pass # Ignore GUI error on headless

cap.release()
cv2.destroyAllWindows()