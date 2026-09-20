-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : export/esporta_profili_csv.sql
-- Scopo     : esporta in CSV il profilo ACN di ogni azienda e il profilo
--             completo, nella cartella export/ del repository.
-- Esecuzione: SOLO da psql o dal PSQL Tool di pgAdmin 4 (usa meta-comandi):
--               \i 'C:/PW19-NIS2-ACN-Registry/export/esporta_profili_csv.sql'
--             Se il repository si trova altrove, impostare prima la cartella:
--               \set cartella 'C:/percorso/del/repository/export'
--             (barre "/" anche su Windows); altrimenti vale il percorso predefinito.
-- =============================================================================

\set ON_ERROR_STOP on
\encoding UTF8
\if :{?cartella}
\else
    \set cartella 'C:/PW19-NIS2-ACN-Registry/export'
\endif
\cd :cartella

\copy (SELECT * FROM nis2.fn_profilo_acn(1)) TO 'profilo_acn_1_zagara_neuro_therapeutics.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM nis2.fn_profilo_acn(2)) TO 'profilo_acn_2_elymsol_energia.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM nis2.fn_profilo_acn(3)) TO 'profilo_acn_3_tecpot_digital_services.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM nis2.v_profilo_acn ORDER BY organizzazione_id, sezione, progressivo) TO 'profilo_acn_completo.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Export completato nella cartella' :cartella
