<?php
// koneksi.php
// Sesuaikan kredensial berikut dengan environment Anda.

$host   = 'localhost';
$port   = '5432';
$dbname = 'siakadu';
$user   = 'postgres';
$pass   = 'password';

try {
    $pdo = new PDO(
        "pgsql:host=$host;port=$port;dbname=$dbname",
        $user,
        $pass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    // Semua tabel ada di schema "siakadu"
    $pdo->exec("SET search_path TO siakadu, public");
} catch (PDOException $e) {
    die('Koneksi database gagal: ' . $e->getMessage());
}