<?php include 'koneksi.php'; ?>
<!DOCTYPE html>
<html>
    <head><title>SIAKADU - Data Mahasiswa</title></head>
    <body>
        <h2>Data Mahasiswa SIAKADU</h2>
        <a href="tambah.php">Tambah Data</a>
        <br><br>
        <table border="1" cellpadding="5" cellspacing="0">
            <tr>
                <th>No</th>
                <th>NPM</th>
                <th>Nama</th>
                <th>Jurusan</th>
                <th>Program Studi</th>
                <th>Aksi</th>
            </tr>
            <?php
                $query = mysqli_query($connection, "SELECT * FROM mahasiswa ORDER BY id DESC");
                $no = 1;
                while ($data = mysqli_fetch_array($query)) {
                ?>
                <tr>
                    <td><?php echo $no++; ?></td>
                    <td><?php echo $data['npm']; ?></td>
                    <td><?php echo $data['nama']; ?></td>
                    <td><?php echo $data['jurusan']; ?></td>
                    <!-- Pastikan nama kolom di database sesuai, di sini saya asumsikan namanya 'program_studi' -->
                    <td><?php echo $data['program_studi']; ?></td> 
                    <td>
                        <a href="edit.php?id=<?php echo $data['id']; ?>">Edit</a> | 
                        <a href="hapus.php?id=<?php echo $data['id']; ?>" onclick="return confirm('Yakin hapus data?')">Hapus</a>
                    </td>
             </tr>
             <?php } ?>
        </table>   
    </body>
</html>