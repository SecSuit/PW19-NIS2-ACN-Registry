-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 09_sicurezza_versione.sql
-- Scopo     : 1) controllo degli accessi secondo il principio del minimo
--                privilegio (ruoli applicativi e permessi sullo schema nis2);
--             2) versioning degli script: registro della versione dello schema
--                e di ogni deploy eseguito (schema separato nis2_meta).
-- Dipende da: 07_dati_test.sql (eseguito per ultimo da 00_run_all.sql)
-- Idempotenza: i ruoli si creano solo se mancano; i permessi si riassegnano a
--              ogni deploy (01_schema.sql ricrea lo schema nis2 da zero);
--              lo schema nis2_meta NON viene cancellato, quindi il registro
--              dei deploy conserva la cronologia di tutte le esecuzioni.
-- Auto-verifica: al termine lo script controlla i permessi effettivi e, se
--              non corrispondono alla matrice attesa, interrompe il deploy.
--
-- Matrice dei ruoli (NOLOGIN: si assegnano agli utenti reali con GRANT)
--   nis2_lettura   consultazione: SELECT su tabelle e viste (escluso audit_log),
--                  esecuzione delle funzioni (profilo ACN, CSV, stato a una data)
--   nis2_redattore compilazione: eredita nis2_lettura; INSERT/UPDATE/DELETE sulle
--                  14 tabelle del registro; nessuna modifica a domini, storico,
--                  audit; nessun TRUNCATE (che non attiverebbe i trigger di riga)
--   nis2_revisore  controllo: eredita nis2_lettura; SELECT su audit_log
--   Le tabelle di dominio restano modificabili solo dall'amministratore.
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

-- -----------------------------------------------------------------------------
-- 1. Ruoli applicativi (oggetti globali del cluster: creati solo se mancano)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['nis2_lettura', 'nis2_redattore', 'nis2_revisore'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END;
$$;

BEGIN;

COMMENT ON ROLE nis2_lettura   IS 'Registro NIS2/ACN: consultazione del registro e generazione del profilo ACN.';
COMMENT ON ROLE nis2_redattore IS 'Registro NIS2/ACN: compilazione e aggiornamento delle 14 tabelle del registro.';
COMMENT ON ROLE nis2_revisore  IS 'Registro NIS2/ACN: consultazione del registro e dell''audit log.';

GRANT nis2_lettura TO nis2_redattore;
GRANT nis2_lettura TO nis2_revisore;

-- -----------------------------------------------------------------------------
-- 2. Nessun accesso di default: si parte da zero e si concede il necessario
-- -----------------------------------------------------------------------------
REVOKE ALL     ON SCHEMA nis2                        FROM PUBLIC;
REVOKE ALL     ON ALL TABLES    IN SCHEMA nis2       FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA nis2       FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA nis2      FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3. nis2_lettura
-- -----------------------------------------------------------------------------
GRANT USAGE   ON SCHEMA nis2                    TO nis2_lettura;
GRANT SELECT  ON ALL TABLES IN SCHEMA nis2      TO nis2_lettura;   -- tabelle e viste
REVOKE SELECT ON nis2.audit_log                 FROM nis2_lettura; -- riservato al revisore
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nis2   TO nis2_lettura;

-- -----------------------------------------------------------------------------
-- 4. nis2_redattore
-- -----------------------------------------------------------------------------
GRANT INSERT, UPDATE, DELETE ON
      nis2.organizzazione, nis2.sede, nis2.persona, nis2.assegnazione_ruolo,
      nis2.asset, nis2.servizio, nis2.servizio_paese, nis2.servizio_asset,
      nis2.dipendenza_asset, nis2.fornitore, nis2.contratto,
      nis2.dipendenza_fornitore, nis2.spazio_ip, nis2.dominio
   TO nis2_redattore;

-- I trigger di storico e di audit girano con i privilegi di chi esegue la
-- modifica: al redattore serve quindi il solo INSERT su storico e audit.
-- UPDATE, DELETE e TRUNCATE non sono concessi, e il trigger NIS06 rende
-- comunque immutabili le righe già scritte (append-only).
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables
              WHERE schemaname = 'nis2' AND tablename LIKE '%\_storico' LOOP
        EXECUTE format('GRANT INSERT ON nis2.%I TO nis2_redattore', t);
    END LOOP;
END;
$$;
GRANT INSERT ON nis2.audit_log TO nis2_redattore;

GRANT EXECUTE ON PROCEDURE nis2.sp_sostituisci_titolare_ruolo TO nis2_redattore;

-- -----------------------------------------------------------------------------
-- 5. nis2_revisore
-- -----------------------------------------------------------------------------
GRANT SELECT ON nis2.audit_log TO nis2_revisore;

-- -----------------------------------------------------------------------------
-- 6. Versioning degli script (schema nis2_meta, non ricreato dal deploy)
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS nis2_meta;
COMMENT ON SCHEMA nis2_meta IS
  'Metadati del registro NIS2/ACN: versioni dello schema e cronologia dei deploy.';

CREATE TABLE IF NOT EXISTS nis2_meta.versione_schema (
    versione      varchar(20)  PRIMARY KEY,
    descrizione   text         NOT NULL,
    rilasciata_il date         NOT NULL,
    CONSTRAINT ck_versione_schema_formato CHECK (versione ~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$')
);
COMMENT ON TABLE  nis2_meta.versione_schema IS 'Versioni rilasciate dello schema nis2 (una riga per release, allineata ai tag Git).';
COMMENT ON COLUMN nis2_meta.versione_schema.versione      IS 'Numero di versione nel formato vMAJOR.MINOR[.PATCH], uguale al tag Git.';
COMMENT ON COLUMN nis2_meta.versione_schema.descrizione   IS 'Contenuto della release.';
COMMENT ON COLUMN nis2_meta.versione_schema.rilasciata_il IS 'Data di rilascio.';

CREATE TABLE IF NOT EXISTS nis2_meta.registro_deploy (
    deploy_id    bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    versione     varchar(20)  NOT NULL REFERENCES nis2_meta.versione_schema (versione),
    eseguito_il  timestamptz  NOT NULL DEFAULT clock_timestamp(),
    eseguito_da  name         NOT NULL DEFAULT session_user,
    database     name         NOT NULL DEFAULT current_database(),
    server       text         NOT NULL DEFAULT split_part(version(), ',', 1)
);
COMMENT ON TABLE  nis2_meta.registro_deploy IS 'Cronologia dei deploy: ogni esecuzione di 00_run_all.sql aggiunge una riga.';
COMMENT ON COLUMN nis2_meta.registro_deploy.deploy_id   IS 'Identificativo progressivo del deploy.';
COMMENT ON COLUMN nis2_meta.registro_deploy.versione    IS 'Versione dello schema installata.';
COMMENT ON COLUMN nis2_meta.registro_deploy.eseguito_il IS 'Istante di esecuzione.';
COMMENT ON COLUMN nis2_meta.registro_deploy.eseguito_da IS 'Utente che ha eseguito il deploy.';
COMMENT ON COLUMN nis2_meta.registro_deploy.database    IS 'Database di destinazione.';
COMMENT ON COLUMN nis2_meta.registro_deploy.server      IS 'Versione del server PostgreSQL.';

REVOKE ALL ON SCHEMA nis2_meta FROM PUBLIC;
GRANT USAGE  ON SCHEMA nis2_meta TO nis2_lettura;
GRANT SELECT ON ALL TABLES IN SCHEMA nis2_meta TO nis2_lettura;

INSERT INTO nis2_meta.versione_schema (versione, descrizione, rilasciata_il)
VALUES ('v1.0',
        'Prima release: registro NIS2/ACN, versioning e audit, profilo ACN e CSV, '
        'categorizzazione (Det. 155238/2026), ruoli di accesso.',
        DATE '2026-09-19')
ON CONFLICT (versione) DO NOTHING;

INSERT INTO nis2_meta.registro_deploy (versione) VALUES ('v1.0');

COMMIT;

RESET client_min_messages;

-- -----------------------------------------------------------------------------
-- 7. Auto-verifica: permessi dichiarati e comportamento effettivo
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    errori text[] := ARRAY[]::text[];
BEGIN
    -- permessi dichiarati
    IF NOT has_table_privilege('nis2_lettura', 'nis2.v_profilo_acn', 'SELECT') THEN
        errori := errori || 'lettura: manca SELECT sul profilo'; END IF;
    IF has_table_privilege('nis2_lettura', 'nis2.asset', 'UPDATE') THEN
        errori := errori || 'lettura: non deve modificare asset'; END IF;
    IF has_table_privilege('nis2_lettura', 'nis2.audit_log', 'SELECT') THEN
        errori := errori || 'lettura: non deve leggere audit_log'; END IF;
    IF NOT has_table_privilege('nis2_redattore', 'nis2.asset', 'UPDATE') THEN
        errori := errori || 'redattore: manca UPDATE su asset'; END IF;
    IF has_table_privilege('nis2_redattore', 'nis2.ruolo', 'INSERT') THEN
        errori := errori || 'redattore: non deve modificare i domini'; END IF;
    IF has_table_privilege('nis2_redattore', 'nis2.audit_log', 'UPDATE')
       OR has_table_privilege('nis2_redattore', 'nis2.audit_log', 'DELETE')
       OR has_table_privilege('nis2_redattore', 'nis2.asset', 'TRUNCATE') THEN
        errori := errori || 'redattore: privilegi eccessivi su audit o TRUNCATE'; END IF;
    IF NOT has_table_privilege('nis2_revisore', 'nis2.audit_log', 'SELECT') THEN
        errori := errori || 'revisore: manca SELECT su audit_log'; END IF;

    -- comportamento effettivo, in sottotransazioni annullate
    BEGIN
        SET LOCAL ROLE nis2_redattore;
        PERFORM nis2.fn_imposta_motivo('Verifica permessi in fase di deploy');
        UPDATE nis2.asset SET rto_minuti = rto_minuti WHERE false;  -- privilegio verificato senza modificare dati
        RAISE EXCEPTION 'ok' USING ERRCODE = 'P0001';
    EXCEPTION
        WHEN insufficient_privilege THEN errori := errori || 'redattore: UPDATE su asset rifiutato';
        WHEN raise_exception THEN NULL;
    END;
    RESET ROLE;

    BEGIN
        SET LOCAL ROLE nis2_lettura;
        PERFORM count(*) FROM nis2.audit_log;
        errori := errori || 'lettura: ha potuto leggere audit_log';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;
    RESET ROLE;

    IF cardinality(errori) > 0 THEN
        RAISE EXCEPTION 'Verifica dei permessi fallita: %', array_to_string(errori, '; ');
    END IF;
    RAISE NOTICE 'Verifica dei permessi superata: ruoli nis2_lettura, nis2_redattore, nis2_revisore conformi alla matrice.';
END;
$$;
