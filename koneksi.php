<?php
$host     = "localhost";
$user     = "root";
$password = ""; 
$db       = "siakadu_db";

$connection = mysqli_connect($host, $user, $password, $db);

if (!$connection) {
    die("Koneksi database gagal:  " . mysqli_connect_error());
}
?>