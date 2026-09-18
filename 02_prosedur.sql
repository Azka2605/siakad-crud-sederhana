-- =====================================================================
--  SIAKADU - Function, Procedure, Trigger & View
--  Jalankan setelah 01_skema.sql
-- =====================================================================

SET search_path TO siakadu, public;


-- =====================================================================
--  BAGIAN 1 : FUNCTION PEMBANTU
-- =====================================================================

-- Konversi nilai angka -> huruf, bobot, status lulus
CREATE OR REPLACE FUNCTION fn_konversi_nilai(p_angka NUMERIC)
RETURNS TABLE (huruf VARCHAR, bobot NUMERIC, is_lulus BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT sn.huruf, sn.bobot, sn.is_lulus
    FROM skala_nilai sn
    WHERE p_angka BETWEEN sn.batas_bawah AND sn.batas_atas
    LIMIT 1;
$$;


-- Semester aktif saat ini
CREATE OR REPLACE FUNCTION fn_semester_aktif()
RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    SELECT id FROM semester WHERE is_aktif LIMIT 1;
$$;


-- IPS satu mahasiswa pada satu semester
CREATE OR REPLACE FUNCTION fn_hitung_ips(p_mahasiswa_id BIGINT, p_semester_id BIGINT)
RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(ROUND(SUM(n.mutu) / NULLIF(SUM(n.sks), 0), 2), 0)
    FROM nilai n
    JOIN krs_detail kd ON kd.id = n.krs_detail_id
    JOIN krs k         ON k.id  = kd.krs_id
    WHERE k.mahasiswa_id = p_mahasiswa_id
      AND k.semester_id  = p_semester_id
      AND n.status = 'final';
$$;


-- IPK kumulatif: ambil nilai TERBAIK per mata kuliah (menangani mengulang)
CREATE OR REPLACE FUNCTION fn_hitung_ipk(p_mahasiswa_id BIGINT)
RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    WITH terbaik AS (
        SELECT DISTINCT ON (kl.mata_kuliah_id)
               n.sks, n.mutu
        FROM nilai n
        JOIN krs_detail kd ON kd.id = n.krs_detail_id
        JOIN krs k         ON k.id  = kd.krs_id
        JOIN kelas kl      ON kl.id = kd.kelas_id
        WHERE k.mahasiswa_id = p_mahasiswa_id
          AND n.status = 'final'
        ORDER BY kl.mata_kuliah_id, n.bobot DESC, n.id DESC
    )
    SELECT COALESCE(ROUND(SUM(mutu) / NULLIF(SUM(sks), 0), 2), 0) FROM terbaik;
$$;


-- Total SKS lulus kumulatif
CREATE OR REPLACE FUNCTION fn_sks_lulus(p_mahasiswa_id BIGINT)
RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    WITH terbaik AS (
        SELECT DISTINCT ON (kl.mata_kuliah_id)
               n.sks, n.is_lulus
        FROM nilai n
        JOIN krs_detail kd ON kd.id = n.krs_detail_id
        JOIN krs k         ON k.id  = kd.krs_id
        JOIN kelas kl      ON kl.id = kd.kelas_id
        WHERE k.mahasiswa_id = p_mahasiswa_id
          AND n.status = 'final'
        ORDER BY kl.mata_kuliah_id, n.bobot DESC, n.id DESC
    )
    SELECT COALESCE(SUM(sks), 0) FROM terbaik WHERE is_lulus;
$$;


-- IPS semester terakhir yang sudah punya nilai final (dasar jatah SKS)
CREATE OR REPLACE FUNCTION fn_ips_terakhir(p_mahasiswa_id BIGINT, p_semester_id BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_kode_skrg VARCHAR(6);
    v_sem_lalu  BIGINT;
BEGIN
    SELECT kode INTO v_kode_skrg FROM semester WHERE id = p_semester_id;

    SELECT s.id INTO v_sem_lalu
    FROM krs k
    JOIN semester s ON s.id = k.semester_id
    JOIN krs_detail kd ON kd.krs_id = k.id
    JOIN nilai n ON n.krs_detail_id = kd.id AND n.status = 'final'
    WHERE k.mahasiswa_id = p_mahasiswa_id
      AND s.kode < v_kode_skrg
    GROUP BY s.id, s.kode
    ORDER BY s.kode DESC
    LIMIT 1;

    IF v_sem_lalu IS NULL THEN
        RETURN NULL;              -- mahasiswa baru, belum punya IPS
    END IF;

    RETURN fn_hitung_ips(p_mahasiswa_id, v_sem_lalu);
END;
$$;


-- Jatah SKS maksimum berdasarkan IPS semester lalu
CREATE OR REPLACE FUNCTION fn_maks_sks(p_ips NUMERIC)
RETURNS SMALLINT
LANGUAGE plpgsql STABLE AS $$
DECLARE v_maks SMALLINT;
BEGIN
    IF p_ips IS NULL THEN
        RETURN 20;                -- paket semester 1
    END IF;

    SELECT maks_sks INTO v_maks
    FROM batas_sks
    WHERE p_ips BETWEEN ips_min AND ips_max
    LIMIT 1;

    RETURN COALESCE(v_maks, 16);
END;
$$;


-- Cek bentrok jadwal antara kelas kandidat dengan kelas yang sudah diambil
CREATE OR REPLACE FUNCTION fn_cek_bentrok_jadwal(p_krs_id BIGINT, p_kelas_id BIGINT)
RETURNS TABLE (kelas_bentrok BIGINT, nama_mk VARCHAR, hari SMALLINT,
               jam_mulai TIME, jam_selesai TIME)
LANGUAGE sql STABLE AS $$
    SELECT kl.id, mk.nama, ja.hari, ja.jam_mulai, ja.jam_selesai
    FROM krs_detail kd
    JOIN kelas kl       ON kl.id = kd.kelas_id
    JOIN mata_kuliah mk ON mk.id = kl.mata_kuliah_id
    JOIN jadwal ja      ON ja.kelas_id = kl.id
    JOIN jadwal jb      ON jb.kelas_id = p_kelas_id
                       AND jb.hari = ja.hari
                       AND jb.jam_mulai < ja.jam_selesai
                       AND jb.jam_selesai > ja.jam_mulai
    WHERE kd.krs_id = p_krs_id;
$$;


-- =====================================================================
--  BAGIAN 2 : PROCEDURE ALUR KRS
-- =====================================================================

-- Buka / ambil KRS milik mahasiswa untuk semester tertentu.
-- Sekaligus menghitung jatah SKS dari IPS semester lalu.
CREATE OR REPLACE PROCEDURE sp_buka_krs(
    p_mahasiswa_id BIGINT,
    p_semester_id  BIGINT DEFAULT NULL,
    INOUT p_krs_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_semester_id BIGINT := COALESCE(p_semester_id, fn_semester_aktif());
    v_status      VARCHAR(15);
    v_pa          BIGINT;
    v_ips         NUMERIC;
BEGIN
    IF v_semester_id IS NULL THEN
        RAISE EXCEPTION 'Tidak ada semester aktif';
    END IF;

    SELECT status, dosen_pa_id INTO v_status, v_pa
    FROM mahasiswa WHERE id = p_mahasiswa_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mahasiswa id % tidak ditemukan', p_mahasiswa_id;
    END IF;
    IF v_status <> 'aktif' THEN
        RAISE EXCEPTION 'Mahasiswa berstatus %, tidak dapat mengisi KRS', v_status;
    END IF;

    SELECT id INTO p_krs_id
    FROM krs WHERE mahasiswa_id = p_mahasiswa_id AND semester_id = v_semester_id;

    IF p_krs_id IS NOT NULL THEN
        RETURN;
    END IF;

    v_ips := fn_ips_terakhir(p_mahasiswa_id, v_semester_id);

    INSERT INTO krs (mahasiswa_id, semester_id, dosen_pa_id, maks_sks, status)
    VALUES (p_mahasiswa_id, v_semester_id, v_pa, fn_maks_sks(v_ips), 'draft')
    RETURNING id INTO p_krs_id;
END;
$$;


-- Ambil satu kelas ke dalam KRS, dengan seluruh validasi.
CREATE OR REPLACE PROCEDURE sp_ambil_kelas(
    p_mahasiswa_id BIGINT,
    p_kelas_id     BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_krs_id        BIGINT;
    v_krs           krs%ROWTYPE;
    v_kelas         kelas%ROWTYPE;
    v_sks           NUMERIC(3,1);
    v_mk_id         BIGINT;
    v_jenis         VARCHAR(15) := 'baru';
    v_pernah_lulus  BOOLEAN;
    v_bentrok       RECORD;
    v_hari          TEXT[] := ARRAY['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
BEGIN
    -- Kunci baris kelas agar kuota aman saat banyak mahasiswa mengambil bersamaan
    SELECT * INTO v_kelas FROM kelas WHERE id = p_kelas_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kelas id % tidak ditemukan', p_kelas_id;
    END IF;
    IF v_kelas.status <> 'dibuka' THEN
        RAISE EXCEPTION 'Kelas sedang berstatus %', v_kelas.status;
    END IF;

    CALL sp_buka_krs(p_mahasiswa_id, v_kelas.semester_id, v_krs_id);
    SELECT * INTO v_krs FROM krs WHERE id = v_krs_id FOR UPDATE;

    IF v_krs.status = 'disetujui' THEN
        RAISE EXCEPTION 'KRS sudah disetujui dan terkunci';
    END IF;

    -- Masa pengisian KRS
    PERFORM 1 FROM semester
     WHERE id = v_kelas.semester_id
       AND (tgl_awal_krs IS NULL OR CURRENT_DATE BETWEEN tgl_awal_krs AND tgl_akhir_krs);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Di luar masa pengisian KRS';
    END IF;

    -- Kuota
    IF v_kelas.terisi >= v_kelas.kapasitas THEN
        RAISE EXCEPTION 'Kuota kelas penuh (%/%)', v_kelas.terisi, v_kelas.kapasitas;
    END IF;

    SELECT mk.id, mk.sks INTO v_mk_id, v_sks
    FROM mata_kuliah mk WHERE mk.id = v_kelas.mata_kuliah_id;

    -- Mata kuliah yang sama tidak boleh diambil dua kelas di semester yang sama
    PERFORM 1
    FROM krs_detail kd JOIN kelas kl ON kl.id = kd.kelas_id
    WHERE kd.krs_id = v_krs_id AND kl.mata_kuliah_id = v_mk_id;
    IF FOUND THEN
        RAISE EXCEPTION 'Mata kuliah ini sudah diambil di kelas lain';
    END IF;

    -- Bentrok jadwal
    SELECT * INTO v_bentrok FROM fn_cek_bentrok_jadwal(v_krs_id, p_kelas_id) LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Bentrok jadwal dengan % pada % %-%',
            v_bentrok.nama_mk, v_hari[v_bentrok.hari],
            v_bentrok.jam_mulai, v_bentrok.jam_selesai;
    END IF;

    -- Batas SKS
    IF v_krs.total_sks + v_sks > v_krs.maks_sks THEN
        RAISE EXCEPTION 'Melebihi jatah SKS (terpakai %, jatah %, mata kuliah ini %)',
            v_krs.total_sks, v_krs.maks_sks, v_sks;
    END IF;

    -- Tentukan jenis pengambilan
    SELECT bool_or(n.is_lulus) INTO v_pernah_lulus
    FROM nilai n
    JOIN krs_detail kd ON kd.id = n.krs_detail_id
    JOIN krs k         ON k.id  = kd.krs_id
    JOIN kelas kl      ON kl.id = kd.kelas_id
    WHERE k.mahasiswa_id = p_mahasiswa_id
      AND kl.mata_kuliah_id = v_mk_id
      AND n.status = 'final';

    IF v_pernah_lulus IS TRUE THEN
        v_jenis := 'perbaikan';
    ELSIF v_pernah_lulus IS FALSE THEN
        v_jenis := 'mengulang';
    END IF;

    INSERT INTO krs_detail (krs_id, kelas_id, sks, jenis_ambil)
    VALUES (v_krs_id, p_kelas_id, v_sks, v_jenis);
END;
$$;


-- Batalkan satu baris KRS
CREATE OR REPLACE PROCEDURE sp_batal_kelas(p_krs_detail_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR(15);
BEGIN
    SELECT k.status INTO v_status
    FROM krs_detail kd JOIN krs k ON k.id = kd.krs_id
    WHERE kd.id = p_krs_detail_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Baris KRS tidak ditemukan';
    END IF;
    IF v_status = 'disetujui' THEN
        RAISE EXCEPTION 'KRS sudah disetujui, pembatalan harus lewat dosen PA';
    END IF;

    DELETE FROM krs_detail WHERE id = p_krs_detail_id;
END;
$$;


-- Mahasiswa mengajukan KRS ke dosen PA
CREATE OR REPLACE PROCEDURE sp_ajukan_krs(p_krs_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_krs krs%ROWTYPE;
BEGIN
    SELECT * INTO v_krs FROM krs WHERE id = p_krs_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'KRS tidak ditemukan';
    END IF;
    IF v_krs.status NOT IN ('draft','ditolak') THEN
        RAISE EXCEPTION 'KRS berstatus %, tidak dapat diajukan', v_krs.status;
    END IF;
    IF v_krs.total_sks = 0 THEN
        RAISE EXCEPTION 'KRS masih kosong';
    END IF;

    UPDATE krs
       SET status = 'diajukan', tgl_pengajuan = now(), catatan_pa = NULL
     WHERE id = p_krs_id;
END;
$$;


-- Dosen PA menyetujui atau menolak
CREATE OR REPLACE PROCEDURE sp_verifikasi_krs(
    p_krs_id   BIGINT,
    p_dosen_id BIGINT,
    p_setuju   BOOLEAN,
    p_catatan  TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE v_krs krs%ROWTYPE;
BEGIN
    SELECT * INTO v_krs FROM krs WHERE id = p_krs_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'KRS tidak ditemukan';
    END IF;
    IF v_krs.status <> 'diajukan' THEN
        RAISE EXCEPTION 'KRS berstatus %, bukan diajukan', v_krs.status;
    END IF;
    IF v_krs.dosen_pa_id IS DISTINCT FROM p_dosen_id THEN
        RAISE EXCEPTION 'Anda bukan dosen PA mahasiswa ini';
    END IF;

    UPDATE krs
       SET status          = CASE WHEN p_setuju THEN 'disetujui' ELSE 'ditolak' END,
           catatan_pa      = p_catatan,
           tgl_persetujuan = now()
     WHERE id = p_krs_id;
END;
$$;


-- =====================================================================
--  BAGIAN 3 : PROCEDURE NILAI
-- =====================================================================

-- Input / ubah nilai satu mahasiswa. Huruf dan bobot dihitung otomatis.
CREATE OR REPLACE PROCEDURE sp_input_nilai(
    p_krs_detail_id BIGINT,
    p_nilai_angka   NUMERIC,
    p_dosen_id      BIGINT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_sks       NUMERIC(3,1);
    v_kelas_id  BIGINT;
    v_st_nilai  VARCHAR(15);
    v_st_krs    VARCHAR(15);
    v_konv      RECORD;
BEGIN
    IF p_nilai_angka < 0 OR p_nilai_angka > 100 THEN
        RAISE EXCEPTION 'Nilai harus 0-100';
    END IF;

    SELECT kd.sks, kd.kelas_id, kl.status_nilai, k.status
      INTO v_sks, v_kelas_id, v_st_nilai, v_st_krs
    FROM krs_detail kd
    JOIN kelas kl ON kl.id = kd.kelas_id
    JOIN krs k    ON k.id  = kd.krs_id
    WHERE kd.id = p_krs_detail_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Baris KRS tidak ditemukan';
    END IF;
    IF v_st_krs <> 'disetujui' THEN
        RAISE EXCEPTION 'KRS belum disetujui dosen PA';
    END IF;
    IF v_st_nilai = 'final' THEN
        RAISE EXCEPTION 'Nilai kelas sudah difinalisasi, ajukan perubahan nilai';
    END IF;

    SELECT * INTO v_konv FROM fn_konversi_nilai(p_nilai_angka);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nilai % tidak masuk skala manapun', p_nilai_angka;
    END IF;

    INSERT INTO nilai (krs_detail_id, nilai_angka, nilai_huruf, bobot, sks,
                       is_lulus, status, diinput_oleh, tgl_input)
    VALUES (p_krs_detail_id, p_nilai_angka, v_konv.huruf, v_konv.bobot, v_sks,
            v_konv.is_lulus, 'draft', p_dosen_id, now())
    ON CONFLICT (krs_detail_id) DO UPDATE
       SET nilai_angka  = EXCLUDED.nilai_angka,
           nilai_huruf  = EXCLUDED.nilai_huruf,
           bobot        = EXCLUDED.bobot,
           is_lulus     = EXCLUDED.is_lulus,
           diinput_oleh = EXCLUDED.diinput_oleh,
           tgl_input    = now();

    UPDATE kelas SET status_nilai = 'proses'
     WHERE id = v_kelas_id AND status_nilai = 'belum';
END;
$$;


-- Finalisasi nilai satu kelas: semua peserta wajib sudah bernilai.
CREATE OR REPLACE PROCEDURE sp_finalisasi_nilai_kelas(p_kelas_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_belum INT;
BEGIN
    SELECT COUNT(*) INTO v_belum
    FROM krs_detail kd
    LEFT JOIN nilai n ON n.krs_detail_id = kd.id
    WHERE kd.kelas_id = p_kelas_id AND n.id IS NULL;

    IF v_belum > 0 THEN
        RAISE EXCEPTION 'Masih ada % mahasiswa yang belum dinilai', v_belum;
    END IF;

    UPDATE nilai SET status = 'final'
     WHERE krs_detail_id IN (SELECT id FROM krs_detail WHERE kelas_id = p_kelas_id);

    UPDATE kelas SET status_nilai = 'final' WHERE id = p_kelas_id;
END;
$$;


-- =====================================================================
--  BAGIAN 4 : KHS & TRANSKRIP
-- =====================================================================

-- KHS satu mahasiswa pada satu semester
CREATE OR REPLACE FUNCTION fn_khs(p_mahasiswa_id BIGINT, p_semester_id BIGINT)
RETURNS TABLE (
    kode_mk VARCHAR, nama_mk VARCHAR, kelas VARCHAR,
    sks NUMERIC, nilai_angka NUMERIC, nilai_huruf VARCHAR,
    bobot NUMERIC, mutu NUMERIC, dosen VARCHAR
)
LANGUAGE sql STABLE AS $$
    SELECT mk.kode, mk.nama, kl.kode_kelas, kd.sks,
           n.nilai_angka, n.nilai_huruf, n.bobot, n.mutu, d.nama
    FROM krs k
    JOIN krs_detail kd  ON kd.krs_id = k.id
    JOIN kelas kl       ON kl.id = kd.kelas_id
    JOIN mata_kuliah mk ON mk.id = kl.mata_kuliah_id
    LEFT JOIN dosen d   ON d.id = kl.dosen_id
    LEFT JOIN nilai n   ON n.krs_detail_id = kd.id AND n.status = 'final'
    WHERE k.mahasiswa_id = p_mahasiswa_id
      AND k.semester_id  = p_semester_id
      AND k.status = 'disetujui'
    ORDER BY mk.kode;
$$;


-- Ringkasan KHS: SKS, IPS, IPK sampai semester tersebut
CREATE OR REPLACE FUNCTION fn_khs_ringkasan(p_mahasiswa_id BIGINT, p_semester_id BIGINT)
RETURNS TABLE (sks_semester NUMERIC, ips NUMERIC, sks_kumulatif NUMERIC, ipk NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT
        (SELECT COALESCE(SUM(n.sks), 0)
           FROM nilai n
           JOIN krs_detail kd ON kd.id = n.krs_detail_id
           JOIN krs k ON k.id = kd.krs_id
          WHERE k.mahasiswa_id = p_mahasiswa_id
            AND k.semester_id = p_semester_id
            AND n.status = 'final'),
        fn_hitung_ips(p_mahasiswa_id, p_semester_id),
        fn_sks_lulus(p_mahasiswa_id),
        fn_hitung_ipk(p_mahasiswa_id);
$$;


-- Transkrip: nilai terbaik per mata kuliah lintas semester
CREATE OR REPLACE FUNCTION fn_transkrip(p_mahasiswa_id BIGINT)
RETURNS TABLE (
    kode_mk VARCHAR, nama_mk VARCHAR, sks NUMERIC,
    nilai_huruf VARCHAR, bobot NUMERIC, mutu NUMERIC,
    semester VARCHAR, jumlah_ambil BIGINT
)
LANGUAGE sql STABLE AS $$
    WITH semua AS (
        SELECT kl.mata_kuliah_id, mk.kode, mk.nama, n.sks, n.nilai_huruf,
               n.bobot, n.mutu, s.kode AS kode_sem, n.id AS nilai_id,
               COUNT(*) OVER (PARTITION BY kl.mata_kuliah_id) AS jml
        FROM nilai n
        JOIN krs_detail kd  ON kd.id = n.krs_detail_id
        JOIN krs k          ON k.id  = kd.krs_id
        JOIN kelas kl       ON kl.id = kd.kelas_id
        JOIN mata_kuliah mk ON mk.id = kl.mata_kuliah_id
        JOIN semester s     ON s.id  = k.semester_id
        WHERE k.mahasiswa_id = p_mahasiswa_id
          AND n.status = 'final'
    )
    SELECT DISTINCT ON (mata_kuliah_id)
           kode, nama, sks, nilai_huruf, bobot, mutu, kode_sem, jml
    FROM semua
    ORDER BY mata_kuliah_id, bobot DESC, nilai_id DESC;
$$;


-- =====================================================================
--  BAGIAN 5 : TRIGGER OTOMATIS
-- =====================================================================

-- Sinkronkan kelas.terisi dan krs.total_sks setiap kali krs_detail berubah
CREATE OR REPLACE FUNCTION trg_sync_krs() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE kelas SET terisi = terisi + 1 WHERE id = NEW.kelas_id;
        UPDATE krs SET total_sks = total_sks + NEW.sks WHERE id = NEW.krs_id;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        UPDATE kelas SET terisi = GREATEST(terisi - 1, 0) WHERE id = OLD.kelas_id;
        UPDATE krs SET total_sks = GREATEST(total_sks - OLD.sks, 0) WHERE id = OLD.krs_id;
        RETURN OLD;

    ELSE
        IF NEW.kelas_id <> OLD.kelas_id THEN
            UPDATE kelas SET terisi = GREATEST(terisi - 1, 0) WHERE id = OLD.kelas_id;
            UPDATE kelas SET terisi = terisi + 1 WHERE id = NEW.kelas_id;
        END IF;
        IF NEW.sks <> OLD.sks THEN
            UPDATE krs SET total_sks = total_sks - OLD.sks + NEW.sks WHERE id = NEW.krs_id;
        END IF;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_krsd_sync
AFTER INSERT OR UPDATE OR DELETE ON krs_detail
FOR EACH ROW EXECUTE FUNCTION trg_sync_krs();


-- Cegah satu ruang dipakai dua kelas pada waktu yang beririsan
CREATE OR REPLACE FUNCTION trg_cek_ruang() RETURNS trigger AS $$
DECLARE v_kode VARCHAR;
BEGIN
    IF NEW.ruang_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT r.kode INTO v_kode
    FROM jadwal j
    JOIN kelas k1 ON k1.id = j.kelas_id
    JOIN kelas k2 ON k2.id = NEW.kelas_id AND k2.semester_id = k1.semester_id
    JOIN ruang r  ON r.id = j.ruang_id
    WHERE j.ruang_id = NEW.ruang_id
      AND j.hari     = NEW.hari
      AND j.id       IS DISTINCT FROM NEW.id
      AND j.jam_mulai   < NEW.jam_selesai
      AND j.jam_selesai > NEW.jam_mulai
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Ruang % sudah terpakai pada slot waktu tersebut', v_kode;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_jadwal_ruang
BEFORE INSERT OR UPDATE ON jadwal
FOR EACH ROW EXECUTE FUNCTION trg_cek_ruang();


-- Cegah satu dosen mengampu dua kelas pada slot waktu yang sama
CREATE OR REPLACE FUNCTION trg_cek_dosen() RETURNS trigger AS $$
DECLARE v_nama VARCHAR;
BEGIN
    SELECT d.nama INTO v_nama
    FROM jadwal j
    JOIN kelas k1 ON k1.id = j.kelas_id
    JOIN kelas k2 ON k2.id = NEW.kelas_id
                 AND k2.semester_id = k1.semester_id
                 AND k2.dosen_id    = k1.dosen_id
    JOIN dosen d  ON d.id = k1.dosen_id
    WHERE j.hari = NEW.hari
      AND j.id   IS DISTINCT FROM NEW.id
      AND j.kelas_id <> NEW.kelas_id
      AND j.jam_mulai   < NEW.jam_selesai
      AND j.jam_selesai > NEW.jam_mulai
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Dosen % sudah mengajar di kelas lain pada slot tersebut', v_nama;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_jadwal_dosen
BEFORE INSERT OR UPDATE ON jadwal
FOR EACH ROW EXECUTE FUNCTION trg_cek_dosen();


-- =====================================================================
--  BAGIAN 6 : VIEW SIAP PAKAI
-- =====================================================================

CREATE OR REPLACE VIEW v_jadwal_kelas AS
SELECT kl.id AS kelas_id, s.kode AS semester, mk.kode AS kode_mk, mk.nama AS nama_mk,
       mk.sks, kl.kode_kelas, d.nama AS dosen,
       CASE j.hari WHEN 1 THEN 'Senin' WHEN 2 THEN 'Selasa' WHEN 3 THEN 'Rabu'
                   WHEN 4 THEN 'Kamis' WHEN 5 THEN 'Jumat' WHEN 6 THEN 'Sabtu'
                   ELSE 'Minggu' END AS hari,
       j.jam_mulai, j.jam_selesai, r.kode AS ruang,
       kl.terisi, kl.kapasitas, kl.kapasitas - kl.terisi AS sisa
FROM kelas kl
JOIN semester s     ON s.id = kl.semester_id
JOIN mata_kuliah mk ON mk.id = kl.mata_kuliah_id
LEFT JOIN dosen d   ON d.id = kl.dosen_id
LEFT JOIN jadwal j  ON j.kelas_id = kl.id
LEFT JOIN ruang r   ON r.id = j.ruang_id;


CREATE OR REPLACE VIEW v_rekap_semester AS
SELECT k.mahasiswa_id, m.npm, m.nama, k.semester_id, s.kode AS semester,
       SUM(n.sks)  AS sks_semester,
       SUM(n.mutu) AS mutu_semester,
       ROUND(SUM(n.mutu) / NULLIF(SUM(n.sks), 0), 2) AS ips
FROM krs k
JOIN mahasiswa m   ON m.id = k.mahasiswa_id
JOIN semester s    ON s.id = k.semester_id
JOIN krs_detail kd ON kd.krs_id = k.id
JOIN nilai n       ON n.krs_detail_id = kd.id AND n.status = 'final'
GROUP BY k.mahasiswa_id, m.npm, m.nama, k.semester_id, s.kode;


-- =====================================================================
--  CONTOH PEMAKAIAN
-- =====================================================================
/*
-- Mahasiswa mengambil tiga kelas
CALL sp_ambil_kelas(1, 10);
CALL sp_ambil_kelas(1, 14);
CALL sp_ambil_kelas(1, 21);

-- Membatalkan satu baris
CALL sp_batal_kelas(3);

-- Ajukan ke dosen PA lalu disetujui
CALL sp_ajukan_krs(1);
CALL sp_verifikasi_krs(1, 5, TRUE, 'Sudah sesuai');

-- Dosen input nilai, lalu finalisasi satu kelas
CALL sp_input_nilai(1, 82.5, 5);
CALL sp_finalisasi_nilai_kelas(10);

-- Lihat KHS, ringkasan, dan transkrip
SELECT * FROM fn_khs(1, 3);
SELECT * FROM fn_khs_ringkasan(1, 3);
SELECT * FROM fn_transkrip(1);
SELECT fn_hitung_ipk(1), fn_sks_lulus(1);
*/