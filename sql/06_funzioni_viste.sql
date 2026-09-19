-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 06_funzioni_viste.sql
-- Scopo     : viste tematiche e funzioni che generano il profilo ACN
--             (anagrafica, punti di contatto, perimetro di rete, servizi,
--             asset critici, fornitori rilevanti) e il relativo CSV.
-- Dipende da: 05_trigger_versioning.sql
-- Idempotenza: DROP ... IF EXISTS + CREATE (le viste dipendono l'una dall'altra
--              e CREATE OR REPLACE VIEW non consente di cambiare le colonne)
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

DROP FUNCTION IF EXISTS nis2.fn_profilo_acn_csv(bigint, text);
DROP FUNCTION IF EXISTS nis2.fn_profilo_acn(bigint);
DROP FUNCTION IF EXISTS nis2.fn_impatto_asset(bigint);
DROP FUNCTION IF EXISTS nis2.fn_piano_asset_critici(integer, bigint);
DROP VIEW IF EXISTS nis2.v_profilo_acn;
DROP VIEW IF EXISTS nis2.v_categorizzazione_attivita;
DROP VIEW IF EXISTS nis2.v_dipendenze_terze_parti;
DROP VIEW IF EXISTS nis2.v_servizi_erogati;
DROP VIEW IF EXISTS nis2.v_asset_critici;
DROP VIEW IF EXISTS nis2.v_punti_contatto;
DROP VIEW IF EXISTS nis2.v_ruoli_attivi;
DROP VIEW IF EXISTS nis2.v_organizzazione;

-- -----------------------------------------------------------------------------
-- Anagrafica completa: ricostruisce settore e sottosettore dalla tipologia
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_organizzazione AS
SELECT o.organizzazione_id,
       o.ragione_sociale,
       o.partita_iva,
       o.pec,
       o.telefono,
       o.email_funzionale,
       o.sito_web,
       c.denominazione  AS categoria_soggetto,
       st.codice        AS settore_codice,
       st.denominazione AS settore,
       st.allegato,
       st.modello_categorizzazione_codice AS modello_categorizzazione,
       ss.denominazione AS sottosettore,
       t.denominazione  AS tipologia_soggetto,
       d.denominazione  AS dimensione,
       o.numero_dipendenti,
       sl.indirizzo || ', ' || sl.cap || ' ' || sl.comune || ' (' || sl.provincia || ')' AS sede_legale,
       o.versione,
       o.valido_dal
  FROM nis2.organizzazione o
  JOIN nis2.tipologia_soggetto t  ON t.codice  = o.tipologia_soggetto_codice
  JOIN nis2.sottosettore ss       ON ss.codice = t.sottosettore_codice
  JOIN nis2.settore st            ON st.codice = ss.settore_codice
  JOIN nis2.categoria_soggetto c  ON c.codice  = o.categoria_soggetto_codice
  JOIN nis2.dimensione_impresa d  ON d.codice  = o.dimensione_codice
  LEFT JOIN nis2.sede sl          ON sl.organizzazione_id = o.organizzazione_id AND sl.tipo_sede = 'LEGALE';
COMMENT ON VIEW nis2.v_organizzazione IS 'Anagrafica delle organizzazioni con classificazione NIS completa (settore, sottosettore, tipologia, categoria) e sede legale.';

-- -----------------------------------------------------------------------------
-- Ruoli in corso alla data odierna e punti di contatto comunicati all'ACN
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_ruoli_attivi AS
SELECT a.organizzazione_id,
       o.ragione_sociale,
       r.codice         AS ruolo_codice,
       r.denominazione  AS ruolo,
       r.richiesto_acn,
       p.persona_id,
       p.nome,
       p.cognome,
       p.email,
       p.telefono,
       a.data_inizio,
       a.atto_nomina
  FROM nis2.assegnazione_ruolo a
  JOIN nis2.organizzazione o ON o.organizzazione_id = a.organizzazione_id
  JOIN nis2.ruolo r          ON r.codice = a.ruolo_codice
  JOIN nis2.persona p        ON p.persona_id = a.persona_id
 WHERE a.data_inizio <= current_date
   AND (a.data_fine IS NULL OR a.data_fine >= current_date);
COMMENT ON VIEW nis2.v_ruoli_attivi IS 'Incarichi in corso alla data odierna, per organizzazione e ruolo.';

CREATE VIEW nis2.v_punti_contatto AS
SELECT organizzazione_id, ragione_sociale, ruolo_codice, ruolo,
       nome, cognome, email, telefono, data_inizio
  FROM nis2.v_ruoli_attivi
 WHERE richiesto_acn;
COMMENT ON VIEW nis2.v_punti_contatto IS 'Punti di contatto e responsabilità comunicati all''ACN (punto di contatto, sostituto, referenti CSIRT, rappresentante legale, organi di amministrazione) in corso alla data odierna.';

-- -----------------------------------------------------------------------------
-- Asset critici (livello >= 3): usa l'indice parziale ix_asset_critici
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_asset_critici AS
SELECT a.organizzazione_id,
       o.ragione_sociale,
       a.asset_id,
       a.codice,
       a.denominazione,
       ta.denominazione AS tipo_asset,
       ci.denominazione AS classificazione,
       a.criticita_livello,
       lc.denominazione AS criticita,
       a.rto_minuti,
       a.rpo_minuti,
       coalesce(s.denominazione || ' - ' || s.comune, 'Cloud/infrastruttura di terzi') AS ubicazione,
       p.nome || ' ' || p.cognome AS proprietario,
       p.email          AS email_proprietario,
       (SELECT count(*) FROM nis2.servizio_asset sa WHERE sa.asset_id = a.asset_id) AS servizi_supportati
  FROM nis2.asset a
  JOIN nis2.organizzazione o                ON o.organizzazione_id = a.organizzazione_id
  JOIN nis2.tipo_asset ta                   ON ta.codice = a.tipo_asset_codice
  JOIN nis2.classificazione_informazione ci ON ci.codice = a.classificazione_codice
  JOIN nis2.livello_criticita lc            ON lc.livello = a.criticita_livello
  JOIN nis2.persona p                       ON p.persona_id = a.proprietario_persona_id
  LEFT JOIN nis2.sede s                     ON s.sede_id = a.sede_id
 WHERE a.criticita_livello >= 3;
COMMENT ON VIEW nis2.v_asset_critici IS 'Asset con criticità ALTA o CRITICA, con RTO/RPO, ubicazione, proprietario e numero di servizi supportati.';

-- -----------------------------------------------------------------------------
-- Servizi erogati
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_servizi_erogati AS
SELECT s.organizzazione_id,
       o.ragione_sociale,
       s.servizio_id,
       s.codice,
       s.denominazione,
       s.criticita_livello,
       lc.denominazione AS criticita,
       s.utenti_impattati,
       s.perimetro_nis,
       p.nome || ' ' || p.cognome AS responsabile,
       (SELECT string_agg(sp.paese_codice, ', ' ORDER BY sp.paese_codice)
          FROM nis2.servizio_paese sp WHERE sp.servizio_id = s.servizio_id) AS paesi_erogazione,
       (SELECT count(*) FROM nis2.servizio_asset sa WHERE sa.servizio_id = s.servizio_id) AS asset_collegati,
       (SELECT count(*) FROM nis2.dipendenza_fornitore df WHERE df.servizio_id = s.servizio_id) AS dipendenze_dirette
  FROM nis2.servizio s
  JOIN nis2.organizzazione o     ON o.organizzazione_id = s.organizzazione_id
  JOIN nis2.livello_criticita lc ON lc.livello = s.criticita_livello
  JOIN nis2.persona p            ON p.persona_id = s.responsabile_persona_id;
COMMENT ON VIEW nis2.v_servizi_erogati IS 'Servizi erogati con criticità, utenti impattati, Stati di erogazione, asset collegati e dipendenze dirette da terzi.';

-- -----------------------------------------------------------------------------
-- Dipendenze da terze parti (servizi e asset -> contratto -> fornitore)
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_dipendenze_terze_parti AS
SELECT c.organizzazione_id,
       o.ragione_sociale,
       df.dipendenza_fornitore_id,
       CASE WHEN df.servizio_id IS NOT NULL THEN 'SERVIZIO' ELSE 'ASSET' END AS tipo_oggetto,
       coalesce(sv.codice, a.codice)               AS codice_oggetto,
       coalesce(sv.denominazione, a.denominazione) AS oggetto,
       f.fornitore_id,
       f.ragione_sociale                           AS fornitore,
       f.identificativo_fiscale,
       f.paese_codice                              AS paese_fornitore,
       pf.membro_ue                                AS fornitore_ue,
       tf.denominazione                            AS tipo_fornitura,
       tf.fornitura_tic,
       df.criterio_rilevanza_codice                AS criterio_rilevanza,
       df.codice_cpv,
       df.criticita_livello,
       lc.denominazione                            AS criticita,
       df.paese_trattamento_codice                 AS paese_trattamento_dati,
       c.codice                                    AS contratto,
       c.data_fine                                 AS scadenza_contratto,
       c.clausole_sicurezza,
       c.dpa_art28,
       c.diritto_audit,
       c.notifica_incidenti_ore,
       (f.organizzazione_id IS NOT NULL)           AS fornitore_censito
  FROM nis2.dipendenza_fornitore df
  JOIN nis2.contratto c          ON c.contratto_id = df.contratto_id
  JOIN nis2.organizzazione o     ON o.organizzazione_id = c.organizzazione_id
  JOIN nis2.fornitore f          ON f.fornitore_id = c.fornitore_id
  JOIN nis2.paese pf             ON pf.codice = f.paese_codice
  JOIN nis2.tipo_fornitura tf    ON tf.codice = df.tipo_fornitura_codice
  JOIN nis2.livello_criticita lc ON lc.livello = df.criticita_livello
  LEFT JOIN nis2.servizio sv     ON sv.servizio_id = df.servizio_id
  LEFT JOIN nis2.asset a         ON a.asset_id = df.asset_id;
COMMENT ON VIEW nis2.v_dipendenze_terze_parti IS 'Dipendenze di servizi e asset da fornitori terzi, con criterio di rilevanza, codice CPV, garanzie contrattuali e Paese di trattamento dei dati.';


-- -----------------------------------------------------------------------------
-- Elenco categorizzato delle attività e dei servizi (art. 30 D.Lgs. 138/2024;
-- Det. ACN 155238/2026): macro-area, categoria pre-assegnata dal modello del
-- soggetto, categoria attribuita, eventuale scostamento e sua valutazione.
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_categorizzazione_attivita AS
SELECT s.organizzazione_id,
       o.ragione_sociale,
       st.modello_categorizzazione_codice      AS modello,
       s.servizio_id,
       s.codice,
       s.denominazione,
       s.perimetro_nis,
       ma.denominazione                        AS macro_area,
       cp.denominazione                        AS categoria_predefinita,
       ca.denominazione                        AS categoria_attribuita,
       ca.ordine                               AS ordine_categoria,
       (s.categoria_rilevanza_codice IS DISTINCT FROM mm.categoria_predefinita_codice) AS scostamento,
       s.valutazione_categoria
  FROM nis2.servizio s
  JOIN nis2.organizzazione o       ON o.organizzazione_id = s.organizzazione_id
  JOIN nis2.tipologia_soggetto t   ON t.codice  = o.tipologia_soggetto_codice
  JOIN nis2.sottosettore ss        ON ss.codice = t.sottosettore_codice
  JOIN nis2.settore st             ON st.codice = ss.settore_codice
  JOIN nis2.macro_area ma          ON ma.codice = s.macro_area_codice
  JOIN nis2.categoria_rilevanza ca ON ca.codice = s.categoria_rilevanza_codice
  LEFT JOIN nis2.macro_area_modello mm
         ON mm.modello_codice = st.modello_categorizzazione_codice AND mm.macro_area_codice = s.macro_area_codice
  LEFT JOIN nis2.categoria_rilevanza cp ON cp.codice = mm.categoria_predefinita_codice;
COMMENT ON VIEW nis2.v_categorizzazione_attivita IS 'Elenco categorizzato delle attività e dei servizi (art. 30 D.Lgs. 138/2024; Det. ACN 155238/2026): macro-area, categoria pre-assegnata e attribuita, scostamento e valutazione.';

-- -----------------------------------------------------------------------------
-- PROFILO ACN: formato "lungo" a colonne fisse (una riga per elemento),
-- adatto all'export CSV e al caricamento in altri strumenti.
-- -----------------------------------------------------------------------------
CREATE VIEW nis2.v_profilo_acn AS
WITH org AS (
    SELECT * FROM nis2.v_organizzazione
),
elementi AS (
    -- 1. Anagrafica del soggetto
    SELECT o.organizzazione_id,
           '1-ANAGRAFICA'::text                 AS sezione,
           1::bigint                            AS progressivo,
           o.partita_iva::text                  AS codice_elemento,
           o.ragione_sociale::text              AS descrizione_elemento,
           'Sede legale: ' || coalesce(o.sede_legale, 'n/d') || '; tel. ' || o.telefono
             || '; e-mail: ' || o.email_funzionale || '; dimensione: ' || o.dimensione
             || coalesce('; dipendenti: ' || o.numero_dipendenti, '')
             || '; allegato ' || o.allegato      AS dettaglio,
           NULL::text                           AS criticita,
           NULL::text                           AS riferimento,
           'IT'::text                           AS paese,
           o.pec::text                          AS email_contatto
      FROM org o
    UNION ALL
    -- 2. Punti di contatto e responsabilità comunicate
    SELECT pc.organizzazione_id, '2-PUNTI_DI_CONTATTO',
           row_number() OVER (PARTITION BY pc.organizzazione_id ORDER BY pc.ruolo_codice, pc.cognome),
           pc.ruolo_codice, pc.ruolo,
           'Incarico dal ' || to_char(pc.data_inizio, 'DD/MM/YYYY') || coalesce('; tel. ' || pc.telefono, ''),
           NULL, pc.nome || ' ' || pc.cognome, 'IT', pc.email
      FROM nis2.v_punti_contatto pc
    UNION ALL
    -- 3. Spazio di indirizzamento IP pubblico
    SELECT ip.organizzazione_id, '3-SPAZIO_IP',
           row_number() OVER (PARTITION BY ip.organizzazione_id ORDER BY ip.rete),
           ip.rete::text, ip.descrizione, CASE WHEN family(ip.rete) = 4
                THEN 'IPv4, indirizzi: ' || (2 ^ (32 - masklen(ip.rete)))::bigint
                ELSE 'IPv6, prefisso /' || masklen(ip.rete) END,
           NULL, NULL, NULL, NULL
      FROM nis2.spazio_ip ip
    UNION ALL
    -- 4. Nomi di dominio
    SELECT dm.organizzazione_id, '4-DOMINI',
           row_number() OVER (PARTITION BY dm.organizzazione_id ORDER BY dm.nome_dominio),
           dm.nome_dominio, dm.descrizione, NULL,
           NULL, NULL, NULL, NULL
      FROM nis2.dominio dm
    UNION ALL
    -- 5. Attività e servizi nel perimetro NIS
    SELECT se.organizzazione_id, '5-SERVIZI',
           row_number() OVER (PARTITION BY se.organizzazione_id ORDER BY se.criticita_livello DESC, se.codice),
           se.codice, se.denominazione,
           'Utenti impattati: ' || se.utenti_impattati || '; Stati: ' || coalesce(se.paesi_erogazione, 'n/d')
             || '; asset collegati: ' || se.asset_collegati,
           se.criticita, se.responsabile, NULL, NULL
      FROM nis2.v_servizi_erogati se
     WHERE se.perimetro_nis
    UNION ALL
    -- 6. Asset critici
    SELECT ac.organizzazione_id, '6-ASSET_CRITICI',
           row_number() OVER (PARTITION BY ac.organizzazione_id ORDER BY ac.criticita_livello DESC, ac.codice),
           ac.codice, ac.denominazione,
           'Tipo: ' || ac.tipo_asset || '; classificazione: ' || ac.classificazione
             || '; RTO: ' || ac.rto_minuti || ' min; RPO: ' || ac.rpo_minuti || ' min; ubicazione: ' || ac.ubicazione,
           ac.criticita, ac.proprietario, NULL, ac.email_proprietario
      FROM nis2.v_asset_critici ac
    UNION ALL
    -- 7. Fornitori rilevanti (criterio TIC o NON_FUNGIBILE)
    SELECT dt.organizzazione_id, '7-FORNITORI_RILEVANTI',
           row_number() OVER (PARTITION BY dt.organizzazione_id ORDER BY dt.criticita_livello DESC, dt.fornitore, dt.codice_oggetto),
           dt.contratto, dt.fornitore,
           'Oggetto: ' || lower(dt.tipo_oggetto) || ' ' || dt.codice_oggetto
             || '; fornitura: ' || dt.tipo_fornitura
             || '; criterio: ' || dt.criterio_rilevanza
             || coalesce('; CPV: ' || dt.codice_cpv, '')
             || '; clausole sicurezza: ' || CASE WHEN dt.clausole_sicurezza THEN 'sì' ELSE 'no' END
             || '; DPA: ' || CASE WHEN dt.dpa_art28 THEN 'sì' ELSE 'no' END
             || coalesce('; dati trattati in: ' || dt.paese_trattamento_dati, ''),
           dt.criticita, dt.identificativo_fiscale, dt.paese_fornitore, NULL
      FROM nis2.v_dipendenze_terze_parti dt
     WHERE dt.criterio_rilevanza <> 'NON_RILEVANTE'
    UNION ALL
    -- 8. Elenco categorizzato di tutte le attività e dei servizi (art. 30)
    SELECT ct.organizzazione_id, '8-CATEGORIZZAZIONE',
           row_number() OVER (PARTITION BY ct.organizzazione_id ORDER BY ct.ordine_categoria DESC, ct.codice),
           ct.codice, ct.denominazione,
           'Macro-area: ' || ct.macro_area
             || '; categoria pre-assegnata: ' || coalesce(ct.categoria_predefinita, 'n/d')
             || '; perimetro NIS: ' || CASE WHEN ct.perimetro_nis THEN 'sì' ELSE 'no' END
             || CASE WHEN ct.scostamento THEN '; scostamento motivato: ' || ct.valutazione_categoria ELSE '' END,
           ct.categoria_attribuita, NULL, NULL, NULL
      FROM nis2.v_categorizzazione_attivita ct
)
SELECT o.organizzazione_id,
       o.partita_iva::text        AS partita_iva,
       o.ragione_sociale::text    AS ragione_sociale,
       o.categoria_soggetto::text AS categoria_soggetto,
       o.settore::text            AS settore,
       o.sottosettore::text       AS sottosettore,
       e.sezione,
       e.progressivo::integer     AS progressivo,
       e.codice_elemento,
       e.descrizione_elemento,
       e.dettaglio,
       e.criticita,
       e.riferimento,
       e.paese,
       e.email_contatto,
       current_date               AS data_estrazione
  FROM elementi e
  JOIN org o ON o.organizzazione_id = e.organizzazione_id;
COMMENT ON VIEW nis2.v_profilo_acn IS 'Profilo ACN di tutte le organizzazioni in formato tabellare a colonne fisse (campi minimi), una riga per elemento, raggruppato in 8 sezioni (compreso l''elenco categorizzato delle attività e dei servizi).';

-- -----------------------------------------------------------------------------
-- Funzione: profilo ACN di una singola organizzazione, ordinato
-- -----------------------------------------------------------------------------
CREATE FUNCTION nis2.fn_profilo_acn(p_organizzazione_id bigint)
RETURNS SETOF nis2.v_profilo_acn
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM nis2.organizzazione WHERE organizzazione_id = p_organizzazione_id) THEN
        RAISE EXCEPTION 'Organizzazione % inesistente', p_organizzazione_id USING ERRCODE = 'NIS07';
    END IF;

    RETURN QUERY
        SELECT *
          FROM nis2.v_profilo_acn v
         WHERE v.organizzazione_id = p_organizzazione_id
         ORDER BY v.sezione, v.progressivo;
END;
$$;
COMMENT ON FUNCTION nis2.fn_profilo_acn(bigint) IS
  'Restituisce il profilo ACN (campi minimi) dell''organizzazione indicata, ordinato per sezione; errore NIS07 se l''organizzazione non esiste.';

-- -----------------------------------------------------------------------------
-- Funzione: profilo ACN come testo CSV (RFC 4180), per l'export senza accesso
-- al file system del server (es. da pgAdmin: copiare la cella o salvarla)
-- -----------------------------------------------------------------------------
CREATE FUNCTION nis2.fn_profilo_acn_csv(p_organizzazione_id bigint, p_separatore text DEFAULT ',')
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_csv text;
BEGIN
    IF p_separatore NOT IN (',', ';') THEN
        RAISE EXCEPTION 'Separatore non ammesso: usare , oppure ;';
    END IF;

    WITH righe AS (
        SELECT ARRAY[organizzazione_id::text, partita_iva, ragione_sociale, categoria_soggetto, settore,
                     sottosettore, sezione, progressivo::text, codice_elemento, descrizione_elemento,
                     dettaglio, criticita, riferimento, paese, email_contatto, data_estrazione::text] AS campi,
               sezione, progressivo
          FROM nis2.fn_profilo_acn(p_organizzazione_id)
    )
    SELECT 'organizzazione_id' || p_separatore || 'partita_iva' || p_separatore || 'ragione_sociale'
           || p_separatore || 'categoria_soggetto' || p_separatore || 'settore' || p_separatore || 'sottosettore'
           || p_separatore || 'sezione' || p_separatore || 'progressivo' || p_separatore || 'codice_elemento'
           || p_separatore || 'descrizione_elemento' || p_separatore || 'dettaglio' || p_separatore || 'criticita'
           || p_separatore || 'riferimento' || p_separatore || 'paese' || p_separatore || 'email_contatto'
           || p_separatore || 'data_estrazione' || E'\r\n'
           || coalesce(string_agg(
                  (SELECT string_agg(
                              CASE
                                  WHEN c IS NULL THEN ''
                                  WHEN c ~ ('["\r\n' || p_separatore || ']') THEN '"' || replace(c, '"', '""') || '"'
                                  ELSE c
                              END, p_separatore ORDER BY n)
                     FROM unnest(r.campi) WITH ORDINALITY AS u(c, n)),
                  E'\r\n' ORDER BY r.sezione, r.progressivo) || E'\r\n', '')
      INTO v_csv
      FROM righe r;

    RETURN v_csv;
END;
$$;
COMMENT ON FUNCTION nis2.fn_profilo_acn_csv(bigint, text) IS
  'Restituisce il profilo ACN dell''organizzazione come testo CSV conforme a RFC 4180 (intestazione, virgolette dove servono, CRLF). Separatore , (default) o ; per Excel in italiano.';

-- -----------------------------------------------------------------------------
-- Funzione: analisi d'impatto (quali asset e servizi dipendono, anche
-- indirettamente, da un asset)
-- -----------------------------------------------------------------------------
CREATE FUNCTION nis2.fn_impatto_asset(p_asset_id bigint)
RETURNS TABLE (livello integer, tipo text, codice varchar, denominazione varchar)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE dipendenti (asset_id, livello) AS (
        SELECT p_asset_id, 0
        UNION
        SELECT d.asset_id, dp.livello + 1
          FROM nis2.dipendenza_asset d
          JOIN dipendenti dp ON d.asset_richiesto_id = dp.asset_id
    ),
    minimo AS (
        SELECT asset_id, min(livello) AS livello FROM dipendenti GROUP BY asset_id
    )
    SELECT m.livello, 'ASSET', a.codice, a.denominazione
      FROM minimo m JOIN nis2.asset a ON a.asset_id = m.asset_id
     WHERE m.livello > 0
    UNION ALL
    SELECT min(m.livello) + 1, 'SERVIZIO', s.codice, s.denominazione
      FROM minimo m
      JOIN nis2.servizio_asset sa ON sa.asset_id = m.asset_id
      JOIN nis2.servizio s        ON s.servizio_id = sa.servizio_id
     GROUP BY s.codice, s.denominazione
     ORDER BY 1, 2, 3;
$$;
COMMENT ON FUNCTION nis2.fn_impatto_asset(bigint) IS
  'Analisi d''impatto: elenca asset e servizi che dipendono direttamente o indirettamente dall''asset indicato, con la distanza nel grafo.';

-- -----------------------------------------------------------------------------
-- Funzione diagnostica: piano di esecuzione della ricerca degli asset critici
-- su un volume realistico. Inserisce asset sintetici in una sottotransazione,
-- aggiorna le statistiche, cattura EXPLAIN ANALYZE e poi ANNULLA tutto
-- sollevando un errore interno intercettato: il database resta invariato.
-- Utilizzabile dal Query Tool di pgAdmin con una sola istruzione.
-- -----------------------------------------------------------------------------
CREATE FUNCTION nis2.fn_piano_asset_critici(p_asset_sintetici integer DEFAULT 30000,
                                            p_organizzazione_id bigint DEFAULT 1)
RETURNS TABLE ("QUERY PLAN" text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_piano text[] := '{}';
    v_riga  text;
BEGIN
    IF p_asset_sintetici NOT BETWEEN 1000 AND 200000 THEN
        RAISE EXCEPTION 'Numero di asset sintetici fuori intervallo (1000-200000)';
    END IF;

    BEGIN
        PERFORM nis2.fn_imposta_motivo('Dimostrazione piano di esecuzione (annullata)');
        INSERT INTO nis2.asset (organizzazione_id, codice, denominazione, tipo_asset_codice, classificazione_codice,
                                criticita_livello, rto_minuti, rpo_minuti, proprietario_persona_id)
        SELECT o.organizzazione_id, 'PERF-' || lpad(g::text, 6, '0'), 'Asset sintetico ' || g, 'HARDWARE', 'INTERNO',
               CASE WHEN g % 50 = 0 THEN 4 ELSE 1 + (g % 2) END, 240, 60,
               (SELECT min(persona_id) FROM nis2.persona)
          FROM generate_series(1, p_asset_sintetici) AS g
          JOIN LATERAL (SELECT organizzazione_id FROM nis2.organizzazione
                         ORDER BY organizzazione_id OFFSET (g % (SELECT count(*) FROM nis2.organizzazione)) LIMIT 1) o ON true;
        ANALYZE nis2.asset;

        FOR v_riga IN EXECUTE format(
            'EXPLAIN (ANALYZE, BUFFERS) SELECT codice, denominazione, criticita_livello, rto_minuti, rpo_minuti '
            'FROM nis2.asset WHERE organizzazione_id = %s AND criticita_livello >= 3', p_organizzazione_id)
        LOOP
            v_piano := v_piano || v_riga;
        END LOOP;

        RAISE EXCEPTION USING ERRCODE = 'NIS99', MESSAGE = 'annullamento dei dati sintetici';
    EXCEPTION WHEN SQLSTATE 'NIS99' THEN
        NULL;   -- sottotransazione annullata: asset sintetici, audit e statistiche tornano allo stato iniziale
    END;

    RETURN QUERY SELECT unnest(v_piano);
END;
$$;
COMMENT ON FUNCTION nis2.fn_piano_asset_critici(integer, bigint) IS
  'Diagnostica: restituisce il piano EXPLAIN ANALYZE della ricerca degli asset critici dopo aver inserito asset sintetici in una sottotransazione poi annullata (il database non viene modificato).';

COMMIT;

RESET client_min_messages;
