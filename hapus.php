<?php
require 'koneksi.php';

$id = $_GET['id'] ?? null;
if (!$id) {
    header('Location: index.php?pesan=' . urlencode('ID mahasiswa tidak valid.'));
    exit;
}

try {
    $stmt = $pdo->prepare("DELETE FROM mahasiswa WHERE id = :id");
    $stmt->execute(['id' => $id]);

    $pesan = $stmt->rowCount() > 0
        ? 'Mahasiswa berhasil dihapus.'
        : 'Mahasiswa tidak ditemukan.';
} catch (PDOException $e) {
    // Contoh: mahasiswa masih punya baris terkait di krs (FK constraint)
    $pesan = 'Gagal menghapus, kemungkinan data masih terpakai di tabel lain (KRS/nilai).';
}

header('Location: index.php?pesan=' . urlencode($pesan));
exit;