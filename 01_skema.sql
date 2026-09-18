-- =====================================================================
--  SIAKADU - Skema Inti (KRS, Kelas & Jadwal, Nilai, KHS, Transkrip)
--  PostgreSQL 14+
--  Jalankan file ini lebih dulu, baru 02_prosedur.sql
-- =====================================================================

-- DROP SCHEMA IF EXISTS siakadu CASCADE;
CREATE SCHEMA IF NOT EXISTS siakadu;
SET search_path TO siakadu, public;


-- ------------------------------ UTILITAS -----------------------------

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------ MASTER -------------------------------

CREATE TABLE prodi (
    id          BIGSERIAL PRIMARY KEY,
    kode        VARCHAR(10)  NOT NULL UNIQUE,
    nama        VARCHAR(150) NOT NULL,
    jenjang     VARCHAR(10)  NOT NULL DEFAULT 'S1',
    is_aktif    BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE dosen (
    id          BIGSERIAL PRIMARY KEY,
    nidn        VARCHAR(10)  UNIQUE,
    nama        VARCHAR(150) NOT NULL,
    prodi_id    BIGINT       REFERENCES prodi(id),
    email       VARCHAR(150) UNIQUE,
    is_aktif    BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE mahasiswa (
    id          BIGSERIAL PRIMARY KEY,
    npm         VARCHAR(15)  NOT NULL UNIQUE,
    nama        VARCHAR(150) NOT NULL,
    prodi_id    BIGINT       NOT NULL REFERENCES prodi(id),
    angkatan    SMALLINT     NOT NULL,
    dosen_pa_id BIGINT       REFERENCES dosen(id),
    email       VARCHAR(150) UNIQUE,
    status      VARCHAR(15)  NOT NULL DEFAULT 'aktif'
                CHECK (status IN ('aktif','cuti','non_aktif','lulus','keluar')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_mhs_prodi ON mahasiswa(prodi_id);
CREATE INDEX idx_mhs_pa    ON mahasiswa(dosen_pa_id);

CREATE TABLE semester (
    id              BIGSERIAL PRIMARY KEY,
    kode            VARCHAR(6)  NOT NULL UNIQUE,   -- 20251 = ganjil 2025/2026
    nama            VARCHAR(50) NOT NULL,
    jenis           VARCHAR(10) NOT NULL CHECK (jenis IN ('ganjil','genap','pendek')),
    tgl_mulai       DATE NOT NULL,
    tgl_selesai     DATE NOT NULL,
    tgl_awal_krs    DATE,
    tgl_akhir_krs   DATE,
    is_aktif        BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (tgl_selesai > tgl_mulai)
);
-- Hanya boleh ada satu semester aktif
CREATE UNIQUE INDEX uq_semester_aktif ON semester(is_aktif) WHERE is_aktif;

CREATE TABLE mata_kuliah (
    id          BIGSERIAL PRIMARY KEY,
    kode        VARCHAR(20)  NOT NULL UNIQUE,
    nama        VARCHAR(200) NOT NULL,
    sks         NUMERIC(3,1) NOT NULL CHECK (sks > 0),
    semester_ke SMALLINT     CHECK (semester_ke BETWEEN 1 AND 14),
    sifat       VARCHAR(10)  NOT NULL DEFAULT 'wajib'
                CHECK (sifat IN ('wajib','pilihan')),
    prodi_id    BIGINT       REFERENCES prodi(id),   -- NULL = mata kuliah umum
    is_aktif    BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE ruang (
    id          BIGSERIAL PRIMARY KEY,
    kode        VARCHAR(20)  NOT NULL UNIQUE,
    nama        VARCHAR(100),
    gedung      VARCHAR(100),
    kapasitas   INT          NOT NULL DEFAULT 0,
    is_aktif    BOOLEAN      NOT NULL DEFAULT TRUE
);


-- -------------------- KELAS PERKULIAHAN & JADWAL ---------------------

CREATE TABLE kelas (
    id              BIGSERIAL PRIMARY KEY,
    semester_id     BIGINT      NOT NULL REFERENCES semester(id),
    mata_kuliah_id  BIGINT      NOT NULL REFERENCES mata_kuliah(id),
    dosen_id        BIGINT      REFERENCES dosen(id),
    kode_kelas      VARCHAR(5)  NOT NULL,            -- A, B, C
    kapasitas       INT         NOT NULL DEFAULT 40 CHECK (kapasitas > 0),
    terisi          INT         NOT NULL DEFAULT 0 CHECK (terisi >= 0),
    status          VARCHAR(15) NOT NULL DEFAULT 'dibuka'
                    CHECK (status IN ('dibuka','ditutup','dibatalkan')),
    status_nilai    VARCHAR(15) NOT NULL DEFAULT 'belum'
                    CHECK (status_nilai IN ('belum','proses','final')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (semester_id, mata_kuliah_id, kode_kelas)
);
CREATE INDEX idx_kelas_semester ON kelas(semester_id);
CREATE INDEX idx_kelas_dosen    ON kelas(dosen_id);

CREATE TABLE jadwal (
    id          BIGSERIAL PRIMARY KEY,
    kelas_id    BIGINT   NOT NULL REFERENCES kelas(id) ON DELETE CASCADE,
    ruang_id    BIGINT   REFERENCES ruang(id),
    hari        SMALLINT NOT NULL CHECK (hari BETWEEN 1 AND 7),  -- 1 = Senin
    jam_mulai   TIME     NOT NULL,
    jam_selesai TIME     NOT NULL,
    jenis       VARCHAR(15) NOT NULL DEFAULT 'teori'
                CHECK (jenis IN ('teori','praktikum','responsi')),
    CHECK (jam_selesai > jam_mulai)
);
CREATE INDEX idx_jadwal_kelas ON jadwal(kelas_id);
CREATE INDEX idx_jadwal_ruang ON jadwal(ruang_id, hari);


-- ------------------------------ KRS ----------------------------------

CREATE TABLE batas_sks (
    id          SMALLSERIAL PRIMARY KEY,
    ips_min     NUMERIC(4,2) NOT NULL,
    ips_max     NUMERIC(4,2) NOT NULL,
    maks_sks    SMALLINT     NOT NULL,
    CHECK (ips_max >= ips_min)
);

CREATE TABLE krs (
    id              BIGSERIAL PRIMARY KEY,
    mahasiswa_id    BIGINT      NOT NULL REFERENCES mahasiswa(id) ON DELETE CASCADE,
    semester_id     BIGINT      NOT NULL REFERENCES semester(id),
    dosen_pa_id     BIGINT      REFERENCES dosen(id),
    maks_sks        SMALLINT    NOT NULL DEFAULT 24,
    total_sks       NUMERIC(4,1) NOT NULL DEFAULT 0,
    status          VARCHAR(15) NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','diajukan','disetujui','ditolak')),
    catatan_pa      TEXT,
    tgl_pengajuan   TIMESTAMPTZ,
    tgl_persetujuan TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (mahasiswa_id, semester_id)
);
CREATE INDEX idx_krs_semester ON krs(semester_id, status);

CREATE TABLE krs_detail (
    id          BIGSERIAL PRIMARY KEY,
    krs_id      BIGINT       NOT NULL REFERENCES krs(id) ON DELETE CASCADE,
    kelas_id    BIGINT       NOT NULL REFERENCES kelas(id),
    sks         NUMERIC(3,1) NOT NULL,
    jenis_ambil VARCHAR(15)  NOT NULL DEFAULT 'baru'
                CHECK (jenis_ambil IN ('baru','mengulang','perbaikan')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (krs_id, kelas_id)
);
CREATE INDEX idx_krsd_kelas ON krs_detail(kelas_id);


-- ----------------------------- NILAI ---------------------------------

CREATE TABLE skala_nilai (
    id          SMALLSERIAL PRIMARY KEY,
    huruf       VARCHAR(2)   NOT NULL UNIQUE,
    bobot       NUMERIC(3,2) NOT NULL,
    batas_bawah NUMERIC(5,2) NOT NULL,
    batas_atas  NUMERIC(5,2) NOT NULL,
    is_lulus    BOOLEAN      NOT NULL DEFAULT TRUE,
    CHECK (batas_atas >= batas_bawah)
);

CREATE TABLE nilai (
    id              BIGSERIAL PRIMARY KEY,
    krs_detail_id   BIGINT       NOT NULL UNIQUE REFERENCES krs_detail(id) ON DELETE CASCADE,
    nilai_angka     NUMERIC(5,2) CHECK (nilai_angka BETWEEN 0 AND 100),
    nilai_huruf     VARCHAR(2),
    bobot           NUMERIC(3,2),
    sks             NUMERIC(3,1) NOT NULL,
    mutu            NUMERIC(6,2) GENERATED ALWAYS AS (bobot * sks) STORED,
    is_lulus        BOOLEAN,
    status          VARCHAR(10)  NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','final')),
    diinput_oleh    BIGINT       REFERENCES dosen(id),
    tgl_input       TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- --------------------------- SEED MINIMAL ----------------------------

INSERT INTO skala_nilai (huruf, bobot, batas_bawah, batas_atas, is_lulus) VALUES
    ('A',  4.00, 76.00, 100.00, TRUE),
    ('B+', 3.50, 71.00,  75.99, TRUE),
    ('B',  3.00, 66.00,  70.99, TRUE),
    ('C+', 2.50, 61.00,  65.99, TRUE),
    ('C',  2.00, 56.00,  60.99, TRUE),
    ('D',  1.00, 50.00,  55.99, TRUE),
    ('E',  0.00,  0.00,  49.99, FALSE);

INSERT INTO batas_sks (ips_min, ips_max, maks_sks) VALUES
    (0.00, 1.99, 16),
    (2.00, 2.49, 18),
    (2.50, 2.99, 20),
    (3.00, 3.49, 22),
    (3.50, 4.00, 24);


-- ------------------------------ TRIGGER ------------------------------

CREATE TRIGGER trg_mhs_updated BEFORE UPDATE ON mahasiswa
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_krs_updated BEFORE UPDATE ON krs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_nilai_updated BEFORE UPDATE ON nilai
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();