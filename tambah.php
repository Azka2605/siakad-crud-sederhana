<?php
require 'koneksi.php';

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $npm      = trim($_POST['npm']);
    $nama     = trim($_POST['nama']);
    $prodi_id = $_POST['prodi_id'];
    $angkatan = $_POST['angkatan'];
    $email    = trim($_POST['email']);
    $status   = $_POST['status'];

    if ($npm === '' || $nama === '' || $prodi_id === '' || $angkatan === '') {
        $error = 'NPM, nama, prodi, dan angkatan wajib diisi.';
    } else {
        try {
            $stmt = $pdo->prepare(
                "INSERT INTO mahasiswa (npm, nama, prodi_id, angkatan, email, status)
                 VALUES (:npm, :nama, :prodi_id, :angkatan, :email, :status)"
            );
            $stmt->execute([
                'npm'      => $npm,
                'nama'     => $nama,
                'prodi_id' => $prodi_id,
                'angkatan' => $angkatan,
                'email'    => $email !== '' ? $email : null,
                'status'   => $status,
            ]);

            header('Location: index.php?pesan=' . urlencode('Mahasiswa berhasil ditambahkan.'));
            exit;
        } catch (PDOException $e) {
            // Contoh: pelanggaran UNIQUE pada npm/email
            $error = 'Gagal menyimpan: ' . $e->getMessage();
        }
    }
}

// Untuk dropdown prodi
$prodi = $pdo->query("SELECT id, nama FROM prodi WHERE is_aktif ORDER BY nama")->fetchAll();
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Tambah Mahasiswa</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        form { background: #fff; padding: 20px; max-width: 420px; border-radius: 6px; }
        label { display: block; margin-top: 12px; font-weight: bold; }
        input, select { width: 100%; padding: 6px; margin-top: 4px; box-sizing: border-box; }
        button { margin-top: 18px; padding: 8px 16px; background: #27ae60; color: #fff; border: none; border-radius: 4px; cursor: pointer; }
        .error { color: #c0392b; background: #fdecea; padding: 8px; border-radius: 4px; margin-bottom: 10px; }
        a { display: inline-block; margin-top: 15px; }
    </style>
</head>
<body>
    <h1>Tambah Mahasiswa</h1>

    <?php if ($error): ?>
        <p class="error"><?= htmlspecialchars($error) ?></p>
    <?php endif; ?>

    <form method="post">
        <label>NPM</label>
        <input type="text" name="npm" value="<?= htmlspecialchars($_POST['npm'] ?? '') ?>" required>

        <label>Nama</label>
        <input type="text" name="nama" value="<?= htmlspecialchars($_POST['nama'] ?? '') ?>" required>

        <label>Program Studi</label>
        <select name="prodi_id" required>
            <option value="">-- pilih prodi --</option>
            <?php foreach ($prodi as $p): ?>
                <option value="<?= $p['id'] ?>"
                    <?= (isset($_POST['prodi_id']) && $_POST['prodi_id'] == $p['id']) ? 'selected' : '' ?>>
                    <?= htmlspecialchars($p['nama']) ?>
                </option>
            <?php endforeach; ?>
        </select>

        <label>Angkatan</label>
        <input type="number" name="angkatan" min="2000" max="2100"
               value="<?= htmlspecialchars($_POST['angkatan'] ?? date('Y')) ?>" required>

        <label>Email</label>
        <input type="email" name="email" value="<?= htmlspecialchars($_POST['email'] ?? '') ?>">

        <label>Status</label>
        <select name="status">
            <?php foreach (['aktif','cuti','non_aktif','lulus','keluar'] as $s): ?>
                <option value="<?= $s ?>" <?= (isset($_POST['status']) && $_POST['status'] === $s) ? 'selected' : '' ?>>
                    <?= $s ?>
                </option>
            <?php endforeach; ?>
        </select>

        <button type="submit">Simpan</button>
    </form>

    <a href="index.php">&larr; Kembali ke daftar</a>
</body>
</html>