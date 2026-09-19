-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : sql/screenshot_query.sql
-- Scopo     : query per le figure della relazione. Il numero del blocco
--             coincide con il numero della figura (S02 = Figura 2, ...).
--             La Figura 1 è il diagramma ER (docs/er_diagram.png); la
--             Figura 17 è l'esito della suite di test (tests/...).
--             La Figura 18 (blocco S18) mostra il controllo degli accessi.
-- Strumento : TUTTI i blocchi si eseguono nel QUERY TOOL di pgAdmin 4 e non
--             contengono meta-comandi psql (\copy, \i, \d).
-- Prerequisito: deploy appena eseguito (00_run_all.sql) sul database nis2_acn.
--
-- Come usarlo
--   1. pgAdmin 4 > Servers > PostgreSQL 18 > Databases > nis2_acn (selezionato)
--      > menu Tools > Query Tool > icona "Open File" > questo file;
--   2. SELEZIONA con il mouse il testo di UN blocco (dalla prima istruzione al
--      punto e virgola finale) e premi F5: viene eseguito solo il testo selezionato;
--   3. fai lo screenshot della scheda indicata ("Data Output" o "Messages") e
--      salvalo come Sxx.png (xx = numero del blocco);
--   4. esegui i blocchi NELL'ORDINE: S02 deve precedere S03 e S04.
-- =============================================================================


-- =============================================================================
-- S02 | Figura 2 | scheda Data Output
-- Didascalia: Figura 2 – Asset ZNT-SER-01 prima dell'aggiornamento (versione 1)
-- Scopo     : stato iniziale dell'asset prima della modifica (versione 1,
--             nessuna riga di storico).
-- Atteso    : 1 riga, 8 colonne: codice ZNT-SER-01, denominazione
--             "Piattaforma di serializzazione", versione 1, rto_minuti 120,
--             rpo_minuti 5, valido_dal, modificato_da postgres, righe_storico 0.
-- =============================================================================
SELECT a.codice, a.denominazione, a.versione, a.rto_minuti, a.rpo_minuti,
       a.valido_dal, a.modificato_da,
       (SELECT count(*) FROM nis2.asset_storico s WHERE s.asset_id = a.asset_id) AS righe_storico
  FROM nis2.asset a
 WHERE a.codice = 'ZNT-SER-01';


-- =============================================================================
-- S03 | Figura 3 | scheda Data Output
-- Didascalia: Figura 3 – Versioning: versione corrente, versione archiviata e stato ricostruito a una data
-- Scopo     : un UPDATE con motivo dichiarato porta la versione a 2; il trigger
--             archivia la versione 1 nello storico; fn_asset_alla_data
--             ricostruisce lo stato precedente. Selezionare ed eseguire
--             ENTRAMBE le istruzioni (il blocco DO e la SELECT) insieme.
-- Atteso    : 3 righe, 8 colonne (fonte, versione, rto_minuti, valido_dal,
--             valido_al, operazione, utente, motivo):
--               corrente                              versione 2  rto 90
--               stato alla data (fn_asset_alla_data)  versione 1  rto 120
--               storico                               versione 1  rto 120  U  motivo valorizzato
--             Il valido_al della riga "storico" coincide con il valido_dal
--             della riga "corrente". Rieseguire il blocco non crea altre versioni.
-- =============================================================================
DO $$
BEGIN
    PERFORM nis2.fn_imposta_motivo('Esercitazione di continuità 2026: RTO ridotto a 90 minuti');
    UPDATE nis2.asset SET rto_minuti = 90 WHERE codice = 'ZNT-SER-01';
END;
$$;

SELECT 'corrente' AS fonte, a.versione, a.rto_minuti, a.valido_dal,
       NULL::timestamptz AS valido_al, NULL::char(1) AS operazione, a.modificato_da AS utente, NULL::text AS motivo
  FROM nis2.asset a WHERE a.codice = 'ZNT-SER-01'
UNION ALL
SELECT 'storico', s.versione, s.rto_minuti, s.valido_dal, s.valido_al, s.operazione, s.archiviato_da, s.motivo
  FROM nis2.asset_storico s WHERE s.codice = 'ZNT-SER-01'
UNION ALL
SELECT 'stato alla data (fn_asset_alla_data)', r.versione, r.rto_minuti, r.valido_dal, NULL, NULL, r.modificato_da, NULL
  FROM nis2.asset_storico s
 CROSS JOIN LATERAL nis2.fn_asset_alla_data(s.asset_id, s.valido_dal + interval '1 millisecond') r
 WHERE s.codice = 'ZNT-SER-01' AND s.versione = 1
 ORDER BY 1;


-- =============================================================================
-- S04 | Figura 4 | scheda Data Output
-- Didascalia: Figura 4 – Audit log: ultime modifiche con campi variati e motivo
-- Scopo     : audit generico in JSONB (chi, cosa, quando, perché, campi variati),
--             filtrato sulle sole modifiche (le INSERT del caricamento sono 212).
-- Atteso    : 3 righe, 10 colonne. La prima è l'UPDATE di S03 sulla tabella
--             asset: campi_modificati {rto_minuti}, rto_prima 120, rto_dopo 90.
--             Seguono la chiusura dell'incarico di punto di contatto
--             (assegnazione_ruolo, {data_fine}) e la revisione dell'RTO del MES
--             (480 -> 240), generate dal caricamento dei dati.
-- =============================================================================
SELECT audit_log_id, istante, utente, tabella, operazione, chiave, campi_modificati,
       dati_prima ->> 'rto_minuti' AS rto_prima,
       dati_dopo  ->> 'rto_minuti' AS rto_dopo,
       motivo
  FROM nis2.audit_log
 WHERE operazione = 'U'
 ORDER BY audit_log_id DESC
 LIMIT 5;


-- =============================================================================
-- S05 | Figura 5 | scheda Data Output
-- Didascalia: Figura 5 – Tabelle dello schema nis2 con tipologia e descrizione (COMMENT ON TABLE)
-- Scopo     : lo schema è dedicato (nis2) e ogni tabella è documentata.
-- Atteso    : 41 righe, 4 colonne (tabella, tipologia, colonne, descrizione):
--             1 audit, 17 dominio (lookup), 14 principale, 9 storico.
-- =============================================================================
SELECT c.relname AS tabella,
       CASE
           WHEN c.relname LIKE '%\_storico' THEN 'storico'
           WHEN c.relname = 'audit_log' THEN 'audit'
           WHEN c.relname IN ('paese','settore','sottosettore','tipologia_soggetto','categoria_soggetto',
                              'dimensione_impresa','livello_criticita','tipo_asset','classificazione_informazione',
                              'tipo_dipendenza_asset','tipo_fornitura','criterio_rilevanza','ruolo','modello_categorizzazione',
                              'categoria_rilevanza','macro_area','macro_area_modello') THEN 'dominio (lookup)'
           ELSE 'principale'
       END AS tipologia,
       (SELECT count(*) FROM information_schema.columns col
         WHERE col.table_schema = 'nis2' AND col.table_name = c.relname) AS colonne,
       obj_description(c.oid, 'pg_class') AS descrizione
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'nis2' AND c.relkind = 'r'
 ORDER BY 2, 1;


-- =============================================================================
-- S06 | Figura 6 | scheda Data Output
-- Didascalia: Figura 6 – Colonne della tabella asset con tipo, obbligatorietà e descrizione
-- Scopo     : data dictionary "vivo" letto dal catalogo.
-- Atteso    : 15 righe (una per colonna di nis2.asset), 5 colonne
--             (n, colonna, tipo, obbligatoria, descrizione).
-- =============================================================================
SELECT a.attnum AS n,
       a.attname AS colonna,
       format_type(a.atttypid, a.atttypmod) AS tipo,
       CASE WHEN a.attnotnull THEN 'sì' ELSE 'no' END AS obbligatoria,
       col_description(a.attrelid, a.attnum) AS descrizione
  FROM pg_attribute a
 WHERE a.attrelid = 'nis2.asset'::regclass AND a.attnum > 0 AND NOT a.attisdropped
 ORDER BY a.attnum;


-- =============================================================================
-- S07 | Figura 7 | scheda Messages
-- Didascalia: Figura 7 – Vincolo CHECK sulla partita IVA: inserimento rifiutato
-- Scopo     : un inserimento con partita IVA dalla cifra di controllo errata
--             viene rifiutato dal vincolo ck_organizzazione_piva. L'errore è
--             intercettato nel blocco DO: il messaggio è leggibile e la
--             transazione NON resta in stato di errore.
-- Atteso    : nessuna griglia; nella scheda Messages:
--               NOTICE:  INSERIMENTO RIFIUTATO (comportamento atteso)
--                 SQLSTATE : 23514
--                 tabella  : organizzazione
--                 vincolo  : ck_organizzazione_piva
--                 messaggio: new row for relation "organizzazione" violates check
--                            constraint "ck_organizzazione_piva"
--             (con PostgreSQL in italiano il messaggio è tradotto; SQLSTATE e
--             nome del vincolo restano identici).
-- =============================================================================
DO $$
DECLARE
    v_stato   text;
    v_tabella text;
    v_vincolo text;
    v_msg     text;
BEGIN
    INSERT INTO nis2.organizzazione (ragione_sociale, partita_iva, pec, telefono, email_funzionale,
                                     tipologia_soggetto_codice, categoria_soggetto_codice, dimensione_codice)
    VALUES ('Etna Idrica S.p.A.', '04738160871', 'protocollo@pec.etna-idrica.example',
            '+39 095 000 9999', 'nis@etna-idrica.example',
            'ACQUA_FORNITORI', 'ESSENZIALE', 'GRANDE');
    RAISE NOTICE 'ATTENZIONE: il vincolo non è intervenuto';
EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_stato = RETURNED_SQLSTATE, v_tabella = TABLE_NAME,
                            v_vincolo = CONSTRAINT_NAME, v_msg = MESSAGE_TEXT;
    RAISE NOTICE E'INSERIMENTO RIFIUTATO (comportamento atteso)\n  SQLSTATE : %\n  tabella  : %\n  vincolo  : %\n  messaggio: %',
                 v_stato, v_tabella, v_vincolo, v_msg;
END;
$$;


-- =============================================================================
-- S08 | Figura 8 | scheda Messages
-- Didascalia: Figura 8 – Trigger anti-ciclo: rifiutata una dipendenza che chiuderebbe un ciclo
-- Scopo     : la dipendenza ZNT-AD-01 -> ZNT-SER-01 chiuderebbe il ciclo
--             SER -> MES -> AD -> SER ed è rifiutata dal trigger con l'errore
--             applicativo NIS04, intercettato nel blocco DO.
-- Atteso    : nessuna griglia; nella scheda Messages:
--               NOTICE:  DIPENDENZA RIFIUTATA (comportamento atteso)
--                 SQLSTATE : NIS04
--                 messaggio: La dipendenza 6 -> 3 creerebbe un ciclo nel grafo degli asset
-- =============================================================================
DO $$
DECLARE
    v_stato text;
    v_msg   text;
BEGIN
    INSERT INTO nis2.dipendenza_asset (asset_id, asset_richiesto_id, tipo_dipendenza_codice)
    VALUES ((SELECT asset_id FROM nis2.asset WHERE codice = 'ZNT-AD-01'),
            (SELECT asset_id FROM nis2.asset WHERE codice = 'ZNT-SER-01'),
            'DATI');
    RAISE NOTICE 'ATTENZIONE: il trigger non è intervenuto';
EXCEPTION WHEN SQLSTATE 'NIS04' THEN
    GET STACKED DIAGNOSTICS v_stato = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RAISE NOTICE E'DIPENDENZA RIFIUTATA (comportamento atteso)\n  SQLSTATE : %\n  messaggio: %', v_stato, v_msg;
END;
$$;


-- =============================================================================
-- S09 | Figura 9 | scheda Data Output
-- Didascalia: Figura 9 – EXPLAIN ANALYZE: la ricerca degli asset critici usa l'indice parziale
-- Scopo     : la funzione diagnostica inserisce 30.000 asset sintetici in una
--             sottotransazione, aggiorna le statistiche, cattura il piano e
--             annulla tutto: il database resta invariato (durata: pochi secondi).
-- Atteso    : circa 12 righe, 1 colonna "QUERY PLAN", tra cui
--             "Bitmap Index Scan on ix_asset_critici" (o "Index Scan using
--             ix_asset_critici") e "rows=208" circa; Execution Time di pochi ms.
-- =============================================================================
SELECT * FROM nis2.fn_piano_asset_critici(30000, 1);


-- =============================================================================
-- S10 | Figura 10 | scheda Data Output
-- Didascalia: Figura 10 – Asset critici per organizzazione con RTO, RPO e proprietario
-- Atteso    : 19 righe (Zagara 8, Elymsol 6, TecPot 5), 9 colonne.
-- =============================================================================
SELECT ragione_sociale, codice, denominazione, tipo_asset, criticita,
       rto_minuti, rpo_minuti, ubicazione, proprietario
  FROM nis2.v_asset_critici
 ORDER BY organizzazione_id, criticita_livello DESC, codice;


-- =============================================================================
-- S11 | Figura 11 | scheda Data Output
-- Didascalia: Figura 11 – Servizi erogati con criticità, utenti impattati e Stati di erogazione
-- Atteso    : 10 righe (4 + 3 + 3), di cui 7 con perimetro_nis = true; 9 colonne.
-- =============================================================================
SELECT ragione_sociale, codice, denominazione, criticita, utenti_impattati,
       perimetro_nis, paesi_erogazione, asset_collegati, responsabile
  FROM nis2.v_servizi_erogati
 ORDER BY organizzazione_id, criticita_livello DESC, codice;


-- =============================================================================
-- S12 | Figura 12 | scheda Data Output
-- Didascalia: Figura 12 – Dipendenze da fornitori terzi con criterio di rilevanza e garanzie contrattuali
-- Atteso    : 16 righe (Zagara 7, Elymsol 5, TecPot 4), 10 colonne; una sola
--             riga con criterio NON_RILEVANTE (CRM di Elymsol Energia).
-- =============================================================================
SELECT ragione_sociale, codice_oggetto, fornitore, paese_fornitore, tipo_fornitura,
       criterio_rilevanza, codice_cpv, criticita, clausole_sicurezza, dpa_art28
  FROM nis2.v_dipendenze_terze_parti
 ORDER BY organizzazione_id, criticita_livello DESC, fornitore;


-- =============================================================================
-- S13 | Figura 13 | scheda Data Output
-- Didascalia: Figura 13 – Punti di contatto e responsabilità comunicate all'ACN
-- Atteso    : 19 righe (7 + 7 + 5), 7 colonne; per Zagara il punto di contatto
--             è Carmela Vitale (subentrata il 01/10/2025 con la procedura di
--             sostituzione).
-- =============================================================================
SELECT ragione_sociale, ruolo, nome, cognome, email, telefono, data_inizio
  FROM nis2.v_punti_contatto
 ORDER BY organizzazione_id, ruolo_codice, cognome;


-- =============================================================================
-- S14 | Figura 14 | scheda Data Output
-- Didascalia: Figura 14 – Vista v_profilo_acn: profilo in formato tabellare a campi fissi
-- Atteso    : 85 righe (34 + 27 + 24), 16 colonne; 8 sezioni, l'ultima è
--             8-CATEGORIZZAZIONE (elenco categorizzato, Det. ACN 155238/2026).
-- =============================================================================
SELECT *
  FROM nis2.v_profilo_acn
 ORDER BY organizzazione_id, sezione, progressivo;


-- =============================================================================
-- S15 | Figura 15 | scheda Data Output
-- Didascalia: Figura 15 – Funzione fn_profilo_acn(2): profilo di Elymsol Energia S.p.A.
-- Atteso    : 27 righe, 7 colonne; sezioni da 1-ANAGRAFICA a
--             8-CATEGORIZZAZIONE in ordine.
-- =============================================================================
SELECT sezione, progressivo, codice_elemento, descrizione_elemento, dettaglio, criticita, riferimento
  FROM nis2.fn_profilo_acn(2);


-- =============================================================================
-- S16 | Figura 16 | file CSV aperto nel Blocco note
-- Didascalia: Figura 16 – Profilo ACN di TecPot Digital Services S.r.l. esportato in CSV
-- Passi     : eseguire la query; nella barra sopra la griglia premere
--             "Save results to file" (icona con la freccia verso il basso, F8);
--             aprire il file .csv scaricato con il Blocco note e fare lo
--             screenshot del file.
-- Atteso    : 24 righe di dati + 1 riga di intestazione, 16 colonne.
-- =============================================================================
SELECT * FROM nis2.fn_profilo_acn(3);


-- =============================================================================
-- S18 | Figura 18 | scheda Data Output
-- Didascalia: Figura 18 – Controllo degli accessi: permessi effettivi dei ruoli e versione dello schema
-- Scopo     : mostra la matrice del minimo privilegio calcolata dal catalogo
--             (has_table_privilege) e la versione registrata in nis2_meta.
-- Atteso    : 6 righe, 6 colonne (oggetto, operazione, nis2_lettura,
--             nis2_redattore, nis2_revisore, versione_schema):
--               asset        SELECT   sì  sì  sì
--               asset        UPDATE   no  sì  no
--               asset        TRUNCATE no  no  no
--               ruolo        INSERT   no  no  no
--               audit_log    SELECT   no  no  sì
--               audit_log    UPDATE   no  no  no
-- =============================================================================
SELECT o.oggetto, o.operazione,
       CASE WHEN has_table_privilege('nis2_lettura',   'nis2.' || o.oggetto, o.operazione) THEN 'sì' ELSE 'no' END AS nis2_lettura,
       CASE WHEN has_table_privilege('nis2_redattore', 'nis2.' || o.oggetto, o.operazione) THEN 'sì' ELSE 'no' END AS nis2_redattore,
       CASE WHEN has_table_privilege('nis2_revisore',  'nis2.' || o.oggetto, o.operazione) THEN 'sì' ELSE 'no' END AS nis2_revisore,
       (SELECT max(versione) FROM nis2_meta.versione_schema) AS versione_schema
  FROM (VALUES (1, 'asset', 'SELECT'), (2, 'asset', 'UPDATE'), (3, 'asset', 'TRUNCATE'),
               (4, 'ruolo', 'INSERT'), (5, 'audit_log', 'SELECT'), (6, 'audit_log', 'UPDATE'))
       AS o(n, oggetto, operazione)
 ORDER BY o.n;
