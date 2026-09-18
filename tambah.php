<?php
include 'koneksi.php';

if (isset($_POST['simpan'])) {
    $npm = $_POST['npm'];
    $nama = $_POST['nama'];
    $jurusan = $_POST['jurusan'];
    $program_studi = $_POST['program_studi'];
    
    mysqli_query($connection, "INSERT INTO mahasiswa (npm, nama, jurusan, program_studi) VALUES ('$npm', '$nama', '$jurusan', '$program_studi')");
    header("Location: index.php");
}
?>
<!DOCTYPE html>
<html>
<head><title>Tambah Mahasiswa</title></head>
<body>
    <h2>Tambah Data Mahasiswa</h2>
    <form method="POST">
        <label>NPM:</label><br>
        <input type="text" name="npm" required><br><br>
        
        <label>Nama:</label><br>
        <input type="text" name="nama" required><br><br>
        
        <label>Jurusan:</label><br>
        <input type="text" name="jurusan" required><br><br>

        <label>Program Studi:</label><br>
        <input type="text" name="program_studi" required><br><br>
        
        <button type="submit" name="simpan">Simpan Data</button>
        <a href="index.php">Batal</a>
    </form>
</body>
</html>