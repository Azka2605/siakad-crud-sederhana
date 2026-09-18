# siakad-crud-sederhana

CRUD PHP native + PostgreSQL untuk data **mahasiswa**, dibuat di atas skema `siakadu`
(lihat `01_skema.sql` / `02_prosedur.sql`).

## Struktur file

| File          | Fungsi                                   |
|---------------|-------------------------------------------|
| `koneksi.php` | Koneksi PDO ke PostgreSQL                  |
| `index.php`   | Menampilkan daftar mahasiswa (Read)        |
| `tambah.php`  | Form + proses tambah mahasiswa (Create)    |
| `update.php`  | Form + proses ubah data mahasiswa (Update) |
| `hapus.php`   | Proses hapus mahasiswa (Delete)            |

## Persiapan

1. Pastikan schema `siakadu` sudah dibuat (jalankan `01_skema.sql`).
2. Isi minimal satu baris di tabel `prodi`, karena form tambah/edit memerlukan
   dropdown prodi, contoh:

   ```sql
   INSERT INTO prodi (kode, nama, jenjang) VALUES ('TI', 'Teknik Informatika', 'S1');
   ```

3. Buka `koneksi.php`, sesuaikan `$host`, `$dbname`, `$user`, `$pass` dengan
   environment Anda.

## Menjalankan

Dengan PHP built-in server (butuh ekstensi `pdo_pgsql` aktif):

```bash
php -S localhost:8000
```

Buka `http://localhost:8000/index.php`.

## Catatan

- Semua query pakai *prepared statement* (`PDO::prepare`), aman dari SQL injection.
- `hapus.php` akan gagal dengan pesan yang jelas kalau mahasiswa masih punya
  baris terkait di tabel lain (KRS, nilai) karena foreign key `ON DELETE` di
  tabel-tabel tersebut tidak diset cascade dari `mahasiswa`.
- Ini contoh CRUD dasar untuk satu tabel saja. Modul lain (kelas, KRS, nilai)
  bisa dibuat dengan pola file yang sama.