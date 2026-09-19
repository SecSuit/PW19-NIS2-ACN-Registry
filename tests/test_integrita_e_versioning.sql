-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : tests/test_integrita_e_versioning.sql
-- Scopo     : verifica automatica di vincoli, regole procedurali, versioning,
--             storico, audit, conteggi, profilo ACN, CSV e privacy del dataset.
-- Prerequisito: deploy completo (sql/00_run_all.sql) sul database corrente.
-- Esecuzione:  psql / PSQL Tool:   \i 'C:/.../tests/test_integrita_e_versioning.sql'
--              pgAdmin Query Tool: aprire il file ed eseguire (F5); esiti e
--              riga finale "=== ESITO ..." sono nella scheda "Messages".
-- Effetti:     NESSUNO. Tutti i test girano in un'unica transazione annullata
--              con ROLLBACK finale: il database resta identico. Gli esiti sono
--              raccolti in una tabella temporanea e riepilogati prima del
--              ROLLBACK, quindi il risultato è lo stesso sia in psql/PSQL Tool
--              sia nel Query Tool (che invia lo script come un'unica richiesta).
-- Convenzione: ogni test stampa "[PASS]" o "[FAIL]" con RAISE NOTICE.
--              Per i test negativi si verifica lo SQLSTATE atteso:
--              23514 check_violation   23503 foreign_key_violation
--              23505 unique_violation  23P01 exclusion_violation
--              23001 restrict_violation
--              428C9 generated_always  NIS0x errori applicativi (05_trigger_versioning.sql)
-- Durata:      pochi secondi (il test T51 genera 30.000 asset sintetici, poi annullati).
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = notice;

BEGIN;

CREATE TEMP TABLE esito_test (
    test_id     text PRIMARY KEY,
    descrizione text NOT NULL,
    superato    boolean NOT NULL,
    dettaglio   text
) ON COMMIT DROP;

-- -----------------------------------------------------------------------------
-- Funzioni di supporto (temporanee, annullate dal ROLLBACK)
-- -----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.registra(p_id text, p_descrizione text, p_ok boolean, p_info text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO esito_test VALUES (p_id, p_descrizione, coalesce(p_ok, false), CASE WHEN p_ok THEN NULL ELSE p_info END);
    IF p_ok THEN
        RAISE NOTICE '[PASS] % - %', p_id, p_descrizione;
    ELSE
        RAISE NOTICE '[FAIL] % - % (%)', p_id, p_descrizione, coalesce(p_info, 'esito inatteso');
    END IF;
END;
$$;

-- Esegue un comando che DEVE fallire con lo SQLSTATE indicato
CREATE FUNCTION pg_temp.errore_atteso(p_id text, p_descrizione text, p_sql text, p_sqlstate text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp.registra(p_id, p_descrizione, false, 'il comando è stato accettato');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.registra(p_id, p_descrizione, SQLSTATE = p_sqlstate,
                                 'atteso ' || p_sqlstate || ', ottenuto ' || SQLSTATE || ': ' || SQLERRM);
    END;
END;
$$;

CREATE FUNCTION pg_temp.aid(p_codice text) RETURNS bigint LANGUAGE sql AS
$$ SELECT asset_id FROM nis2.asset WHERE codice = p_codice $$;

DO $$ BEGIN RAISE NOTICE '=== A. Vincoli dichiarativi (i comandi devono essere RIFIUTATI) ==='; END $$;

SELECT pg_temp.errore_atteso('T01', 'P.IVA con formato errato (10 cifre)',
$$INSERT INTO nis2.organizzazione (ragione_sociale, partita_iva, pec, telefono, email_funzionale, tipologia_soggetto_codice, categoria_soggetto_codice, dimensione_codice)
  VALUES ('Prova S.r.l.', '0123456789', 'prova@pec.prova.example', '+39 095 000 9999', 'nis@prova.example', 'EE_FORNITORI', 'IMPORTANTE', 'MEDIA')$$, '23514');

SELECT pg_temp.errore_atteso('T02', 'P.IVA con cifra di controllo errata',
$$INSERT INTO nis2.organizzazione (ragione_sociale, partita_iva, pec, telefono, email_funzionale, tipologia_soggetto_codice, categoria_soggetto_codice, dimensione_codice)
  VALUES ('Prova S.r.l.', '04738160871', 'prova@pec.prova.example', '+39 095 000 9999', 'nis@prova.example', 'EE_FORNITORI', 'IMPORTANTE', 'MEDIA')$$, '23514');

SELECT pg_temp.errore_atteso('T03', 'P.IVA duplicata',
$$INSERT INTO nis2.organizzazione (ragione_sociale, partita_iva, pec, telefono, email_funzionale, tipologia_soggetto_codice, categoria_soggetto_codice, dimensione_codice)
  VALUES ('Clone S.p.A.', '04738160870', 'clone@pec.clone.example', '+39 095 000 9999', 'nis@clone.example', 'SAN_FARMACEUTICI', 'ESSENZIALE', 'GRANDE')$$, '23505');

SELECT pg_temp.errore_atteso('T04', 'E-mail di persona non valida',
$$INSERT INTO nis2.persona (nome, cognome, email) VALUES ('Mario', 'Prova', 'mario.prova-at-example')$$, '23514');

SELECT pg_temp.errore_atteso('T05', 'FK verso tipo di asset inesistente',
$$INSERT INTO nis2.asset (organizzazione_id, codice, denominazione, tipo_asset_codice, classificazione_codice, criticita_livello, proprietario_persona_id)
  VALUES (1, 'ZNT-TEST-01', 'Asset di prova', 'INESISTENTE', 'INTERNO', 1, 1)$$, '23503');

SELECT pg_temp.errore_atteso('T06', 'Asset critico (livello 4) senza RTO/RPO',
$$INSERT INTO nis2.asset (organizzazione_id, codice, denominazione, tipo_asset_codice, classificazione_codice, criticita_livello, proprietario_persona_id)
  VALUES (1, 'ZNT-TEST-02', 'Asset critico incompleto', 'APPLICAZIONE', 'RISERVATO', 4, 1)$$, '23514');

SELECT pg_temp.errore_atteso('T07', 'RTO negativo',
$$UPDATE nis2.asset SET rto_minuti = -5 WHERE codice = 'ZNT-ERP-01'$$, '23514');

SELECT pg_temp.errore_atteso('T08', 'Incarico con data di fine precedente all''inizio',
$$INSERT INTO nis2.assegnazione_ruolo (organizzazione_id, persona_id, ruolo_codice, data_inizio, data_fine)
  VALUES (1, 6, 'MEMBRO_ORGANO_AMM', '2026-01-10', '2025-12-31')$$, '23514');

SELECT pg_temp.errore_atteso('T09', 'Seconda sede legale per la stessa organizzazione',
$$INSERT INTO nis2.sede (organizzazione_id, tipo_sede, denominazione, indirizzo, cap, comune, provincia)
  VALUES (1, 'LEGALE', 'Seconda sede legale', 'Via Prova 1', '95100', 'Catania', 'CT')$$, '23505');

SELECT pg_temp.errore_atteso('T10', 'Dipendenza di un asset da sé stesso',
$$INSERT INTO nis2.dipendenza_asset VALUES (pg_temp.aid('ZNT-AD-01'), pg_temp.aid('ZNT-AD-01'), 'DATI')$$, '23514');

SELECT pg_temp.errore_atteso('T11', 'Dipendenza da fornitore riferita sia a servizio sia ad asset',
$$INSERT INTO nis2.dipendenza_fornitore (contratto_id, servizio_id, asset_id, tipo_fornitura_codice, criterio_rilevanza_codice, criticita_livello)
  VALUES ((SELECT contratto_id FROM nis2.contratto WHERE codice = 'C-ZNT-2024-011'),
          (SELECT servizio_id FROM nis2.servizio WHERE codice = 'ZNT-SRV-PROD'),
          pg_temp.aid('ZNT-MES-01'), 'SERVIZI_GESTITI', 'TIC', 3)$$, '23514');

SELECT pg_temp.errore_atteso('T12', 'Blocco IP sovrapposto a uno già registrato',
$$INSERT INTO nis2.spazio_ip (organizzazione_id, rete, descrizione) VALUES (2, '192.0.2.16/28', 'Sovrapposto')$$, '23P01');

SELECT pg_temp.errore_atteso('T13', 'Cancellazione di organizzazione con elementi collegati (ON DELETE RESTRICT)',
$$DELETE FROM nis2.organizzazione WHERE organizzazione_id = 3$$, '23001');

SELECT pg_temp.errore_atteso('T14', 'Assegnazione esplicita di una PK identity (GENERATED ALWAYS)',
$$UPDATE nis2.asset SET asset_id = 999 WHERE codice = 'ZNT-ERP-01'$$, '428C9');

DO $$ BEGIN RAISE NOTICE '=== B. Regole procedurali (trigger) ==='; END $$;

SELECT pg_temp.errore_atteso('T15', 'Modifica della PK tramite DEFAULT bloccata dal trigger di versioning',
$$UPDATE nis2.asset SET asset_id = DEFAULT WHERE codice = 'ZNT-ERP-01'$$, 'NIS01');

SELECT pg_temp.errore_atteso('T16', 'Secondo punto di contatto con periodo sovrapposto',
$$INSERT INTO nis2.assegnazione_ruolo (organizzazione_id, persona_id, ruolo_codice, data_inizio)
  VALUES (1, 4, 'PUNTO_CONTATTO', '2026-01-01')$$, 'NIS02');

SELECT pg_temp.errore_atteso('T17', 'Nuovo punto di contatto senza chiudere l''incarico in corso',
$$INSERT INTO nis2.assegnazione_ruolo (organizzazione_id, persona_id, ruolo_codice, data_inizio)
  VALUES (2, 11, 'PUNTO_CONTATTO', '2026-03-01')$$, 'NIS02');

SELECT pg_temp.errore_atteso('T18', 'Punto di contatto nominato anche sostituto (incompatibilità)',
$$UPDATE nis2.assegnazione_ruolo SET persona_id = 16
   WHERE organizzazione_id = 3 AND ruolo_codice = 'SOSTITUTO_PUNTO_CONTATTO'$$, 'NIS03');

SELECT pg_temp.errore_atteso('T19', 'Arco che chiude un ciclo (AD -> SER -> MES -> AD)',
$$INSERT INTO nis2.dipendenza_asset VALUES (pg_temp.aid('ZNT-AD-01'), pg_temp.aid('ZNT-SER-01'), 'DATI')$$, 'NIS04');

SELECT pg_temp.errore_atteso('T20', 'Servizio e asset di organizzazioni diverse',
$$INSERT INTO nis2.servizio_asset (servizio_id, asset_id)
  VALUES ((SELECT servizio_id FROM nis2.servizio WHERE codice = 'ZNT-SRV-PROD'), pg_temp.aid('ELY-SCADA-01'))$$, 'NIS05');

SELECT pg_temp.errore_atteso('T21', 'Organizzazione fornitrice di sé stessa',
$$INSERT INTO nis2.contratto (organizzazione_id, fornitore_id, codice, oggetto, data_inizio, clausole_sicurezza, dpa_art28, diritto_audit)
  VALUES (3, (SELECT fornitore_id FROM nis2.fornitore WHERE organizzazione_id = 3), 'C-TDS-TEST', 'Autofornitura', '2026-01-01', true, true, true)$$, 'NIS05');

SELECT pg_temp.errore_atteso('T22', 'Audit log immutabile (UPDATE)',
$$UPDATE nis2.audit_log SET utente = 'intruso' WHERE audit_log_id = 1$$, 'NIS06');

SELECT pg_temp.errore_atteso('T23', 'Storico immutabile (DELETE)',
$$DELETE FROM nis2.asset_storico$$, 'NIS06');

SELECT pg_temp.errore_atteso('T24', 'Profilo ACN di organizzazione inesistente',
$$SELECT * FROM nis2.fn_profilo_acn(999)$$, 'NIS07');

DO $$ BEGIN RAISE NOTICE '=== C. Conteggi e profilo ACN ==='; END $$;

DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(organizzazione_id || ':' || n, ',' ORDER BY organizzazione_id) INTO v
      FROM (SELECT organizzazione_id, count(*) n FROM nis2.v_asset_critici GROUP BY 1) t;
    PERFORM pg_temp.registra('T25', 'Asset critici per organizzazione = 8 / 6 / 5', v = '1:8,2:6,3:5', 'ottenuto ' || v);

    SELECT string_agg(organizzazione_id || ':' || n, ',' ORDER BY organizzazione_id) INTO v
      FROM (SELECT organizzazione_id, count(*) n FROM nis2.v_servizi_erogati WHERE perimetro_nis GROUP BY 1) t;
    PERFORM pg_temp.registra('T26', 'Servizi nel perimetro NIS = 3 / 2 / 2', v = '1:3,2:2,3:2', 'ottenuto ' || v);

    SELECT string_agg(organizzazione_id || ':' || n, ',' ORDER BY organizzazione_id) INTO v
      FROM (SELECT organizzazione_id, count(*) n FROM nis2.v_dipendenze_terze_parti
             WHERE criterio_rilevanza <> 'NON_RILEVANTE' GROUP BY 1) t;
    PERFORM pg_temp.registra('T27', 'Dipendenze da fornitori rilevanti = 7 / 4 / 4', v = '1:7,2:4,3:4', 'ottenuto ' || v);

    SELECT string_agg(organizzazione_id || ':' || n, ',' ORDER BY organizzazione_id) INTO v
      FROM (SELECT organizzazione_id, count(*) n FROM nis2.v_punti_contatto GROUP BY 1) t;
    PERFORM pg_temp.registra('T28', 'Punti di contatto comunicati = 7 / 7 / 5', v = '1:7,2:7,3:5', 'ottenuto ' || v);

    SELECT string_agg(organizzazione_id || ':' || n, ',' ORDER BY organizzazione_id) INTO v
      FROM (SELECT organizzazione_id, count(*) n FROM nis2.v_profilo_acn GROUP BY 1) t;
    PERFORM pg_temp.registra('T29', 'Righe del profilo ACN = 34 / 27 / 24', v = '1:34,2:27,3:24', 'ottenuto ' || v);

    PERFORM pg_temp.registra('T30', 'Ogni profilo contiene tutte le 8 sezioni',
        NOT EXISTS (SELECT 1 FROM nis2.organizzazione o
                     WHERE (SELECT count(DISTINCT sezione) FROM nis2.fn_profilo_acn(o.organizzazione_id)) <> 8));

    PERFORM pg_temp.registra('T31', 'Ogni organizzazione ha esattamente un punto di contatto e un sostituto in carica',
        NOT EXISTS (SELECT 1 FROM nis2.organizzazione o
                     WHERE (SELECT count(*) FROM nis2.v_punti_contatto p
                             WHERE p.organizzazione_id = o.organizzazione_id AND p.ruolo_codice = 'PUNTO_CONTATTO') <> 1
                        OR (SELECT count(*) FROM nis2.v_punti_contatto p
                             WHERE p.organizzazione_id = o.organizzazione_id AND p.ruolo_codice = 'SOSTITUTO_PUNTO_CONTATTO') <> 1));

    PERFORM pg_temp.registra('T32', 'La funzione restituisce le stesse righe della vista',
        (SELECT count(*) FROM nis2.fn_profilo_acn(2)) = (SELECT count(*) FROM nis2.v_profilo_acn WHERE organizzazione_id = 2));
END;
$$;

DO $$
DECLARE
    v_csv    text := nis2.fn_profilo_acn_csv(1);
    v_righe  integer;
    v_header text;
BEGIN
    v_righe  := array_length(string_to_array(rtrim(v_csv, E'\r\n'), E'\r\n'), 1);
    v_header := split_part(v_csv, E'\r\n', 1);
    PERFORM pg_temp.registra('T33', 'CSV: intestazione + 34 righe dati per Zagara', v_righe = 35, 'righe ' || v_righe);
    PERFORM pg_temp.registra('T34', 'CSV: 16 colonne nell''intestazione',
        array_length(string_to_array(v_header, ','), 1) = 16, v_header);
    PERFORM pg_temp.registra('T35', 'CSV: i campi con separatore sono racchiusi tra virgolette',
        v_csv LIKE '%"Sede legale: Viale delle Zagare 18, 95121 Catania (CT)%');
    PERFORM pg_temp.registra('T36', 'CSV con separatore ";" per Excel in italiano',
        split_part(nis2.fn_profilo_acn_csv(1, ';'), E'\r\n', 1) LIKE 'organizzazione_id;partita_iva;%');
END;
$$;

DO $$ BEGIN RAISE NOTICE '=== D. Versioning, storico e audit ==='; END $$;

DO $$
DECLARE
    v_id        bigint := pg_temp.aid('ZNT-ERP-01');
    v_prima     timestamptz;
    v_versione  integer;
    v_storico   record;
    v_audit     record;
    v_n         integer;
BEGIN
    v_prima := clock_timestamp();
    PERFORM pg_sleep(0.01);
    PERFORM nis2.fn_imposta_motivo('Test T37: revisione RTO');
    UPDATE nis2.asset SET rto_minuti = 360 WHERE asset_id = v_id;

    SELECT versione INTO v_versione FROM nis2.asset WHERE asset_id = v_id;
    PERFORM pg_temp.registra('T37', 'UPDATE incrementa la versione (1 -> 2)', v_versione = 2, 'versione ' || v_versione);

    SELECT * INTO v_storico FROM nis2.asset_storico WHERE asset_id = v_id AND versione = 1;
    PERFORM pg_temp.registra('T38', 'La versione precedente è archiviata nello storico con valori e motivo',
        FOUND AND v_storico.rto_minuti = 480 AND v_storico.operazione = 'U'
              AND v_storico.motivo = 'Test T37: revisione RTO'
              AND v_storico.valido_al = (SELECT valido_dal FROM nis2.asset WHERE asset_id = v_id));

    UPDATE nis2.asset SET rto_minuti = 360 WHERE asset_id = v_id;     -- nessuna variazione reale
    SELECT count(*) INTO v_n FROM nis2.asset_storico WHERE asset_id = v_id;
    SELECT versione INTO v_versione FROM nis2.asset WHERE asset_id = v_id;
    PERFORM pg_temp.registra('T39', 'UPDATE senza variazioni non crea nuove versioni', v_n = 1 AND v_versione = 2);

    PERFORM pg_temp.registra('T40', 'fn_asset_alla_data: stato precedente (RTO 480) e attuale (RTO 360)',
        (SELECT rto_minuti FROM nis2.fn_asset_alla_data(v_id, v_prima)) = 480
        AND (SELECT rto_minuti FROM nis2.fn_asset_alla_data(v_id, clock_timestamp())) = 360);

    PERFORM pg_temp.registra('T41', 'fn_record_alla_data: record non ancora esistente = NULL',
        nis2.fn_record_alla_data('asset', v_id, TIMESTAMPTZ '2000-01-01') IS NULL);

    SELECT * INTO v_audit FROM nis2.audit_log
     WHERE tabella = 'asset' AND operazione = 'U' AND chiave = jsonb_build_object('asset_id', v_id)
     ORDER BY audit_log_id DESC LIMIT 1;
    PERFORM pg_temp.registra('T42', 'Audit log: modifica registrata con campi modificati, prima/dopo e motivo',
        FOUND AND v_audit.campi_modificati = ARRAY['rto_minuti']
              AND (v_audit.dati_prima ->> 'rto_minuti')::int = 480
              AND (v_audit.dati_dopo  ->> 'rto_minuti')::int = 360
              AND v_audit.motivo = 'Test T37: revisione RTO');
END;
$$;

DO $$
DECLARE
    v_id bigint := pg_temp.aid('ZNT-INT-01');
    v_ok boolean;
BEGIN
    PERFORM nis2.fn_imposta_motivo('Test T43: dismissione intranet');
    DELETE FROM nis2.asset WHERE asset_id = v_id;
    SELECT EXISTS (SELECT 1 FROM nis2.asset_storico WHERE asset_id = v_id AND operazione = 'D'
                     AND motivo = 'Test T43: dismissione intranet') INTO v_ok;
    PERFORM pg_temp.registra('T43', 'DELETE archivia l''ultima versione con operazione D', v_ok);
    PERFORM pg_temp.registra('T44', 'DELETE: le associazioni servizio_asset sono rimosse in cascata',
        NOT EXISTS (SELECT 1 FROM nis2.servizio_asset WHERE asset_id = v_id));
    PERFORM pg_temp.registra('T45', 'DELETE registrato nell''audit con immagine "prima"',
        EXISTS (SELECT 1 FROM nis2.audit_log WHERE tabella = 'asset' AND operazione = 'D'
                  AND chiave = jsonb_build_object('asset_id', v_id) AND dati_prima ->> 'codice' = 'ZNT-INT-01'));
END;
$$;

DO $$
DECLARE
    v_vecchio record;
    v_nuovo   record;
BEGIN
    CALL nis2.sp_sostituisci_titolare_ruolo(2, 'SOSTITUTO_PUNTO_CONTATTO', 12, current_date + 1,
                                            'Test T46: cambio sostituto', 'Delibera di prova');
    SELECT * INTO v_vecchio FROM nis2.assegnazione_ruolo
     WHERE organizzazione_id = 2 AND ruolo_codice = 'SOSTITUTO_PUNTO_CONTATTO' AND persona_id = 11;
    SELECT * INTO v_nuovo FROM nis2.assegnazione_ruolo
     WHERE organizzazione_id = 2 AND ruolo_codice = 'SOSTITUTO_PUNTO_CONTATTO' AND persona_id = 12;
    PERFORM pg_temp.registra('T46', 'Procedura di sostituzione: vecchio incarico chiuso oggi, nuovo da domani',
        v_vecchio.data_fine = current_date AND v_vecchio.versione = 2 AND v_nuovo.data_inizio = current_date + 1);
    PERFORM pg_temp.registra('T47', 'Oggi il sostituto in carica è ancora il precedente',
        (SELECT cognome FROM nis2.v_punti_contatto
          WHERE organizzazione_id = 2 AND ruolo_codice = 'SOSTITUTO_PUNTO_CONTATTO') = 'Cangemi');
END;
$$;

DO $$ BEGIN RAISE NOTICE '=== E. Privacy by design del dataset ==='; END $$;

DO $$
BEGIN
    PERFORM pg_temp.registra('T48', 'Tutte le e-mail e PEC usano domini riservati (.example / .test)',
        NOT EXISTS (
            SELECT email FROM nis2.persona WHERE email !~ '\.(example|test)$'
            UNION ALL SELECT pec FROM nis2.organizzazione WHERE pec !~ '\.(example|test)$'
            UNION ALL SELECT email_contatto FROM nis2.fornitore WHERE email_contatto !~ '\.(example|test)$'
            UNION ALL SELECT nome_dominio FROM nis2.dominio WHERE nome_dominio !~ '\.(example|test)$'));
    PERFORM pg_temp.registra('T49', 'Tutti gli indirizzi IP appartengono ai blocchi di documentazione',
        NOT EXISTS (SELECT 1 FROM nis2.spazio_ip
                     WHERE NOT (rete <<= '192.0.2.0/24' OR rete <<= '198.51.100.0/24'
                                OR rete <<= '203.0.113.0/24' OR rete <<= '2001:db8::/32')));
END;
$$;

DO $$ BEGIN RAISE NOTICE '=== F. Codifica UTF-8 e diagnostica delle prestazioni ==='; END $$;

DO $$
DECLARE
    v_testo text;
    v_prima bigint;
    v_audit bigint;
    v_piano text;
BEGIN
    -- 'à' (U+00E0) deve essere 1 carattere e 2 byte: il file è stato letto come UTF-8
    SELECT denominazione INTO v_testo FROM nis2.servizio WHERE codice = 'ZNT-SRV-DIST';
    PERFORM pg_temp.registra('T50', 'Lettere accentate lette e memorizzate in UTF-8 (tracciabilità, Paternò)',
        v_testo = 'Distribuzione e tracciabilità dei medicinali'
        AND strpos(v_testo, U&'\00E0') > 0
        AND octet_length('à') = 2 AND char_length('à') = 1
        AND current_setting('server_encoding') = 'UTF8'
        AND EXISTS (SELECT 1 FROM nis2.sede WHERE comune = 'Paternò' AND char_length(comune) = 7 AND octet_length(comune) = 8),
        'testo letto: ' || coalesce(v_testo, 'NULL') || ' / server_encoding ' || current_setting('server_encoding'));

    SELECT count(*) INTO v_prima FROM nis2.asset;
    SELECT count(*) INTO v_audit FROM nis2.audit_log;
    SELECT string_agg("QUERY PLAN", E'\n') INTO v_piano FROM nis2.fn_piano_asset_critici(30000, 1);
    PERFORM pg_temp.registra('T51', 'Piano di esecuzione: la ricerca degli asset critici usa ix_asset_critici',
        v_piano LIKE '%ix_asset_critici%', left(v_piano, 200));
    PERFORM pg_temp.registra('T52', 'La funzione diagnostica non lascia dati sintetici (asset e audit invariati)',
        (SELECT count(*) FROM nis2.asset) = v_prima AND (SELECT count(*) FROM nis2.audit_log) = v_audit);
END;
$$;

DO $$ BEGIN RAISE NOTICE '=== G. Categorizzazione delle attività e dei servizi (Det. ACN 155238/2026) ==='; END $$;

SELECT pg_temp.errore_atteso('T53', 'Categoria diversa da quella pre-assegnata senza valutazione documentata',
$$UPDATE nis2.servizio SET categoria_rilevanza_codice = 'IMPATTO_ALTO', valutazione_categoria = NULL
   WHERE codice = 'ZNT-SRV-RD'$$, 'NIS09');

DO $$
DECLARE
    v_n   integer;
    v_sco integer;
    v_val integer;
BEGIN
    UPDATE nis2.servizio SET categoria_rilevanza_codice = 'IMPATTO_ALTO',
           valutazione_categoria = 'Test T54: nuova molecola in fase clinica'
     WHERE codice = 'ZNT-SRV-RD';
    PERFORM pg_temp.registra('T54', 'Scostamento accettato se la valutazione è documentata',
        (SELECT categoria_rilevanza_codice FROM nis2.servizio WHERE codice = 'ZNT-SRV-RD') = 'IMPATTO_ALTO');

    SELECT count(*), count(*) FILTER (WHERE scostamento),
           count(*) FILTER (WHERE scostamento AND coalesce(btrim(valutazione_categoria), '') <> '')
      INTO v_n, v_sco, v_val
      FROM nis2.v_categorizzazione_attivita;
    PERFORM pg_temp.registra('T55', 'Elenco categorizzato: ogni attività ha macro-area e categoria; ogni scostamento è motivato',
        v_n = (SELECT count(*) FROM nis2.servizio) AND v_sco = v_val AND v_sco > 0,
        format('attività %s, scostamenti %s, motivati %s', v_n, v_sco, v_val));

    PERFORM pg_temp.registra('T56', 'Modelli ACN: Logistica pre-assegnata "Impatto basso" (Allegato 1) e "Impatto minimo" (Allegato 2)',
        (SELECT categoria_predefinita_codice FROM nis2.macro_area_modello WHERE modello_codice = 'ALLEGATO_1' AND macro_area_codice = 'LOGISTICA') = 'IMPATTO_BASSO'
        AND (SELECT categoria_predefinita_codice FROM nis2.macro_area_modello WHERE modello_codice = 'ALLEGATO_2' AND macro_area_codice = 'LOGISTICA') = 'IMPATTO_MINIMO'
        AND (SELECT count(*) FROM nis2.macro_area_modello) = 20);
END;
$$;

-- -----------------------------------------------------------------------------
-- Riepilogo (prima del ROLLBACK, così funziona sia in psql/PSQL Tool sia nel
-- Query Tool, che invia lo script come un'unica richiesta)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_pass bigint;
    v_fail bigint;
BEGIN
    SELECT count(*) FILTER (WHERE superato), count(*) FILTER (WHERE NOT superato)
      INTO v_pass, v_fail FROM esito_test;
    RAISE NOTICE '=== ESITO: % PASS, % FAIL su % test (il ROLLBACK finale lascia il database invariato) ===',
                 v_pass, v_fail, v_pass + v_fail;
END;
$$;

SELECT count(*) FILTER (WHERE superato)     AS test_superati,
       count(*) FILTER (WHERE NOT superato) AS test_falliti,
       CASE WHEN bool_and(superato) THEN 'PASS' ELSE 'FAIL' END AS esito_complessivo
  FROM esito_test;

ROLLBACK;
