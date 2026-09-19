-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 00_run_all.sql
-- Scopo     : deploy completo e riproducibile da zero, nell'ordine corretto.
-- Esecuzione: SOLO da psql o dal PSQL Tool di pgAdmin 4 (usa meta-comandi),
--             connessi al database di destinazione nis2_acn:
--                 \i 'C:/Users/aroci/OneDrive/Desktop/nis2_acn/sql/00_run_all.sql'
--             Usare le barre "/" anche su Windows. La cartella di lavoro del
--             PSQL Tool non conta: \ir risolve ogni script rispetto alla
--             cartella di QUESTO file.
-- Sicurezza : ON_ERROR_STOP interrompe il deploy al primo errore; ogni script
--             è una transazione autonoma.
-- Idempotenza: rieseguibile; 01_schema.sql ricrea lo schema nis2 da zero.
-- =============================================================================

\set ON_ERROR_STOP on
\encoding UTF8
SET client_encoding = 'UTF8';

\echo '== PW19 Registro NIS2/ACN - deploy =='
SELECT current_database() AS database, current_user AS utente,
       current_setting('server_encoding') AS server_encoding,
       current_setting('client_encoding') AS client_encoding,
       split_part(version(), ',', 1) AS versione;

\echo '[1/8] Schema'
\ir 01_schema.sql
\echo '[2/8] Tabelle di dominio'
\ir 02_lookup.sql
\echo '[3/8] Tabelle principali'
\ir 03_tabelle.sql
\echo '[4/8] Indici'
\ir 04_indici.sql
\echo '[5/8] Versioning, storico, audit e regole'
\ir 05_trigger_versioning.sql
\echo '[6/8] Viste e funzioni del profilo ACN'
\ir 06_funzioni_viste.sql
\echo '[7/8] Dati di test'
\ir 07_dati_test.sql
\echo '[8/8] Ruoli di accesso e versione dello schema'
\ir 09_sicurezza_versione.sql

\echo '== Deploy completato. Riepilogo oggetti dello schema nis2 =='
SELECT 'tabelle' AS oggetto, count(*) AS numero
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'nis2' AND c.relkind = 'r'
UNION ALL
SELECT 'viste', count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'nis2' AND c.relkind = 'v'
UNION ALL
SELECT 'funzioni e procedure', count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'nis2'
UNION ALL
SELECT 'trigger', count(*)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'nis2' AND NOT t.tgisinternal
UNION ALL
SELECT 'indici', count(*)
  FROM pg_indexes WHERE schemaname = 'nis2'
UNION ALL
SELECT 'organizzazioni (dati di test)', count(*) FROM nis2.organizzazione
UNION ALL
SELECT 'righe del profilo ACN', count(*) FROM nis2.v_profilo_acn;

\echo '== Versione dello schema e ultimi deploy (nis2_meta) =='
SELECT d.deploy_id, d.versione, v.rilasciata_il, d.eseguito_il, d.eseguito_da, d.server
  FROM nis2_meta.registro_deploy d JOIN nis2_meta.versione_schema v USING (versione)
 ORDER BY d.deploy_id DESC
 LIMIT 3;
