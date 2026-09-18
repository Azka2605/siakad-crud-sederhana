<?php
require 'koneksi.php';

// Ambil data mahasiswa berikut nama prodinya
$sql = "SELECT m.id, m.npm, m.nama, p.nama AS nama_prodi, m.angkatan, m.email, m.status
        FROM mahasiswa m
        LEFT JOIN prodi p ON p.id = m.prodi_id
        ORDER BY m.npm";
$stmt = $pdo->query($sql);
$data = $stmt->fetchAll();
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Data Mahasiswa - SIAKAD</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        h1 { color: #222; }
        table { border-collapse: collapse; width: 100%; background: #fff; }
        th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
        th { background: #2c3e50; color: #fff; }
        tr:nth-child(even) { background: #f9f9f9; }
        .btn { padding: 4px 10px; text-decoration: none; border-radius: 4px; font-size: 13px; }
        .btn-tambah { background: #27ae60; color: #fff; display: inline-block; margin-bottom: 15px; }
        .btn-edit { background: #2980b9; color: #fff; }
        .btn-hapus { background: #c0392b; color: #fff; }
        .status-aktif { color: #27ae60; font-weight: bold; }
        .status-lain { color: #888; }
        .alert { padding: 10px; background: #dff0d8; color: #3c763d; margin-bottom: 15px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>Data Mahasiswa</h1>

    <?php if (isset($_GET['pesan'])): ?>
        <div class="alert"><?= htmlspecialchars($_GET['pesan']) ?></div>
    <?php endif; ?>

    <a class="btn btn-tambah" href="tambah.php">+ Tambah Mahasiswa</a>

    <table>
        <tr>
            <th>NPM</th>
            <th>Nama</th>
            <th>Prodi</th>
            <th>Angkatan</th>
            <th>Email</th>
            <th>Status</th>
            <th>Aksi</th>
        </tr>
        <?php if (count($data) === 0): ?>
        <tr><td colspan="7">Belum ada data mahasiswa.</td></tr>
        <?php endif; ?>

        <?php foreach ($data as $row): ?>
        <tr>
            <td><?= htmlspecialchars($row['npm']) ?></td>
            <td><?= htmlspecialchars($row['nama']) ?></td>
            <td><?= htmlspecialchars($row['nama_prodi'] ?? '-') ?></td>
            <td><?= htmlspecialchars($row['angkatan']) ?></td>
            <td><?= htmlspecialchars($row['email'] ?? '-') ?></td>
            <td>
                <span class="<?= $row['status'] === 'aktif' ? 'status-aktif' : 'status-lain' ?>">
                    <?= htmlspecialchars($row['status']) ?>
                </span>
            </td>
            <td>
                <a class="btn btn-edit" href="update.php?id=<?= $row['id'] ?>">Edit</a>
                <a class="btn btn-hapus" href="hapus.php?id=<?= $row['id'] ?>"
                   onclick="return confirm('Hapus mahasiswa <?= htmlspecialchars(addslashes($row['nama'])) ?>?')">Hapus</a>
            </td>
        </tr>
        <?php endforeach; ?>
    </table>
</body>
</html>