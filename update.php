<?php
include 'koneksi.php';
 $id = $_GET['id'];

 $query = mysqli_query($connection, "SELECT * FROM mahasiswa WHERE id='$id'");
 $data = mysqli_fetch_array($query);

 if (isset($_POST['update'])) {
    $npm = $_POST['npm'];
    $nama = $_POST['nama'];
    $jurusan = $_POST['jurusan'];
    $program_studi = $_POST['program_studi'];

    mysqli_query($connection, "UPDATE mahasiswa SET npm='$npm', nama='$nama', jurusan='$jurusan', program_studi='$program_studi' WHERE id='$id'");
    header("Location: index.php");
 }
 ?>
 <!DOCTYPE html>
<html>
<head><title>Edit Mahasiswa</title></head>
<body>
    <h2>Edit Data Mahasiswa</h2>
    <form method="POST">
        <label>NPM:</label><br>
        <input type="text" name="npm" value="<?php echo $data['npm']; ?>" required><br><br>
        
        <label>Nama:</label><br>
        <input type="text" name="nama" value="<?php echo $data['nama']; ?>" required><br><br>
        
        <label>Jurusan:</label><br>
        <input type="text" name="jurusan" value="<?php echo $data['jurusan']; ?>" required><br><br>
        
        <button type="submit" name="update">Update Data</button>
        <a href="index.php">Batal</a>
    </form>
</body>
</html>