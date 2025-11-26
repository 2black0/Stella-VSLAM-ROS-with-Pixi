import numpy as np
import cv2
import glob
import time

# ==========================================
# KONFIGURASI PAPAN CATUR (SESUAIKAN DI SINI)
# ==========================================
# Ganti sesuai kertas yang Anda download:
# A4 - 25mm squares -> vertices 10 x 7
CHECKERBOARD = (10, 7)
SQUARE_SIZE = 0.025  # Ukuran kotak dalam meter (25mm = 0.025m)

# Setting Kamera
CAMERA_INDEX = 0
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
MIN_FRAMES = 20  # Kita butuh sampel agak banyak biar akurat
# ==========================================

# Persiapan titik 3D dunia nyata
criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
objp = np.zeros((1, CHECKERBOARD[0] * CHECKERBOARD[1], 3), np.float32)
objp[0,:,:2] = np.mgrid[0:CHECKERBOARD[0], 0:CHECKERBOARD[1]].T.reshape(-1, 2)
objp = objp * SQUARE_SIZE  # Skala sesuai ukuran asli

objpoints = [] # 3d point in real world space
imgpoints = [] # 2d points in image plane.

# Buka Kamera (Pakai V4L2 agar kompatibel RPi)
print("Membuka kamera...")
cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_V4L2)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

if not cap.isOpened():
    print("❌ Gagal membuka kamera.")
    exit()

print(f"\n=== MULAI KALIBRASI ===")
print(f"1. Target: Papan Catur {CHECKERBOARD[0]} x {CHECKERBOARD[1]} (Vertices)")
print(f"2. Ukuran Kotak: {SQUARE_SIZE*1000} mm")
print(f"3. Gerakkan papan: Dekat, Jauh, Miring Kiri/Kanan/Atas/Bawah")
print(f"4. Kumpulkan {MIN_FRAMES} sampel sukses.")
print("   Tekan 'q' untuk batal.\n")

valid_frames = 0
last_capture_time = time.time()

while True:
    ret, frame = cap.read()
    if not ret: break

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    # Cari sudut papan catur
    # Flags diperbanyak agar deteksi lebih jitu
    flags = cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_FAST_CHECK + cv2.CALIB_CB_NORMALIZE_IMAGE
    ret_corners, corners = cv2.findChessboardCorners(gray, CHECKERBOARD, flags)

    # Clone frame untuk visualisasi (jika ada GUI)
    display_frame = frame.copy()

    if ret_corners:
        # Perhalus posisi sudut (Sub-pixel accuracy)
        corners2 = cv2.cornerSubPix(gray, corners, (11,11), (-1,-1), criteria)

        # Gambar garis deteksi
        cv2.drawChessboardCorners(display_frame, CHECKERBOARD, corners2, ret_corners)

        # Ambil sampel setiap 2 detik jika papan terdeteksi stabil
        if time.time() - last_capture_time > 1.5:
            objpoints.append(objp)
            imgpoints.append(corners2)
            valid_frames += 1
            last_capture_time = time.time()
            print(f"✅ Sampel {valid_frames}/{MIN_FRAMES} OK! (Gerakkan papan ke posisi lain)")

            # Efek Flash Visual (Green Border)
            cv2.rectangle(display_frame, (0,0), (FRAME_WIDTH, FRAME_HEIGHT), (0,255,0), 20)
    else:
        # Info jika papan tidak terdeteksi
        cv2.putText(display_frame, "Papan tidak terdeteksi...", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)

    # Logika GUI / Headless
    # Karena via SSH, kita tidak imshow, tapi bisa print status progress bar sederhana
    if ret_corners:
        print(".", end="", flush=True)

    if valid_frames >= MIN_FRAMES:
        print("\n\n🎉 Cukup sampel! Sedang menghitung parameter (tunggu sebentar)...")
        break

cap.release()
cv2.destroyAllWindows()

# --- PROSES KALIBRASI ---
ret, mtx, dist, rvecs, tvecs = cv2.calibrateCamera(objpoints, imgpoints, gray.shape[::-1], None, None)

print("\n==========================================")
print("       HASIL KALIBRASI (COPY INI)")
print("==========================================")
print("Buka file: raspi/lib_rpi/webcam_config.yaml")
print("Ganti bagian Camera parameters dengan angka ini:\n")
print(f"  fx: {mtx[0][0]:.5f}")
print(f"  fy: {mtx[1][1]:.5f}")
print(f"  cx: {mtx[0][2]:.5f}")
print(f"  cy: {mtx[1][2]:.5f}")
print("")
print(f"  k1: {dist[0][0]:.5f}")
print(f"  k2: {dist[0][1]:.5f}")
print(f"  p1: {dist[0][2]:.5f}")
print(f"  p2: {dist[0][3]:.5f}")
print(f"  k3: {dist[0][4]:.5f}")
print("==========================================")
print(f"Error Kalibrasi (RMS): {ret:.4f} pixels")
if ret < 1.0:
    print("✅ Hasil Bagus! (RMS < 1.0)")
else:
    print("⚠️  Hasil Kurang Akurat. Coba kalibrasi ulang dengan pencahayaan lebih baik.")