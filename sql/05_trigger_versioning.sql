-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 05_trigger_versioning.sql
-- Scopo     : versioning, storico, audit log e regole di integrità non
--             esprimibili con vincoli dichiarativi.
-- Dipende da: 04_indici.sql
-- Idempotenza: CREATE ... IF NOT EXISTS, CREATE OR REPLACE FUNCTION/TRIGGER
--
-- Architettura (tre livelli complementari)
--  1. VERSIONING sulla tabella corrente: colonne versione / valido_dal /
--     modificato_da, imposte da un trigger BEFORE (l'utente non può falsarle).
--  2. STORICO (snapshot-on-write): per ogni entità storicizzata esiste
--     <tabella>_storico con la stessa struttura più valido_al, operazione,
--     motivo, archiviato_da. Un trigger AFTER UPDATE/DELETE vi copia la
--     versione superata: ogni riga storica descrive un intervallo
--     [valido_dal, valido_al) e la tabella corrente resta snella.
--  3. AUDIT LOG generale: un unico trigger generico registra in formato JSONB
--     ogni INSERT/UPDATE/DELETE su tutte le tabelle (anche ponte e lookup),
--     con i campi modificati, l'utente, l'applicazione e la transazione.
--  Il motivo della modifica si passa con la variabile di sessione
--  nis2.motivo_modifica (funzione nis2.fn_imposta_motivo), senza alterare
--  la firma delle tabelle.
--
-- Codici di errore applicativi (SQLSTATE personalizzati, classe "NIS")
--  NIS01 modifica della chiave primaria      NIS05 organizzazioni incoerenti
--  NIS02 ruolo unico già assegnato           NIS06 storico/audit immutabili
--  NIS03 punto di contatto = sostituto       NIS07 organizzazione inesistente
--  NIS04 ciclo nelle dipendenze tra asset    NIS08 tabella non storicizzata
--  NIS09 categoria di rilevanza diversa da quella pre-assegnata senza valutazione documentata
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

-- =============================================================================
-- 1. AUDIT LOG
-- =============================================================================
CREATE TABLE IF NOT EXISTS nis2.audit_log (
    audit_log_id      bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    istante           timestamptz  NOT NULL DEFAULT clock_timestamp(),
    id_transazione    bigint       NOT NULL DEFAULT (pg_current_xact_id()::text::bigint),
    utente            varchar(128) NOT NULL DEFAULT session_user,
    applicazione      varchar(128) NOT NULL DEFAULT coalesce(nullif(current_setting('application_name', true), ''), 'n/d'),
    tabella           varchar(63)  NOT NULL,
    operazione        char(1)      NOT NULL,
    chiave            jsonb        NOT NULL,
    dati_prima        jsonb,
    dati_dopo         jsonb,
    campi_modificati  text[],
    motivo            text,
    CONSTRAINT ck_audit_operazione CHECK (operazione IN ('I', 'U', 'D')),
    CONSTRAINT ck_audit_dati CHECK (
        (operazione = 'I' AND dati_prima IS NULL AND dati_dopo IS NOT NULL) OR
        (operazione = 'U' AND dati_prima IS NOT NULL AND dati_dopo IS NOT NULL) OR
        (operazione = 'D' AND dati_prima IS NOT NULL AND dati_dopo IS NULL))
);
COMMENT ON TABLE  nis2.audit_log IS 'Registro di audit append-only di tutte le modifiche ai dati dello schema nis2 (chi, cosa, quando, perché).';
COMMENT ON COLUMN nis2.audit_log.audit_log_id     IS 'Identificativo progressivo dell''evento.';
COMMENT ON COLUMN nis2.audit_log.istante          IS 'Istante effettivo della modifica (clock_timestamp).';
COMMENT ON COLUMN nis2.audit_log.id_transazione   IS 'Identificativo della transazione: raggruppa le modifiche atomiche.';
COMMENT ON COLUMN nis2.audit_log.utente           IS 'Utente database di sessione che ha eseguito l''operazione.';
COMMENT ON COLUMN nis2.audit_log.applicazione     IS 'Valore di application_name del client (es. pgAdmin 4, psql).';
COMMENT ON COLUMN nis2.audit_log.tabella          IS 'Tabella modificata.';
COMMENT ON COLUMN nis2.audit_log.operazione       IS 'I = inserimento, U = modifica, D = cancellazione.';
COMMENT ON COLUMN nis2.audit_log.chiave           IS 'Chiave della riga interessata in formato JSON.';
COMMENT ON COLUMN nis2.audit_log.dati_prima       IS 'Immagine della riga prima della modifica (NULL per I).';
COMMENT ON COLUMN nis2.audit_log.dati_dopo        IS 'Immagine della riga dopo la modifica (NULL per D).';
COMMENT ON COLUMN nis2.audit_log.campi_modificati IS 'Elenco delle colonne effettivamente variate (solo U).';
COMMENT ON COLUMN nis2.audit_log.motivo           IS 'Motivo dichiarato con nis2.fn_imposta_motivo (facoltativo).';

CREATE INDEX IF NOT EXISTS ix_audit_log_tabella_istante ON nis2.audit_log (tabella, istante DESC);
CREATE INDEX IF NOT EXISTS ix_audit_log_chiave          ON nis2.audit_log USING gin (chiave jsonb_path_ops);
CREATE INDEX IF NOT EXISTS ix_audit_log_istante_brin    ON nis2.audit_log USING brin (istante);

-- =============================================================================
-- 2. FUNZIONI DI SUPPORTO
-- =============================================================================
CREATE OR REPLACE FUNCTION nis2.fn_imposta_motivo(p_motivo text)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
    SELECT set_config('nis2.motivo_modifica', coalesce(p_motivo, ''), true);
$$;
COMMENT ON FUNCTION nis2.fn_imposta_motivo(text) IS
  'Imposta il motivo delle modifiche per la transazione corrente (SET LOCAL); viene registrato in storico e audit.';

CREATE OR REPLACE FUNCTION nis2.fn_motivo_corrente()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(current_setting('nis2.motivo_modifica', true), '');
$$;
COMMENT ON FUNCTION nis2.fn_motivo_corrente() IS
  'Restituisce il motivo impostato per la transazione corrente, o NULL.';

-- =============================================================================
-- 3. TRIGGER GENERICI DI VERSIONING E STORICO
-- =============================================================================

-- BEFORE INSERT OR UPDATE: imposta le colonne di versione.
CREATE OR REPLACE FUNCTION nis2.fn_trg_versione()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    c_meta constant text[] := ARRAY['versione', 'valido_dal', 'modificato_da'];
    v_pk   constant text   := TG_TABLE_NAME || '_id';
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.versione      := 1;
        NEW.valido_dal    := clock_timestamp();
        NEW.modificato_da := session_user;
        RETURN NEW;
    END IF;

    -- UPDATE: la chiave primaria surrogata è immutabile
    IF to_jsonb(NEW) -> v_pk IS DISTINCT FROM to_jsonb(OLD) -> v_pk THEN
        RAISE EXCEPTION 'La chiave primaria %.% non è modificabile', TG_TABLE_NAME, v_pk
              USING ERRCODE = 'NIS01';
    END IF;

    -- Nessuna variazione sostanziale: la riga non viene riscritta, niente nuova versione
    IF (to_jsonb(NEW) - c_meta) = (to_jsonb(OLD) - c_meta) THEN
        RETURN NULL;
    END IF;

    NEW.versione      := OLD.versione + 1;
    NEW.valido_dal    := clock_timestamp();   -- distinto anche per più modifiche nella stessa transazione
    NEW.modificato_da := session_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_versione() IS
  'Trigger BEFORE INSERT/UPDATE: imposta versione, valido_dal e modificato_da; blocca la modifica della PK; ignora gli UPDATE senza variazioni.';

-- AFTER UPDATE OR DELETE: archivia la versione superata in <tabella>_storico.
CREATE OR REPLACE FUNCTION nis2.fn_trg_storico()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_valido_al timestamptz;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_valido_al := NEW.valido_dal;        -- la nuova versione inizia dove finisce la precedente
    ELSE
        v_valido_al := clock_timestamp();
    END IF;

    -- corrispondenza per NOME di colonna (jsonb_populate_record): lo storico resta
    -- corretto anche se in futuro le colonne vengono aggiunte in ordine diverso
    EXECUTE format('INSERT INTO %1$I.%2$I SELECT * FROM jsonb_populate_record(NULL::%1$I.%2$I, $1)',
                   TG_TABLE_SCHEMA, TG_TABLE_NAME || '_storico')
    USING to_jsonb(OLD) || jsonb_build_object(
              'valido_al',     v_valido_al,
              'operazione',    left(TG_OP, 1),
              'motivo',        nis2.fn_motivo_corrente(),
              'archiviato_da', session_user);

    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_storico() IS
  'Trigger AFTER UPDATE/DELETE: copia la versione superata nella tabella <nome>_storico con intervallo di validità, operazione e motivo.';

-- Impedisce UPDATE e DELETE su storico e audit (append-only).
CREATE OR REPLACE FUNCTION nis2.fn_trg_immutabile()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La tabella %.% è in sola aggiunta: % non consentito', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
          USING ERRCODE = 'NIS06';
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_immutabile() IS
  'Trigger BEFORE UPDATE/DELETE che rende immutabili storico e audit log.';

-- =============================================================================
-- 4. TRIGGER GENERICO DI AUDIT
-- =============================================================================
CREATE OR REPLACE FUNCTION nis2.fn_trg_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_prima   jsonb;
    v_dopo    jsonb;
    v_riga    jsonb;
    v_pk      constant text := TG_TABLE_NAME || '_id';
    v_chiave  jsonb;
    v_campi   text[];
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_prima := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_dopo := to_jsonb(NEW);
    END IF;
    v_riga := coalesce(v_dopo, v_prima);

    -- chiave: PK surrogata se esiste, altrimenti l'intera riga (tabelle ponte e lookup)
    IF v_riga ? v_pk THEN
        v_chiave := jsonb_build_object(v_pk, v_riga -> v_pk);
    ELSE
        v_chiave := v_riga;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(n.key ORDER BY n.key)
          INTO v_campi
          FROM jsonb_each(v_dopo) AS n
         WHERE n.value IS DISTINCT FROM v_prima -> n.key
           AND n.key NOT IN ('versione', 'valido_dal', 'modificato_da');
        IF v_campi IS NULL THEN
            RETURN NULL;                      -- UPDATE senza variazioni: nulla da registrare
        END IF;
    END IF;

    INSERT INTO nis2.audit_log (tabella, operazione, chiave, dati_prima, dati_dopo, campi_modificati, motivo)
    VALUES (TG_TABLE_NAME, left(TG_OP, 1), v_chiave, v_prima, v_dopo, v_campi, nis2.fn_motivo_corrente());

    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_audit() IS
  'Trigger AFTER INSERT/UPDATE/DELETE generico: registra ogni modifica in nis2.audit_log in formato JSONB.';

-- =============================================================================
-- 5. TABELLE DI STORICO E ASSOCIAZIONE DEI TRIGGER
-- =============================================================================
DO $$
DECLARE
    v_tab text;
    v_tabelle_storicizzate constant text[] := ARRAY[
        'organizzazione', 'sede', 'persona', 'assegnazione_ruolo',
        'asset', 'servizio', 'fornitore', 'contratto', 'dipendenza_fornitore'];
BEGIN
    FOREACH v_tab IN ARRAY v_tabelle_storicizzate LOOP
        -- stessa struttura della tabella corrente (senza vincoli né identity) + metadati di chiusura
        EXECUTE format('CREATE TABLE IF NOT EXISTS nis2.%I (LIKE nis2.%I INCLUDING COMMENTS)',
                       v_tab || '_storico', v_tab);
        EXECUTE format('ALTER TABLE nis2.%I
                            ADD COLUMN IF NOT EXISTS valido_al     timestamptz  NOT NULL,
                            ADD COLUMN IF NOT EXISTS operazione    char(1)      NOT NULL,
                            ADD COLUMN IF NOT EXISTS motivo        text,
                            ADD COLUMN IF NOT EXISTS archiviato_da varchar(128) NOT NULL',
                       v_tab || '_storico');
        IF NOT EXISTS (SELECT 1 FROM pg_constraint
                        WHERE conrelid = format('nis2.%I', v_tab || '_storico')::regclass
                          AND contype = 'p') THEN
            EXECUTE format('ALTER TABLE nis2.%I ADD CONSTRAINT %I PRIMARY KEY (%I, versione)',
                           v_tab || '_storico', 'pk_' || v_tab || '_storico', v_tab || '_id');
            EXECUTE format('ALTER TABLE nis2.%I ADD CONSTRAINT %I CHECK (operazione IN (''U'', ''D''))',
                           v_tab || '_storico', 'ck_' || v_tab || '_storico_operazione');
            EXECUTE format('ALTER TABLE nis2.%I ADD CONSTRAINT %I CHECK (valido_al >= valido_dal)',
                           v_tab || '_storico', 'ck_' || v_tab || '_storico_intervallo');
        END IF;
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON nis2.%I (%I, valido_dal, valido_al)',
                       'ix_' || v_tab || '_storico_periodo', v_tab || '_storico', v_tab || '_id');

        EXECUTE format('COMMENT ON TABLE nis2.%I IS %L', v_tab || '_storico',
                       'Storico (snapshot-on-write) delle versioni superate di nis2.' || v_tab
                       || '. Una riga per versione, valida nell''intervallo [valido_dal, valido_al). Append-only.');
        EXECUTE format('COMMENT ON COLUMN nis2.%I.valido_al IS %L', v_tab || '_storico',
                       'Istante di fine validità della versione (escluso).');
        EXECUTE format('COMMENT ON COLUMN nis2.%I.operazione IS %L', v_tab || '_storico',
                       'Operazione che ha chiuso la versione: U = modifica, D = cancellazione.');
        EXECUTE format('COMMENT ON COLUMN nis2.%I.motivo IS %L', v_tab || '_storico',
                       'Motivo della modifica dichiarato con nis2.fn_imposta_motivo.');
        EXECUTE format('COMMENT ON COLUMN nis2.%I.archiviato_da IS %L', v_tab || '_storico',
                       'Utente database che ha chiuso la versione.');

        -- trigger sulla tabella corrente (l'ordine alfabetico del nome determina l'ordine di esecuzione)
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_10_versione
                            BEFORE INSERT OR UPDATE ON nis2.%I
                            FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_versione()', v_tab, v_tab);
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_80_storico
                            AFTER UPDATE OR DELETE ON nis2.%I
                            FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_storico()', v_tab, v_tab);
        -- lo storico non si modifica
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_storico_immutabile
                            BEFORE UPDATE OR DELETE ON nis2.%I
                            FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_immutabile()', v_tab, v_tab || '_storico');
    END LOOP;
END;
$$;

-- Audit su tutte le tabelle dello schema, escluse audit_log e le tabelle di storico
DO $$
DECLARE
    v_tab text;
BEGIN
    FOR v_tab IN
        SELECT c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'nis2'
           AND c.relkind = 'r'
           AND c.relname <> 'audit_log'
           AND c.relname NOT LIKE '%\_storico'
         ORDER BY c.relname
    LOOP
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_90_audit
                            AFTER INSERT OR UPDATE OR DELETE ON nis2.%I
                            FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_audit()', v_tab, v_tab);
    END LOOP;
END;
$$;

CREATE OR REPLACE TRIGGER trg_audit_log_immutabile
    BEFORE UPDATE OR DELETE ON nis2.audit_log
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_immutabile();

-- =============================================================================
-- 6. REGOLE DI INTEGRITÀ PROCEDURALI
-- =============================================================================

-- 6.1 Ruoli: unicità temporale e incompatibilità punto di contatto / sostituto
CREATE OR REPLACE FUNCTION nis2.fn_trg_assegnazione_regole()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_unico    boolean;
    v_periodo  daterange;
    v_conflitto record;
BEGIN
    -- date incoerenti: decide il vincolo CHECK ck_assegnazione_date (errore 23514)
    IF NEW.data_fine < NEW.data_inizio THEN
        RETURN NEW;
    END IF;
    v_periodo := daterange(NEW.data_inizio, NEW.data_fine, '[]');

    -- serializza le assegnazioni concorrenti della stessa organizzazione
    PERFORM pg_advisory_xact_lock(hashtextextended('nis2.assegnazione_ruolo:' || NEW.organizzazione_id, 0));

    SELECT r.unico_per_organizzazione INTO v_unico
      FROM nis2.ruolo r WHERE r.codice = NEW.ruolo_codice;

    IF v_unico THEN
        SELECT a.assegnazione_ruolo_id, a.data_inizio, a.data_fine INTO v_conflitto
          FROM nis2.assegnazione_ruolo a
         WHERE a.organizzazione_id = NEW.organizzazione_id
           AND a.ruolo_codice      = NEW.ruolo_codice
           AND a.assegnazione_ruolo_id <> NEW.assegnazione_ruolo_id
           AND daterange(a.data_inizio, a.data_fine, '[]') && v_periodo
         LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'Il ruolo % è già assegnato per l''organizzazione % nel periodo % - % (assegnazione %)',
                  NEW.ruolo_codice, NEW.organizzazione_id, v_conflitto.data_inizio,
                  coalesce(v_conflitto.data_fine::text, 'in corso'), v_conflitto.assegnazione_ruolo_id
                  USING ERRCODE = 'NIS02',
                        HINT = 'Chiudere prima l''incarico in corso (data_fine) o usare nis2.sp_sostituisci_titolare_ruolo.';
        END IF;
    END IF;

    IF NEW.ruolo_codice IN ('PUNTO_CONTATTO', 'SOSTITUTO_PUNTO_CONTATTO') AND EXISTS (
        SELECT 1
          FROM nis2.assegnazione_ruolo a
         WHERE a.organizzazione_id = NEW.organizzazione_id
           AND a.persona_id        = NEW.persona_id
           AND a.ruolo_codice IN ('PUNTO_CONTATTO', 'SOSTITUTO_PUNTO_CONTATTO')
           AND a.ruolo_codice     <> NEW.ruolo_codice
           AND daterange(a.data_inizio, a.data_fine, '[]') && v_periodo) THEN
        RAISE EXCEPTION 'La stessa persona non può essere contemporaneamente punto di contatto e sostituto (organizzazione %)',
              NEW.organizzazione_id
              USING ERRCODE = 'NIS03';
    END IF;

    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_assegnazione_regole() IS
  'Trigger BEFORE INSERT/UPDATE su assegnazione_ruolo: un solo titolare per i ruoli unici in periodi sovrapposti; punto di contatto e sostituto devono essere persone diverse.';

CREATE OR REPLACE TRIGGER trg_assegnazione_ruolo_20_regole
    BEFORE INSERT OR UPDATE ON nis2.assegnazione_ruolo
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_assegnazione_regole();

-- 6.2 Coerenza dell'organizzazione tra entità collegate
CREATE OR REPLACE FUNCTION nis2.fn_trg_coerenza_organizzazione()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_org_a bigint;
    v_org_b bigint;
    v_descr text;
BEGIN
    CASE TG_TABLE_NAME
    WHEN 'asset' THEN
        IF NEW.sede_id IS NULL THEN RETURN NEW; END IF;
        v_org_a := NEW.organizzazione_id;
        SELECT s.organizzazione_id INTO v_org_b FROM nis2.sede s WHERE s.sede_id = NEW.sede_id;
        v_descr := 'la sede dell''asset appartiene a un''altra organizzazione';
    WHEN 'servizio_asset' THEN
        SELECT s.organizzazione_id INTO v_org_a FROM nis2.servizio s WHERE s.servizio_id = NEW.servizio_id;
        SELECT a.organizzazione_id INTO v_org_b FROM nis2.asset a WHERE a.asset_id = NEW.asset_id;
        v_descr := 'servizio e asset appartengono a organizzazioni diverse';
    WHEN 'dipendenza_asset' THEN
        SELECT a.organizzazione_id INTO v_org_a FROM nis2.asset a WHERE a.asset_id = NEW.asset_id;
        SELECT a.organizzazione_id INTO v_org_b FROM nis2.asset a WHERE a.asset_id = NEW.asset_richiesto_id;
        v_descr := 'la dipendenza collega asset di organizzazioni diverse (usare dipendenza_fornitore)';
    WHEN 'dipendenza_fornitore' THEN
        SELECT c.organizzazione_id INTO v_org_a FROM nis2.contratto c WHERE c.contratto_id = NEW.contratto_id;
        IF NEW.servizio_id IS NOT NULL THEN
            SELECT s.organizzazione_id INTO v_org_b FROM nis2.servizio s WHERE s.servizio_id = NEW.servizio_id;
        ELSE
            SELECT a.organizzazione_id INTO v_org_b FROM nis2.asset a WHERE a.asset_id = NEW.asset_id;
        END IF;
        v_descr := 'il contratto non è stipulato dall''organizzazione titolare del servizio/asset';
    WHEN 'contratto' THEN
        SELECT f.organizzazione_id INTO v_org_b FROM nis2.fornitore f WHERE f.fornitore_id = NEW.fornitore_id;
        IF v_org_b IS NOT NULL AND v_org_b = NEW.organizzazione_id THEN
            RAISE EXCEPTION 'Un''organizzazione non può essere fornitore di sé stessa (organizzazione %)', NEW.organizzazione_id
                  USING ERRCODE = 'NIS05';
        END IF;
        RETURN NEW;
    END CASE;

    -- se uno dei riferimenti non esiste, decide il vincolo FK (errore 23503)
    IF v_org_a IS NOT NULL AND v_org_b IS NOT NULL AND v_org_a <> v_org_b THEN
        RAISE EXCEPTION 'Incoerenza di organizzazione su %: %', TG_TABLE_NAME, v_descr
              USING ERRCODE = 'NIS05';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_coerenza_organizzazione() IS
  'Trigger BEFORE INSERT/UPDATE: verifica che le entità collegate appartengano alla stessa organizzazione (sede-asset, servizio-asset, asset-asset, contratto-oggetto) e che nessuno sia fornitore di sé stesso.';

CREATE OR REPLACE TRIGGER trg_asset_20_coerenza
    BEFORE INSERT OR UPDATE ON nis2.asset
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_coerenza_organizzazione();
CREATE OR REPLACE TRIGGER trg_servizio_asset_20_coerenza
    BEFORE INSERT OR UPDATE ON nis2.servizio_asset
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_coerenza_organizzazione();
CREATE OR REPLACE TRIGGER trg_dipendenza_asset_20_coerenza
    BEFORE INSERT OR UPDATE ON nis2.dipendenza_asset
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_coerenza_organizzazione();
CREATE OR REPLACE TRIGGER trg_dipendenza_fornitore_20_coerenza
    BEFORE INSERT OR UPDATE ON nis2.dipendenza_fornitore
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_coerenza_organizzazione();
CREATE OR REPLACE TRIGGER trg_contratto_20_coerenza
    BEFORE INSERT OR UPDATE ON nis2.contratto
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_coerenza_organizzazione();

-- 6.3 Controllo anti-ciclo sul grafo delle dipendenze tra asset
CREATE OR REPLACE FUNCTION nis2.fn_trg_dipendenza_asset_aciclica()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_da bigint;
    v_old_a  bigint;
    v_ciclo  boolean;
BEGIN
    -- l'autodipendenza è gestita dal vincolo CHECK ck_dipendenza_asset_no_self
    IF NEW.asset_id = NEW.asset_richiesto_id THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('nis2.dipendenza_asset', 0));

    IF TG_OP = 'UPDATE' THEN               -- l'arco che si sta modificando non va considerato
        v_old_da := OLD.asset_id;
        v_old_a  := OLD.asset_richiesto_id;
    END IF;

    -- esiste già un cammino asset_richiesto -> ... -> asset? allora il nuovo arco chiude un ciclo
    WITH RECURSIVE raggiungibili (asset_id) AS (
        SELECT NEW.asset_richiesto_id
        UNION
        SELECT d.asset_richiesto_id
          FROM nis2.dipendenza_asset d
          JOIN raggiungibili r ON d.asset_id = r.asset_id
         WHERE NOT (d.asset_id = v_old_da AND d.asset_richiesto_id = v_old_a)
            OR v_old_da IS NULL
    )
    SELECT EXISTS (SELECT 1 FROM raggiungibili WHERE asset_id = NEW.asset_id) INTO v_ciclo;

    IF v_ciclo THEN
        RAISE EXCEPTION 'La dipendenza % -> % creerebbe un ciclo nel grafo degli asset',
              NEW.asset_id, NEW.asset_richiesto_id
              USING ERRCODE = 'NIS04';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_dipendenza_asset_aciclica() IS
  'Trigger BEFORE INSERT/UPDATE su dipendenza_asset: rifiuta gli archi che chiuderebbero un ciclo (visita ricorsiva del grafo).';

CREATE OR REPLACE TRIGGER trg_dipendenza_asset_30_aciclica
    BEFORE INSERT OR UPDATE ON nis2.dipendenza_asset
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_dipendenza_asset_aciclica();


-- 6.4 Categorizzazione delle attività e dei servizi (Det. ACN 155238/2026, art. 3)
CREATE OR REPLACE FUNCTION nis2.fn_trg_servizio_categoria()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_modello      varchar;
    v_predefinita  varchar;
BEGIN
    SELECT st.modello_categorizzazione_codice INTO v_modello
      FROM nis2.organizzazione o
      JOIN nis2.tipologia_soggetto t ON t.codice = o.tipologia_soggetto_codice
      JOIN nis2.sottosettore ss      ON ss.codice = t.sottosettore_codice
      JOIN nis2.settore st           ON st.codice = ss.settore_codice
     WHERE o.organizzazione_id = NEW.organizzazione_id;

    IF v_modello IS NULL THEN
        RETURN NEW;                     -- modello non determinato: nessun confronto possibile
    END IF;

    SELECT mm.categoria_predefinita_codice INTO v_predefinita
      FROM nis2.macro_area_modello mm
     WHERE mm.modello_codice = v_modello AND mm.macro_area_codice = NEW.macro_area_codice;

    IF NEW.categoria_rilevanza_codice IS DISTINCT FROM v_predefinita
       AND coalesce(btrim(NEW.valutazione_categoria), '') = '' THEN
        RAISE EXCEPTION 'Categoria % diversa da quella pre-assegnata (%) alla macro-area % senza valutazione documentata',
              NEW.categoria_rilevanza_codice, v_predefinita, NEW.macro_area_codice
              USING ERRCODE = 'NIS09',
                    HINT = 'Compilare valutazione_categoria (Determinazione ACN 155238/2026, art. 3, c. 3).';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION nis2.fn_trg_servizio_categoria() IS
  'Trigger BEFORE INSERT/UPDATE su servizio: se la categoria di rilevanza differisce da quella pre-assegnata alla macro-area nel modello del soggetto, richiede la valutazione documentata (Det. ACN 155238/2026, art. 3, c. 3).';

CREATE OR REPLACE TRIGGER trg_servizio_20_categoria
    BEFORE INSERT OR UPDATE ON nis2.servizio
    FOR EACH ROW EXECUTE FUNCTION nis2.fn_trg_servizio_categoria();

-- =============================================================================
-- 7. CONSULTAZIONE DELLO STATO A UNA DATA E PROCEDURE DI MANUTENZIONE
-- =============================================================================

-- Stato di un record di qualsiasi tabella storicizzata a un certo istante (JSONB)
CREATE OR REPLACE FUNCTION nis2.fn_record_alla_data(p_tabella text, p_id bigint, p_istante timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_risultato jsonb;
BEGIN
    IF to_regclass(format('nis2.%I', p_tabella || '_storico')) IS NULL THEN
        RAISE EXCEPTION 'La tabella % non è storicizzata', p_tabella USING ERRCODE = 'NIS08';
    END IF;

    -- versione corrente, se già valida all'istante richiesto
    EXECUTE format('SELECT to_jsonb(t) FROM nis2.%I t WHERE t.%I = $1 AND t.valido_dal <= $2',
                   p_tabella, p_tabella || '_id')
       INTO v_risultato USING p_id, p_istante;

    -- altrimenti la versione storica il cui intervallo contiene l'istante
    IF v_risultato IS NULL THEN
        EXECUTE format('SELECT to_jsonb(s) FROM nis2.%I s
                         WHERE s.%I = $1 AND s.valido_dal <= $2 AND s.valido_al > $2',
                       p_tabella || '_storico', p_tabella || '_id')
           INTO v_risultato USING p_id, p_istante;
    END IF;

    RETURN v_risultato;   -- NULL se il record non esisteva a quell'istante
END;
$$;
COMMENT ON FUNCTION nis2.fn_record_alla_data(text, bigint, timestamptz) IS
  'Restituisce in JSONB lo stato del record p_id della tabella storicizzata p_tabella all''istante p_istante (NULL se non esisteva).';

-- Variante tipizzata per gli asset: restituisce una riga con la struttura di nis2.asset
CREATE OR REPLACE FUNCTION nis2.fn_asset_alla_data(p_asset_id bigint, p_istante timestamptz)
RETURNS SETOF nis2.asset
LANGUAGE sql
STABLE
AS $$
    SELECT r.*
      FROM jsonb_populate_record(NULL::nis2.asset,
                                 nis2.fn_record_alla_data('asset', p_asset_id, p_istante)) AS r
     WHERE r.asset_id IS NOT NULL;
$$;
COMMENT ON FUNCTION nis2.fn_asset_alla_data(bigint, timestamptz) IS
  'Stato di un asset a una data, con la stessa struttura della tabella nis2.asset (vuoto se non esisteva).';

-- Sostituzione atomica del titolare di un ruolo (chiude l'incarico in corso e apre il nuovo)
CREATE OR REPLACE PROCEDURE nis2.sp_sostituisci_titolare_ruolo(
    p_organizzazione_id bigint,
    p_ruolo_codice      varchar,
    p_nuova_persona_id  bigint,
    p_data_decorrenza   date,
    p_motivo            text,
    p_atto_nomina       varchar DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_data_decorrenza IS NULL THEN
        RAISE EXCEPTION 'La data di decorrenza è obbligatoria';
    END IF;

    PERFORM nis2.fn_imposta_motivo(p_motivo);

    -- chiude l'incarico in corso (se esiste) il giorno precedente alla decorrenza
    UPDATE nis2.assegnazione_ruolo
       SET data_fine = p_data_decorrenza - 1
     WHERE organizzazione_id = p_organizzazione_id
       AND ruolo_codice      = p_ruolo_codice
       AND data_inizio       < p_data_decorrenza
       AND (data_fine IS NULL OR data_fine >= p_data_decorrenza);

    INSERT INTO nis2.assegnazione_ruolo (organizzazione_id, persona_id, ruolo_codice, data_inizio, atto_nomina)
    VALUES (p_organizzazione_id, p_nuova_persona_id, p_ruolo_codice, p_data_decorrenza, p_atto_nomina);
END;
$$;
COMMENT ON PROCEDURE nis2.sp_sostituisci_titolare_ruolo(bigint, varchar, bigint, date, text, varchar) IS
  'Sostituisce in modo atomico il titolare di un ruolo: chiude l''incarico in corso al giorno precedente la decorrenza e crea il nuovo, registrando il motivo in storico e audit.';

COMMIT;

RESET client_min_messages;
