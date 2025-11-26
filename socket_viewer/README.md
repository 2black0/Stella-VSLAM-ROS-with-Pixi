# Socket Viewer

Socket Viewer adalah antarmuka web untuk memantau data MAVLink, streaming SLAM pose, dan menyiarkan video AirSim secara langsung. Aplikasi ini berjalan sebagai kombinasi Node.js (server HTTP/WebSocket) dan proses bridge `pymavlink`.

## Menjalankan

```bash
# jalankan dari root repo
pixi run -e slam2gps node socket_viewer/app.js
```

Server akan membuka:

- `ws://localhost:3000` – kanal WebSocket utama.
- `http://localhost:3001` – server HTTP untuk publikasi video, API status, dan subscription eksternal.

Pastikan AirSim, SITL ArduPilot, dan semua dependensi (stella-vslam, dsb) sudah berjalan sebelum menyalakan Socket Viewer.

## Tampilan Web

Halaman utama (`http://localhost:3000/`) memuat beberapa panel:

1. **SLAM Pose Panel** – menampilkan posisi dan matriks rotasi yang dikirim dari Visual-SLAM (`map_publish`).
2. **MavLink Data Panel** – menampilkan mode, lat/lon, altitude, heading, dan informasi sensor berbasis MAVLink.
3. **Live Camera Thumbnail** – preview frame dari stream AirSim yang dipublikasikan lewat `frame_publish`.
4. **Control Panel** – kumpulan tombol untuk:
   - `Take Off`, `Guided`, `Auto`, `RTL` – mengirim command MAVLink.
   - Toggle `Calibrate`, `SLAM2GPS`, `Visual-SLAM`.
   - `Save CSV` – mulai/hentikan logging CSV via bridge `pymavlink`.

Panel-panel telemetri dan kontrol menggunakan font monospasi agar mudah dibaca, dengan ukuran panel yang ringkas supaya area kanan layar tidak kosong.

## API HTTP

Beberapa endpoint penting di server HTTP (`http://localhost:3001`):

- `GET /api/telemetry` – snapshot lengkap status MAVLink (lat/lon/alt, mode, status log, dsb).
- `GET /api/sample` – ringkasan singkat yang berisi:
  ```json
  {
    "timestamp_system": 1690000000000,
    "timestamp_slam": 1690000000500,
    "slam_x": 1.23,
    "slam_y": 4.56,
    "slam_z": -0.78,
    "timestamp_mavlink": 1690000000400,
    "gps_lat": -7.28,
    "gps_lon": 112.79,
    "gps_alt": 53.2,
    "alt_rel": 30.1
  }
  ```
  Endpoint ini dipakai oleh script `code/get-slam.py` untuk memonitor pose SLAM dan GPS di terminal.

Endpoint lain (`/api/sample`, `/api/telemetry`) dapat dicurl atau diintegrasikan ke tool lain untuk memantau status tanpa membuka UI web.

## Integrasi Streaming

Aplikasi menerima dua jenis publikasi dari klien eksternal:

1. **`map_publish`** – data SLAM dalam bentuk protobuf (`map_segment.proto`). Payload base64 akan dibroadcast ke UI dan diteruskan ke `pymavlink_bridge` agar timestamp/pose bisa disinkronkan dengan MAVLink.
2. **`frame_publish`** – JPEG buffer base64 (misal dari kamera AirSim) untuk ditampilkan sebagai thumbnail.

## Tips Penggunaan

- Gunakan script pendukung (`code/get-sensor.py`, `code/get-slam.py`) untuk memverifikasi koneksi MAVLink/SLAM lewat terminal.
- Jika ingin menambah perintah baru di UI (misal men-trigger Visual-SLAM), buat endpoint HTTP/Socket baru di `app.js` dan hubungkan tombolnya pada file `public/js/main.js`.
- Log proses Node.js akan menunjukkan informasi `Connected`/`Disconnected` ketika klien WebSocket bergabung atau terputus.

Itu saja! Socket Viewer memberi gambaran cepat status drone, pose SLAM, dan memberikan kontrol dasar langsung dari browser.
