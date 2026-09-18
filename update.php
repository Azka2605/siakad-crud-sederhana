<?php
require 'koneksi.php';

$id = $_GET['id'] ?? $_POST['id'] ?? null;
if (!$id) {
    header('Location: index.php?pesan=' . urlencode('ID mahasiswa tidak valid.'));
    exit;
}

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
                "UPDATE mahasiswa
                    SET npm = :npm, nama = :nama, prodi_id = :prodi_id,
                        angkatan = :angkatan, email = :email, status = :status
                  WHERE id = :id"
            );
            $stmt->execute([
                'npm'      => $npm,
                'nama'     => $nama,
                'prodi_id' => $prodi_id,
                'angkatan' => $angkatan,
                'email'    => $email !== '' ? $email : null,
                'status'   => $status,
                'id'       => $id,
            ]);

            header('Location: index.php?pesan=' . urlencode('Data mahasiswa berhasil diperbarui.'));
            exit;
        } catch (PDOException $e) {
            $error = 'Gagal menyimpan: ' . $e->getMessage();
        }
    }
    $mhs = $_POST; // supaya form tetap terisi kalau ada error validasi
} else {
    $stmt = $pdo->prepare("SELECT * FROM mahasiswa WHERE id = :id");
    $stmt->execute(['id' => $id]);
    $mhs = $stmt->fetch();

    if (!$mhs) {
        header('Location: index.php?pesan=' . urlencode('Mahasiswa tidak ditemukan.'));
        exit;
    }
}

$prodi = $pdo->query("SELECT id, nama FROM prodi WHERE is_aktif ORDER BY nama")->fetchAll();
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Edit Mahasiswa</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        form { background: #fff; padding: 20px; max-width: 420px; border-radius: 6px; }
        label { display: block; margin-top: 12px; font-weight: bold; }
        input, select { width: 100%; padding: 6px; margin-top: 4px; box-sizing: border-box; }
        button { margin-top: 18px; padding: 8px 16px; background: #2980b9; color: #fff; border: none; border-radius: 4px; cursor: pointer; }
        .error { color: #c0392b; background: #fdecea; padding: 8px; border-radius: 4px; margin-bottom: 10px; }
        a { display: inline-block; margin-top: 15px; }
    </style>
</head>
<body>
    <h1>Edit Mahasiswa</h1>

    <?php if ($error): ?>
        <p class="error"><?= htmlspecialchars($error) ?></p>
    <?php endif; ?>

    <form method="post">
        <input type="hidden" name="id" value="<?= htmlspecialchars($id) ?>">

        <label>NPM</label>
        <input type="text" name="npm" value="<?= htmlspecialchars($mhs['npm']) ?>" required>

        <label>Nama</label>
        <input type="text" name="nama" value="<?= htmlspecialchars($mhs['nama']) ?>" required>

        <label>Program Studi</label>
        <select name="prodi_id" required>
            <option value="">-- pilih prodi --</option>
            <?php foreach ($prodi as $p): ?>
                <option value="<?= $p['id'] ?>" <?= $mhs['prodi_id'] == $p['id'] ? 'selected' : '' ?>>
                    <?= htmlspecialchars($p['nama']) ?>
                </option>
            <?php endforeach; ?>
        </select>

        <label>Angkatan</label>
        <input type="number" name="angkatan" min="2000" max="2100"
               value="<?= htmlspecialchars($mhs['angkatan']) ?>" required>

        <label>Email</label>
        <input type="email" name="email" value="<?= htmlspecialchars($mhs['email'] ?? '') ?>">

        <label>Status</label>
        <select name="status">
            <?php foreach (['aktif','cuti','non_aktif','lulus','keluar'] as $s): ?>
                <option value="<?= $s ?>" <?= $mhs['status'] === $s ? 'selected' : '' ?>><?= $s ?></option>
            <?php endforeach; ?>
        </select>

        <button type="submit">Simpan Perubahan</button>
    </form>

    <a href="index.php">&larr; Kembali ke daftar</a>
</body>
</html>